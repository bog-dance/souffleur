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
        let url = URL(string: "\(config.ollamaUrl)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = config.timeout

        let prompt: String
        switch mode {
        case .normalize:
            prompt = """
            Clean up this dictated text. Fix punctuation, capitalization, grammar. \
            Remove filler words (ну, типу, от, ем). \
            IMPORTANT: Keep the SAME language as the input. Do NOT translate. \
            English tech terms (AWS, infrastructure, engineering, deployment, Terraform, etc.) must stay in Latin script. \
            Return ONLY the cleaned text, nothing else:\n\n\(text)
            """
        case .translate:
            prompt = """
            You are a communications assistant for an Infrastructure Team Lead at a tech company. \
            Translate and rewrite the following dictated text into polished, professional English. \
            This is for Slack messages, emails, or posts visible to C-level executives and stakeholders. \
            Tone: confident, clear, diplomatic. Not robotic, not overly formal - natural professional English. \
            Keep technical terms accurate. Remove filler words and hesitations. \
            If the input sounds emotional or blunt, soften it to be diplomatically appropriate while keeping the core message. \
            Return ONLY the final English text, nothing else:\n\n\(text)
            """
        }

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
