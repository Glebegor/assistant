import Foundation
import Observation

/// The chat models each AI offers on your key, fetched from the provider (so new models show up
/// by themselves) and remembered; a built-in list is used until the first fetch.
@Observable
@MainActor
final class ModelCatalog {
    static let shared = ModelCatalog()

    struct Model: Codable, Hashable, Identifiable {
        let id: String
        let name: String
    }

    private(set) var models: [ChatProvider: [Model]] = [:]
    private(set) var loading: Set<ChatProvider> = []
    /// Why the last fetch failed, shown under the model picker in Settings.
    private(set) var errors: [ChatProvider: String] = [:]
    private static let cacheKey = "chat.modelCatalog.v2"

    init() {
        let cached = (UserDefaults.standard.data(forKey: Self.cacheKey))
            .flatMap { try? JSONDecoder().decode([String: [Model]].self, from: $0) } ?? [:]
        for provider in ChatProvider.allCases {
            models[provider] = cached[provider.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? Self.builtIn(provider)
        }
    }

    func list(for provider: ChatProvider) -> [Model] {
        let list = models[provider] ?? Self.builtIn(provider)
        // GitHub Models ids have a publisher ("openai/gpt-4.1"), the subscription's don't.
        if provider == .copilot, list.contains(where: { $0.id.contains("/") }) == CopilotAuth.isSignedIn { return Self.builtIn(provider) }
        return list
    }

    /// After signing in to or out of the Copilot subscription.
    func reset(_ provider: ChatProvider) {
        models[provider] = Self.builtIn(provider)
        Task { await refresh(provider) }
    }

    func name(of id: String, provider: ChatProvider) -> String {
        list(for: provider).first { $0.id == id }?.name ?? id
    }

    /// Fetches every provider that has a key (called at launch and from Settings).
    func refreshAll() {
        for provider in ChatProvider.allCases where Keychain.read(provider.keychainAccount) != nil {
            Task { await refresh(provider) }
        }
    }

    func refresh(_ provider: ChatProvider) async {
        guard let key = Keychain.read(provider.keychainAccount), !loading.contains(provider) else { return }
        loading.insert(provider)
        defer { loading.remove(provider) }
        let fetched: [Model]
        do {
            fetched = try await Self.fetch(provider, key: key)
        } catch {
            errors[provider] = error.localizedDescription
            return
        }
        guard !fetched.isEmpty else {
            errors[provider] = L("The provider listed no models this key can use for chat with tools.")
            return
        }
        errors[provider] = nil
        models[provider] = fetched
        let cache = Dictionary(uniqueKeysWithValues: models.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(try? JSONEncoder().encode(cache), forKey: Self.cacheKey)
    }

    // MARK: Fetching

    private static func fetch(_ provider: ChatProvider, key: String) async throws -> [Model] {
        switch provider {
        case .claude:
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let json = try await get(request)
            return (json["data"]?.array ?? []).compactMap { model in
                model["id"]?.string.map { Model(id: $0, name: model["display_name"]?.string ?? $0) }
            }
        case .openAI:
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let ids = (try await get(request)["data"]?.array ?? []).compactMap { $0["id"]?.string }
            // GPT models first (newest on top), then the o-series reasoning models.
            return ids.filter(isOpenAIChatModel).sorted { a, b in
                let aGPT = a.hasPrefix("gpt-"), bGPT = b.hasPrefix("gpt-")
                return aGPT != bGPT ? aGPT : newestFirst(a, b)
            }.map { Model(id: $0, name: $0) }
        case .copilot where CopilotAuth.isSignedIn:
            // The subscription's models, as in the VS Code model picker. Models that only speak the
            // newer Responses API (some Codex ones) are left out.
            let items = try await get(CopilotAuth.request(path: "models", oauth: key))["data"]?.array ?? []
            var seen = Set<String>()
            return items.filter { model in
                let supports = model["capabilities"]?["supports"]
                let endpoints = model["supported_endpoints"]?.array?.compactMap(\.string)
                return model["capabilities"]?["type"]?.string == "chat" && model["model_picker_enabled"]?.bool != false
                    && supports?["tool_calls"]?.bool == true && (endpoints == nil || endpoints!.contains("/chat/completions"))
                    && model["policy"]?["state"]?.string != "disabled"
            }.compactMap { model in
                guard let id = model["id"]?.string, seen.insert(id).inserted else { return nil }
                return Model(id: id, name: model["name"]?.string ?? id)
            }
        case .copilot:
            var request = URLRequest(url: URL(string: "https://models.github.ai/catalog/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            let json = try await get(request)
            let items = json.array ?? json["models"]?.array ?? json["data"]?.array ?? []
            // Models that can use tools, chat ones first; the newest of a family on top.
            return items.filter { model in
                let capabilities = (model["capabilities"]?.array ?? []).compactMap(\.string)
                let output = (model["supported_output_modalities"]?.array ?? []).compactMap(\.string)
                return capabilities.contains("tool-calling") && (output.isEmpty || output.contains("text"))
            }.compactMap { model in
                model["id"]?.string.map { Model(id: $0, name: model["name"]?.string ?? $0) }
            }.sorted { a, b in
                let aOpenAI = a.id.hasPrefix("openai/"), bOpenAI = b.id.hasPrefix("openai/")
                return aOpenAI != bOpenAI ? aOpenAI : newestFirst(a.id, b.id)
            }
        case .gemini:
            let request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=\(key)")!)
            let items = try await get(request)["models"]?.array ?? []
            return items.filter { model in
                let id = model["name"]?.string ?? ""
                let skip = ["embedding", "image", "tts", "live", "aqa", "vision", "learnlm", "imagen", "veo"]
                return id.contains("gemini") && !skip.contains { id.contains($0) }
                    && (model["supportedGenerationMethods"]?.array ?? []).contains("generateContent")
            }.compactMap { model in
                (model["name"]?.string).map { name in
                    let id = name.replacingOccurrences(of: "models/", with: "")
                    return Model(id: id, name: model["displayName"]?.string ?? id)
                }
            }.sorted { newestFirst($0.id, $1.id) }
        }
    }

    private static func get(_ request: URLRequest) async throws -> JSONValue {
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            throw ChatError(message: L("The key was rejected (error %lld). Check it, and for GitHub that the token has “Models: read”.", status))
        }
        guard status == 200, let json = JSONValue.parse(data) else {
            throw ChatError(message: L("Couldn't load the model list (error %lld).", status))
        }
        return json
    }

    /// Chat models only: no audio, images, realtime, search, embeddings, old or dated snapshots.
    static func isOpenAIChatModel(_ id: String) -> Bool {
        guard id.hasPrefix("gpt-") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") else { return false }
        let skip = ["audio", "realtime", "tts", "transcribe", "image", "search", "live", "instruct", "codex", "-pro",
                    "gpt-3.5", "gpt-4-", "chat-latest", "translate", "whisper"]
        if skip.contains(where: id.contains) || id == "gpt-4" { return false }
        // "gpt-4.1-2025-04-14" duplicates "gpt-4.1".
        return id.range(of: "-20\\d\\d-\\d\\d-\\d\\d$", options: .regularExpression) == nil
    }

    /// Higher version numbers first ("gpt-6.1-sol" before "gpt-5.5").
    nonisolated static func newestFirst(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric]) == .orderedDescending
    }

    static func builtIn(_ provider: ChatProvider) -> [Model] {
        switch provider {
        case .claude: ChatSettings.claudeModels.map { Model(id: $0.id, name: $0.name) }
        case .openAI: ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5", "gpt-5-mini", "gpt-4.1", "gpt-4o", "o3", "o4-mini"].map { Model(id: $0, name: $0) }
        case .copilot where CopilotAuth.isSignedIn:
            [("gpt-4.1", "GPT-4.1"), ("gpt-5-mini", "GPT-5 mini"), ("claude-sonnet-4", "Claude Sonnet 4")].map { Model(id: $0.0, name: $0.1) }
        case .copilot: ChatSettings.copilotModels.map { Model(id: $0.id, name: $0.name) }
        case .gemini: [("gemini-2.5-pro", "Gemini 2.5 Pro"), ("gemini-2.5-flash", "Gemini 2.5 Flash"), ("gemini-2.5-flash-lite", "Gemini 2.5 Flash-Lite")]
            .map { Model(id: $0.0, name: $0.1) }
        }
    }
}
