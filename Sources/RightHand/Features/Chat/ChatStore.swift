import Foundation
import Observation

/// The conversation in the Assistant tab: sends questions to Claude or ChatGPT and streams answers.
@Observable
@MainActor
final class ChatStore {
    private(set) var messages: [ChatMessage] = []
    private(set) var isSending = false
    /// Providers that have an API key in the Keychain.
    private(set) var configuredProviders: Set<ChatProvider> = []

    var provider: ChatProvider {
        didSet { ChatSettings.provider = provider }
    }

    /// Bumped when Settings change, so the model name shown in the chat refreshes.
    private var settingsRevision = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init() {
        ChatSettings.registerDefaults()
        provider = ChatSettings.provider
        reloadKeys()
        NotificationCenter.default.addObserver(forName: Keychain.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadKeys() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsRevision += 1 }
        }
    }

    var hasKey: Bool { configuredProviders.contains(provider) }
    var modelName: String {
        _ = settingsRevision
        return ChatSettings.modelName(for: provider)
    }

    func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending, let apiKey = Keychain.read(provider.keychainAccount) else { return }

        let model = ChatSettings.model(for: provider)
        messages.append(ChatMessage(role: .user, text: question))
        let history = conversationHistory()
        let answer = ChatMessage(role: .assistant, text: "", provider: provider,
                                 modelName: ChatSettings.modelName(for: provider), isStreaming: true)
        messages.append(answer)
        isSending = true

        let stream: AsyncThrowingStream<ChatEvent, Error>
        do {
            switch provider {
            case .claude:
                stream = ClaudeService.stream(body: try ClaudeService.body(history: history, model: model),
                                              model: model, apiKey: apiKey)
            case .openAI:
                stream = OpenAIService.stream(body: try OpenAIService.body(history: history, model: model),
                                              apiKey: apiKey)
            }
        } catch {
            finish(answer.id, error: error.localizedDescription)
            return
        }

        task = Task { [weak self] in
            do {
                for try await event in stream {
                    self?.apply(event, to: answer.id)
                }
                self?.finish(answer.id, error: nil)
            } catch is CancellationError {
                self?.finish(answer.id, error: nil)
            } catch {
                self?.finish(answer.id, error: error.localizedDescription)
            }
        }
    }

    /// Stops the answer that is streaming in; what arrived so far is kept.
    func stop() {
        task?.cancel()
    }

    func newChat() {
        task?.cancel()
        task = nil
        messages = []
        isSending = false
    }

    func reloadKeys() {
        configuredProviders = Set(ChatProvider.allCases.filter { Keychain.read($0.keychainAccount) != nil })
    }

    // MARK: Private

    /// Questions and answers the AI should remember: declined or failed exchanges are left out
    /// (only ever at the end of a chat, so earlier turns never change).
    private func conversationHistory() -> [ChatMessage] {
        var history: [ChatMessage] = []
        for (index, message) in messages.enumerated() where message.role == .user {
            let isNewQuestion = index == messages.count - 1
            let answer = messages.indices.contains(index + 1) ? messages[index + 1] : nil
            if isNewQuestion {
                history.append(message)
            } else if let answer, answer.belongsInHistory {
                history.append(message)
                history.append(answer)
            }
        }
        return history
    }

    private func apply(_ event: ChatEvent, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case .text(let text):
            messages[index].text += text
        case .finished(let claudeContent, let declined):
            messages[index].claudeContent = claudeContent
            messages[index].isDeclined = declined
        }
    }

    private func finish(_ id: UUID, error: String?) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].isStreaming = false
            messages[index].errorMessage = error
        }
        isSending = false
        task = nil
    }
}
