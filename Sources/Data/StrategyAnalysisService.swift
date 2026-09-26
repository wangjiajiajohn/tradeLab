import Foundation

struct StrategyDraft: Decodable, Sendable {
    let kind: String
    let suggestedName: String?
    let shortWindow: Int?
    let longWindow: Int?
    let entryWindow: Int?
    let exitWindow: Int?
    let missingFields: [String]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case kind
        case suggestedName = "suggested_name"
        case shortWindow = "short_window"
        case longWindow = "long_window"
        case entryWindow = "entry_window"
        case exitWindow = "exit_window"
        case missingFields = "missing_fields"
        case warnings
    }
}

enum StrategyAnalysisError: LocalizedError {
    case unavailable
    case invalidResponse
    case provider(String)

    var errorDescription: String? {
        localizedDescription(locale: .current)
    }

    func localizedDescription(locale: Locale) -> String {
        switch self {
        case .unavailable:
            AppLocalization.string("strategy_analysis.not_configured", locale: locale)
        case .invalidResponse:
            AppLocalization.string("strategy_analysis.invalid_response", locale: locale)
        case let .provider(message):
            message
        }
    }
}

enum StrategyAnalysisService {
    private struct OpenAICompatibleRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct ResponseFormat: Encodable { let type: String }

        let model: String
        let messages: [Message]
        let responseFormat: ResponseFormat?
        let temperature: Double?

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case responseFormat = "response_format"
        }
    }

    private struct OpenAICompatibleResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct AnthropicRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct AnthropicResponse: Decodable {
        struct Content: Decodable {
            let type: String
            let text: String?
        }
        let content: [Content]
    }

    private struct ErrorEnvelope: Decodable {
        struct APIError: Decodable { let message: String? }
        let error: APIError?
    }

    static func analyze(
        _ description: String,
        provider: AIProvider,
        model: String,
        locale: Locale = .current,
        session: URLSession = .shared
    ) async throws -> StrategyDraft {
        guard provider != .disabled,
              let apiKey = CredentialStore.value(for: .aiAPIKey),
              !apiKey.isEmpty,
              let endpoint = endpoint(for: provider)
        else { throw StrategyAnalysisError.unavailable }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .claude {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONEncoder().encode(
                AnthropicRequest(
                    model: model,
                    maxTokens: 1_500,
                    system: systemPrompt,
                    messages: [.init(role: "user", content: description)]
                )
            )
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(
                OpenAICompatibleRequest(
                    model: model,
                    messages: [
                        .init(role: "system", content: systemPrompt),
                        .init(role: "user", content: description)
                    ],
                    responseFormat: provider == .kimi ? nil : .init(type: "json_object"),
                    temperature: provider == .kimi ? nil : 0
                )
            )
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StrategyAnalysisError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error?.message)
                ?? String(
                    format: AppLocalization.string("strategy_analysis.http_error_format", locale: locale),
                    http.statusCode
                )
            throw StrategyAnalysisError.provider(message)
        }
        let content: String?
        if provider == .claude {
            content = try JSONDecoder().decode(AnthropicResponse.self, from: data).content
                .first(where: { $0.type == "text" })?.text
        } else {
            content = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
                .choices.first?.message.content
        }
        guard let content,
              let contentData = cleanedJSON(content).data(using: .utf8),
              let draft = try? JSONDecoder().decode(StrategyDraft.self, from: contentData),
              ["buy_and_hold", "monthly_dca", "moving_average", "breakout", "unsupported"].contains(draft.kind)
        else { throw StrategyAnalysisError.invalidResponse }
        return draft
    }

    private static func endpoint(for provider: AIProvider) -> URL? {
        switch provider {
        case .disabled: nil
        case .openAI: URL(string: "https://api.openai.com/v1/chat/completions")
        case .deepSeek: URL(string: "https://api.deepseek.com/chat/completions")
        case .claude: URL(string: "https://api.anthropic.com/v1/messages")
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        case .kimi: URL(string: "https://api.moonshot.cn/v1/chat/completions")
        }
    }

    private static func cleanedJSON(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```json") { result.removeFirst(7) }
        else if result.hasPrefix("```") { result.removeFirst(3) }
        if result.hasSuffix("```") { result.removeLast(3) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let systemPrompt = """
    You convert a user's natural-language trading idea into one supported, stock-independent backtest template. Return JSON only.

    Supported kinds:
    - buy_and_hold: buy at the first available close and sell at the final available close.
    - monthly_dca: split starting capital evenly across calendar months, buy on each month's first trading close, sell at the final close.
    - moving_average: requires explicit short_window and long_window positive integers, with short_window < long_window.
    - breakout: requires explicit entry_window and exit_window positive integers, with exit_window < entry_window.
    - unsupported: use when the idea cannot be represented by the four templates.

    Required JSON keys: kind, suggested_name, short_window, long_window, entry_window, exit_window, missing_fields, warnings.
    Use null for inapplicable or unspecified numeric fields. Never invent missing parameters. Put required missing parameters in missing_fields. Do not bind a stock, market, currency, capital, date range, fee, or slippage to the strategy; add a concise warning when the user includes them because those belong to the backtest configuration. Keep suggested_name short and use the user's language. Keep warnings and missing_fields concise and in the user's language.
    """
}
