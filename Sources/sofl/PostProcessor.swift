import Foundation

enum PostProcessMode {
    case normalize
    case translate
}

class PostProcessor {
    let config: PostProcessConfig

    init(config: PostProcessConfig) {
        self.config = config
    }

    func process(_ text: String, mode: PostProcessMode) async throws -> String {
        switch mode {
        case .normalize:
            return try await processOllama(text, mode: mode)
        case .translate:
            if !config.openaiApiKey.isEmpty {
                return try await processOpenAI(text)
            }
            return try await processOllama(text, mode: mode)
        }
    }

    private func processOpenAI(_ text: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.openaiApiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = config.timeout

        let systemPrompt = config.translatePrompt

        let body: [String: Any] = [
            "model": config.openaiModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.1,
            "max_tokens": 1024
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            print("OpenAI error \(statusCode): \(body)")
            throw PostProcessError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PostProcessError.invalidResponse
        }

        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }

    private func processOllama(_ text: String, mode: PostProcessMode) async throws -> String {
        let url = URL(string: "\(config.ollamaUrl)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = config.timeout

        let basePrompt: String
        switch mode {
        case .normalize:
            basePrompt = config.normalizePrompt
        case .translate:
            basePrompt = config.translatePrompt
        }
        let prompt = "\(basePrompt)\n\n\(text)"

        let body: [String: Any] = [
            "model": config.model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.1, "num_predict": 512]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PostProcessError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["response"] as? String else {
            throw PostProcessError.invalidResponse
        }

        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }
}

enum PostProcessError: Error {
    case httpError
    case invalidResponse
}
