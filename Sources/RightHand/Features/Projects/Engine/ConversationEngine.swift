import Foundation
import Observation

/// A question to you before a tool runs: "Claude wants to read README.md".
struct ToolApproval: Identifiable {
    let id = UUID()
    let toolName: String
    let toolDisplayName: String
    let action: String
    /// The exact command or text, when there is one.
    let detail: String?
    let canAlwaysAllow: Bool
    /// "For This Project" is offered in project chats, not in the notch chat.
    let canAllowForProject: Bool
}

enum ApprovalDecision {
    case deny, allowOnce, alwaysAllow
    /// Until this chat ends (a new chat or quitting RightHand).
    case allowForChat
    /// For every chat in this project, until you remove it in the project's settings.
    case allowForProject
}

/// Runs one project chat: sends messages, streams answers, runs tools (asking first), saves.
@Observable
@MainActor
final class ConversationEngine {
    private(set) var chat: ProjectChat
    private(set) var isRunning = false
    /// The answer streaming in right now.
    private(set) var streamingText = ""
    /// "Reading README.md…", shown while a tool runs or a reply is being prepared.
    private(set) var activity: String?
    private(set) var pendingApproval: ToolApproval?
    var errorMessage: String?
    /// Called when a permission question appears (the notch opens to show it).
    @ObservationIgnored var onApprovalNeeded: (() -> Void)?

    @ObservationIgnored private let project: () -> Project?
    @ObservationIgnored private let onSave: (ProjectChat) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var approvalContinuation: CheckedContinuation<ApprovalDecision, Never>?
    @ObservationIgnored private var turnNumber = 0
    /// Tools you allowed for the rest of this chat.
    @ObservationIgnored private var allowedForChat: Set<String> = []
    private static let maxToolRounds = 30

    init(chat: ProjectChat, project: @escaping () -> Project?, onSave: @escaping (ProjectChat) -> Void) {
        self.chat = chat
        self.project = project
        self.onSave = onSave
    }

    var display: [ChatDisplayItem] { ChatDisplayItem.items(for: chat) }

    func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isRunning, let project = project() else { return }
        guard let apiKey = Keychain.read(chat.provider.keychainAccount) else {
            errorMessage = L("Add your %@ API key in Settings → Assistant.", chat.provider.title)
            return
        }
        errorMessage = nil

        // If the project changed since the chat started, tell the AI in a separate message.
        let fingerprint = ProjectContext.fingerprint(of: project)
        let update: String? = fingerprint == chat.contextFingerprint ? nil
            : "The project was updated. This replaces the earlier project context:\n\n"
              + ProjectContext.systemPrompt(for: project, provider: chat.provider)
        chat.contextFingerprint = fingerprint
        if chat.messages.isEmpty { chat.title = String(question.prefix(50)) }
        chat.messages += client.userMessages(text: question, contextUpdate: update)
        save()

