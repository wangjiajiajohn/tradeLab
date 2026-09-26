import Foundation

struct AlpacaCredentials: Sendable {
    let apiKey: String
    let apiSecret: String

    static var saved: AlpacaCredentials? {
        guard let apiKey = CredentialStore.value(for: .alpacaAPIKey),
              let apiSecret = CredentialStore.value(for: .alpacaAPISecret),
              !apiKey.isEmpty, !apiSecret.isEmpty
        else { return nil }
        return AlpacaCredentials(apiKey: apiKey, apiSecret: apiSecret)
    }
}

struct AlpacaMarketDataProvider: Sendable {
    let credentials: AlpacaCredentials

    private struct Response: Decodable {
        struct Bar: Decodable {
            let t: String
            let o: Double
            let h: Double
            let l: Double
            let c: Double
            let v: Double
        }
        let bars: [Bar]
    }

    private struct ErrorResponse: Decodable {
        let message: String?
    }

    func validateCredentials() async throws {
        let end = Date()
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -30, to: end)
            ?? end.addingTimeInterval(-30 * 86_400)
        let security = Security(
            id: "AAPL.US",
            symbol: "AAPL",
            name: "Apple",
            market: .us,
            currency: "USD",
            isSyntheticDemo: false
        )
        _ = try await dailyCandles(for: security, from: start, to: end)
    }

    func dailyCandles(for security: Security, from: Date, to: Date) async throws -> [Candle] {
        guard security.market == .us else { throw OnlineMarketDataError.unsupportedMarket }
        var components = URLComponents(
            url: URL(string: "https://data.alpaca.markets/v2/stocks/\(security.symbol)/bars")!,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "timeframe", value: "1Day"),
            URLQueryItem(name: "start", value: iso8601Formatter().string(from: from)),
            URLQueryItem(name: "end", value: iso8601Formatter().string(from: to)),
            URLQueryItem(name: "adjustment", value: "all"),
            URLQueryItem(name: "feed", value: "iex"),
            URLQueryItem(name: "limit", value: "10000")
        ]
        guard let url = components.url else { throw OnlineMarketDataError.malformed }
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue(credentials.apiKey, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(credentials.apiSecret, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OnlineMarketDataError.malformed }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw OnlineMarketDataError.authentication
            }
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).message)
                ?? "HTTP \(http.statusCode)"
            throw OnlineMarketDataError.network(message)
        }
        let values = try JSONDecoder().decode(Response.self, from: data).bars.compactMap { bar -> Candle? in
            guard let date = iso8601Formatter().date(from: bar.t) else { return nil }
            return Candle(date: date, open: bar.o, high: bar.h, low: bar.l, close: bar.c, volume: bar.v)
        }
        guard !values.isEmpty else { throw OnlineMarketDataError.noData }
        return values.sorted { $0.date < $1.date }
    }

    private func iso8601Formatter() -> ISO8601DateFormatter {
        ISO8601DateFormatter()
    }
}

struct TwelveDataMarketDataProvider: Sendable {
    let apiKey: String

    private struct Response: Decodable {
        struct Value: Decodable {
            let datetime: String
            let open: String
            let high: String
            let low: String
            let close: String
            let volume: String?
        }
        let status: String?
        let message: String?
        let values: [Value]?
    }

    static var savedAPIKey: String? {
        guard let value = CredentialStore.value(for: .twelveDataAPIKey), !value.isEmpty else { return nil }
        return value
    }

    func validateCredentials() async throws {
        let end = Date()
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -30, to: end)
            ?? end.addingTimeInterval(-30 * 86_400)
        let security = Security(
            id: "AAPL.US",
            symbol: "AAPL",
            name: "Apple",
            market: .us,
            currency: "USD",
            isSyntheticDemo: false
        )
        _ = try await dailyCandles(for: security, from: start, to: end)
    }

    func dailyCandles(for security: Security, from: Date, to: Date) async throws -> [Candle] {
        guard security.market == .us || security.market == .hk else {
            throw OnlineMarketDataError.unsupportedMarket
        }
        var components = URLComponents(string: "https://api.twelvedata.com/time_series")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol(for: security)),
            URLQueryItem(name: "interval", value: "1day"),
            URLQueryItem(name: "start_date", value: queryDateFormatter().string(from: from)),
            URLQueryItem(name: "end_date", value: queryDateFormatter().string(from: to)),
            URLQueryItem(name: "adjust", value: "all"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components.url else { throw OnlineMarketDataError.malformed }
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OnlineMarketDataError.malformed }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        guard 200..<300 ~= http.statusCode, payload.status != "error" else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw OnlineMarketDataError.authentication
            }
            throw OnlineMarketDataError.network(payload.message ?? "HTTP \(http.statusCode)")
        }
        let formatter = dayFormatter(for: security.market)
        let candles = (payload.values ?? []).compactMap { value -> Candle? in
            guard let date = formatter.date(from: value.datetime),
                  let open = Double(value.open), let high = Double(value.high),
                  let low = Double(value.low), let close = Double(value.close)
            else { return nil }
            return Candle(
                date: date,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: Double(value.volume ?? "") ?? 0
            )
        }
        guard !candles.isEmpty else { throw OnlineMarketDataError.noData }
        return candles.sorted { $0.date < $1.date }
    }

    private func symbol(for security: Security) -> String {
        security.market == .hk ? "\(security.symbol):HKEX" : security.symbol
    }

    private func dayFormatter(for market: Market) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: market == .hk ? "Asia/Hong_Kong" : "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func queryDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
