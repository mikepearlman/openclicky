import Combine
import Foundation

nonisolated enum OpenClickyExternalAPITransport: String {
    case responses
    case chatCompletions
    case anthropicMessages
}

final class OpenClickyExternalModelAPI {
    private let provider: OpenClickyModelProvider
    private let apiKey: String
    private let baseURL: URL
    private let sessionID = UUID().uuidString
    private let session: URLSession

    init(provider: OpenClickyModelProvider) throws {
        self.provider = provider

        switch provider {
        case .openCodeGo:
            guard let key = AppBundleConfiguration.openCodeGoAPIKey() else {
                throw Self.error("OpenCode Go needs a key. Add it in Models settings.")
            }
            apiKey = key
            baseURL = AppBundleConfiguration.openCodeGoBaseURL()
        case .nvidia:
            guard let key = AppBundleConfiguration.nvidiaAPIKey() else {
                throw Self.error("NVIDIA needs a key. Add it in Models settings.")
            }
            apiKey = key
            baseURL = AppBundleConfiguration.nvidiaBaseURL()
        default:
            throw Self.error("This model does not use an outside model service.")
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func analyze(
        model: OpenClickyModelOption,
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String,
        onTextChunk: @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        let transport = Self.transport(provider: provider, modelID: model.remoteModelID)
        let endpoint: String
        let body: [String: Any]

        switch transport {
        case .responses:
            endpoint = "responses"
            body = responsesBody(
                modelID: model.remoteModelID,
                maxOutputTokens: model.maxOutputTokens,
                images: images,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                userPrompt: userPrompt
            )
        case .chatCompletions:
            endpoint = "chat/completions"
            body = chatBody(
                modelID: model.remoteModelID,
                maxOutputTokens: model.maxOutputTokens,
                images: images,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                userPrompt: userPrompt
            )
        case .anthropicMessages:
            endpoint = "messages"
            body = messagesBody(
                modelID: model.remoteModelID,
                maxOutputTokens: model.maxOutputTokens,
                images: images,
                systemPrompt: systemPrompt,
                conversationHistory: conversationHistory,
                userPrompt: userPrompt
            )
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("OpenClicky/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .openCodeGo {
            request.setValue(sessionID, forHTTPHeaderField: "x-opencode-session")
        }
        if transport == .anthropicMessages {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Self.error("The model service returned an invalid response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw Self.error(Self.apiErrorMessage(data: data, statusCode: http.statusCode))
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Self.error("The model service returned unreadable data.")
        }

        let text = Self.outputText(from: payload, transport: transport)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw Self.error("The selected model returned no answer.")
        }

        onTextChunk(text)
        return text
    }

    static func fetchModelIDs(provider: OpenClickyModelProvider) async throws -> [String] {
        let api = try OpenClickyExternalModelAPI(provider: provider)
        var request = URLRequest(url: api.baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(api.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("OpenClicky/1.0", forHTTPHeaderField: "User-Agent")
        if provider == .openCodeGo {
            request.setValue(api.sessionID, forHTTPHeaderField: "x-opencode-session")
        }

        let (data, response) = try await api.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw error(apiErrorMessage(data: data, statusCode: statusCode))
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = payload["data"] as? [[String: Any]] else {
            throw error("The service returned an unreadable model list.")
        }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    static func transport(provider: OpenClickyModelProvider, modelID: String) -> OpenClickyExternalAPITransport {
        guard provider == .openCodeGo else { return .chatCompletions }

        let lowercasedID = modelID.lowercased()
        if lowercasedID.hasPrefix("minimax-") || lowercasedID.hasPrefix("qwen") {
            return .anthropicMessages
        }
        if lowercasedID.hasPrefix("gpt-")
            || lowercasedID.hasPrefix("grok-")
            || lowercasedID.hasPrefix("muse-") {
            return .responses
        }
        return .chatCompletions
    }

    private func responsesBody(
        modelID: String,
        maxOutputTokens: Int,
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String
    ) -> [String: Any] {
        var input: [[String: Any]] = conversationHistory.flatMap { turn in
            [
                ["role": "user", "content": [["type": "input_text", "text": turn.userPlaceholder]]],
                ["role": "assistant", "content": [["type": "output_text", "text": turn.assistantResponse]]]
            ]
        }
        var content: [[String: Any]] = images.flatMap { image in
            [
                ["type": "input_text", "text": image.label],
                ["type": "input_image", "image_url": dataURL(for: image.data)]
            ]
        }
        content.append(["type": "input_text", "text": userPrompt])
        input.append(["role": "user", "content": content])
        return [
            "model": modelID,
            "instructions": systemPrompt,
            "max_output_tokens": maxOutputTokens,
            "stream": false,
            "input": input
        ]
    }

    private func chatBody(
        modelID: String,
        maxOutputTokens: Int,
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String
    ) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for turn in conversationHistory {
            messages.append(["role": "user", "content": turn.userPlaceholder])
            messages.append(["role": "assistant", "content": turn.assistantResponse])
        }

        if images.isEmpty {
            messages.append(["role": "user", "content": userPrompt])
        } else {
            var content: [[String: Any]] = images.flatMap { image in
                [
                    ["type": "text", "text": image.label],
                    ["type": "image_url", "image_url": ["url": dataURL(for: image.data)]]
                ]
            }
            content.append(["type": "text", "text": userPrompt])
            messages.append(["role": "user", "content": content])
        }

        return [
            "model": modelID,
            "messages": messages,
            "max_tokens": maxOutputTokens,
            "stream": false
        ]
    }

    private func messagesBody(
        modelID: String,
        maxOutputTokens: Int,
        images: [(data: Data, label: String)],
        systemPrompt: String,
        conversationHistory: [(userPlaceholder: String, assistantResponse: String)],
        userPrompt: String
    ) -> [String: Any] {
        var messages: [[String: Any]] = []
        for turn in conversationHistory {
            messages.append(["role": "user", "content": turn.userPlaceholder])
            messages.append(["role": "assistant", "content": turn.assistantResponse])
        }

        var content: [[String: Any]] = images.flatMap { image in
            [
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": mediaType(for: image.data),
                        "data": image.data.base64EncodedString()
                    ]
                ],
                ["type": "text", "text": image.label]
            ]
        }
        content.append(["type": "text", "text": userPrompt])
        messages.append(["role": "user", "content": content])

        return [
            "model": modelID,
            "system": systemPrompt,
            "messages": messages,
            "max_tokens": maxOutputTokens,
            "stream": false
        ]
    }

    private func dataURL(for data: Data) -> String {
        "data:\(mediaType(for: data));base64,\(data.base64EncodedString())"
    }

    private func mediaType(for data: Data) -> String {
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        return data.count >= 4 && [UInt8](data.prefix(4)) == pngSignature ? "image/png" : "image/jpeg"
    }

    private static func outputText(from payload: [String: Any], transport: OpenClickyExternalAPITransport) -> String {
        switch transport {
        case .responses:
            if let outputText = payload["output_text"] as? String { return outputText }
            let output = payload["output"] as? [[String: Any]] ?? []
            return output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .compactMap { $0["text"] as? String }
                .joined()
        case .chatCompletions:
            guard let choices = payload["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else { return "" }
            return (message["content"] as? String) ?? ""
        case .anthropicMessages:
            let content = payload["content"] as? [[String: Any]] ?? []
            return content.compactMap { $0["text"] as? String }.joined()
        }
    }

    private static func apiErrorMessage(data: Data, statusCode: Int) -> String {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = payload["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let detail = payload["detail"] as? String { return detail }
            if let message = payload["message"] as? String { return message }
        }
        return "The model service returned error \(statusCode)."
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "OpenClickyExternalModelAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@MainActor
final class OpenClickyExternalModelStore: ObservableObject {
    @Published private(set) var openCodeGoModels: [OpenClickyModelOption] = []
    @Published private(set) var nvidiaModels: [OpenClickyModelOption] = []
    @Published private(set) var openCodeGoStatus = "Checking your OpenCode Go account."
    @Published private(set) var nvidiaStatus = "Checking your NVIDIA account."
    @Published private(set) var isRefreshing = false

    var recommendedModels: [OpenClickyModelOption] {
        recommended(
            available: openCodeGoModels,
            preferredIDs: OpenClickyModelCatalog.recommendedOpenCodeGoModelIDs
        ) + recommended(
            available: nvidiaModels,
            preferredIDs: OpenClickyModelCatalog.recommendedNVIDIAModelIDs
        )
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let openCodeResult = await load(provider: .openCodeGo)
        let nvidiaResult = await load(provider: .nvidia)
        apply(openCodeResult, provider: .openCodeGo)
        apply(nvidiaResult, provider: .nvidia)
    }

    private func load(provider: OpenClickyModelProvider) async -> Result<[String], Error> {
        do {
            return .success(try await OpenClickyExternalModelAPI.fetchModelIDs(provider: provider))
        } catch {
            return .failure(error)
        }
    }

    private func apply(_ result: Result<[String], Error>, provider: OpenClickyModelProvider) {
        switch result {
        case .success(let modelIDs):
            let options = modelIDs.compactMap {
                OpenClickyModelCatalog.externalModelOption(provider: provider, remoteModelID: $0)
            }
            if provider == .openCodeGo {
                openCodeGoModels = options
                openCodeGoStatus = "Connected. \(options.count) models listed."
            } else {
                nvidiaModels = options.filter {
                    OpenClickyModelCatalog.recommendedNVIDIAModelIDs.contains($0.remoteModelID)
                }
                nvidiaStatus = "Connected. \(nvidiaModels.count) current free model choices."
            }
        case .failure(let error):
            if provider == .openCodeGo {
                openCodeGoModels = []
                openCodeGoStatus = error.localizedDescription
            } else {
                nvidiaModels = []
                nvidiaStatus = error.localizedDescription
            }
        }
    }

    private func recommended(
        available: [OpenClickyModelOption],
        preferredIDs: [String]
    ) -> [OpenClickyModelOption] {
        preferredIDs.compactMap { preferredID in
            available.first { $0.remoteModelID == preferredID }
        }
    }
}