        let tools = Toolbox.tools(for: project)
        task = Task { await run(tools: tools, apiKey: apiKey) }
    }

    func stop() {
        approvalContinuation?.resume(returning: .deny)
        approvalContinuation = nil
        task?.cancel()
    }

    func resolveApproval(_ decision: ApprovalDecision) {
        pendingApproval = nil
        approvalContinuation?.resume(returning: decision)
        approvalContinuation = nil
    }

    // MARK: The loop

    private var client: ModelClient {
        chat.provider == .claude ? ClaudeClient() : OpenAIClient()
    }

    private func run(tools: [AssistantTool], apiKey: String) async {
        isRunning = true
        defer {
            isRunning = false
            streamingText = ""
            activity = nil
            pendingApproval = nil
            save()
        }
        let byName = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        do {
            for _ in 0..<Self.maxToolRounds {
                try Task.checkCancellation()
                try await shortenIfNeeded(apiKey: apiKey)

                activity = L("Thinking…")
                streamingText = ""
                turnNumber += 1
                let number = turnNumber
                let turn = try await client.turn(system: chat.system, chat: chat, tools: tools, apiKey: apiKey) { event in
                    // The main queue keeps the streamed pieces in order.
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated { self?.handle(event, turn: number) }
                    }
                }
                turnNumber += 1 // late pieces of this reply are ignored from now on
                chat.messages.append(turn.message)
                chat.updatedAt = Date()
                streamingText = ""
                save()

                if turn.stopReason == "refusal" {
                    errorMessage = L("%@ declined this request. Try rephrasing it.", chat.provider.title)
                    // Tools from a declined turn never run, but every call still needs an answer.
                    answer(turn.toolCalls, with: .error("Not run: the request was declined."))
                    return
                }
                guard !turn.toolCalls.isEmpty else { return }

                var results: [(call: ToolCall, output: ToolOutput)] = []
                for call in turn.toolCalls {
                    if Task.isCancelled {
                        results.append((call, .error("Stopped by the user.")))
                        continue
                    }
                    results.append((call, await execute(call, tools: byName, truncated: turn.stopReason == "max_tokens")))
                }
                chat.messages += client.toolResultMessages(results)
                save()
            }
            errorMessage = L("Stopped after %lld tool steps. Send a message to continue.", Self.maxToolRounds)
        } catch is CancellationError {
            // Stopped by the user; what arrived so far is kept.
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    private func execute(_ call: ToolCall, tools: [String: AssistantTool], truncated: Bool) async -> ToolOutput {
        guard let tool = tools[call.name] else { return .error("Unknown tool \(call.name).") }
        guard !truncated else { return .error("The request was cut off before this call was complete. Try again with less at once.") }
        guard let input = call.input else {
            return .error(JSONValue.object(["INVALID_JSON": .string(call.rawInput)]).jsonString)
        }

        let action = tool.describe(input)
        let projectID = chat.projectID
        let isAllowed = allowedForChat.contains(tool.name) || ProjectPermissions.isAllowed(tool.name, in: projectID)
            || (tool.canAlwaysAllow && !tool.alwaysAsks(input) && ToolPermissions.isAlwaysAllowed(tool.name))
        if !isAllowed {
            activity = L("Waiting for your permission…")
            let decision = await withCheckedContinuation { continuation in
                approvalContinuation = continuation
                pendingApproval = ToolApproval(toolName: tool.name, toolDisplayName: tool.displayName, action: action,
                                               detail: tool.detail(input), canAlwaysAllow: tool.canAlwaysAllow && !tool.alwaysAsks(input),
                                               canAllowForProject: projectID != ChatStore.projectID)
                onApprovalNeeded?()
            }
            switch decision {
            case .deny: return .error("The user declined: \(action).")
            case .alwaysAllow: if tool.canAlwaysAllow { ToolPermissions.setAlwaysAllowed(tool.name, true) }
            case .allowOnce: break
            case .allowForChat: allowedForChat.insert(tool.name)
            case .allowForProject: ProjectPermissions.set(tool.name, allowed: true, in: projectID)
            }
        }
        activity = action + "…"
        return await tool.run(input)
    }

    /// Answers tool calls that won't run, so the conversation stays valid.
    private func answer(_ calls: [ToolCall], with output: ToolOutput) {
        guard !calls.isEmpty else { return }
        chat.messages += client.toolResultMessages(calls.map { ($0, output) })
    }

    /// ChatGPT has no built-in compaction, so long chats are summarized here.
    private func shortenIfNeeded(apiKey: String) async throws {
        guard chat.provider == .openAI else { return }
        let client = OpenAIClient()
        if let shortened = try? await client.shortened(chat, system: chat.system, apiKey: apiKey) {
            activity = L("Summarizing the earlier conversation…")
            chat.contextStart = shortened.start
            chat.summary = shortened.summary
            save()
        }
    }

    private func handle(_ event: TurnEvent, turn: Int) {
        guard turn == turnNumber else { return }
        switch event {
        case .text(let text):
            streamingText += text
            activity = nil
        case .usingTool(let name):
            activity = L("Preparing %@…", Toolbox.displayName(of: name))
        case .compacting:
            activity = L("Summarizing the earlier conversation…")
        }
    }

    private func save() {
        chat.updatedAt = Date()
        onSave(chat)
    }
}
