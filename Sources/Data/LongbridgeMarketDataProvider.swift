import CryptoKit
import Foundation
import Network
import OSLog
import zlib

struct LongbridgeCredentials: Sendable {
    let appKey: String
    let appSecret: String
    let accessToken: String

    static var saved: LongbridgeCredentials? {
        guard let appKey = CredentialStore.value(for: .longbridgeAppKey),
              let appSecret = CredentialStore.value(for: .longbridgeAppSecret),
              let accessToken = CredentialStore.value(for: .longbridgeAccessToken),
              !appKey.isEmpty, !appSecret.isEmpty, !accessToken.isEmpty
        else { return nil }
        return LongbridgeCredentials(appKey: appKey, appSecret: appSecret, accessToken: accessToken)
    }
}

enum OnlineMarketDataError: LocalizedError {
    case missingCredentials
    case network(String)
    case token
    case authentication
    case entitlement(Int)
    case history(Int)
    case malformed
    case noData
    case unsupportedMarket
    case validationTimeout

    var errorDescription: String? {
        localizedDescription(locale: .current)
    }

    func localizedDescription(locale: Locale) -> String {
        switch self {
        case .missingCredentials: AppLocalization.string("market_error.missing_credentials", locale: locale)
        case let .network(message): String(
            format: AppLocalization.string("market_error.network_format", locale: locale),
            message
        )
        case .token: AppLocalization.string("market_error.token", locale: locale)
        case .authentication: AppLocalization.string("market_error.authentication", locale: locale)
        case let .entitlement(status): String(
            format: AppLocalization.string("market_error.entitlement_format", locale: locale),
            status
        )
        case let .history(status): String(
            format: AppLocalization.string("market_error.history_format", locale: locale),
            status
        )
        case .malformed: AppLocalization.string("market_error.malformed", locale: locale)
        case .noData: AppLocalization.string("market_error.no_data", locale: locale)
        case .unsupportedMarket: AppLocalization.string("market_error.unsupported_market", locale: locale)
        case .validationTimeout: AppLocalization.string("market_error.validation_timeout", locale: locale)
        }
    }
}

func withMarketDataValidationTimeout<T: Sendable>(
    _ duration: Duration = .seconds(15),
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: duration)
            throw OnlineMarketDataError.validationTimeout
        }

        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw OnlineMarketDataError.validationTimeout
        }
        return result
    }
}

private enum LongbridgeEndpoint: Sendable {
    case mainland
    case international

    var http: URL {
        switch self {
        case .mainland: URL(string: "https://openapi.longbridge.cn")!
        case .international: URL(string: "https://openapi.longbridge.com")!
        }
    }

    var quote: URL {
        switch self {
        case .mainland: URL(string: "wss://openapi-quote.longbridge.cn/v2?version=1&codec=1&platform=9")!
        case .international: URL(string: "wss://openapi-quote.longbridge.com/v2?version=1&codec=1&platform=9")!
        }
    }
}

struct LongbridgeMarketDataProvider: Sendable {
    let credentials: LongbridgeCredentials

    private static let logger = Logger(subsystem: "com.tradelab.backtest.v2", category: "LongbridgeQuote")
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 75
        return URLSession(configuration: configuration)
    }()

    func validateCredentials() async throws {
        var lastError: Error?
        for endpoint in endpoints {
            do {
                _ = try await socketToken(endpoint: endpoint, requestTimeout: 10)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? OnlineMarketDataError.network("Unknown error")
    }

    func dailyCandles(for security: Security, from: Date, to: Date) async throws -> [Candle] {
        var lastError: Error?
        for attempt in 1...2 {
            for endpoint in endpoints {
                do {
                    return try await requestDailyCandles(for: security, from: from, to: to, endpoint: endpoint)
                } catch {
                    lastError = error
                    Self.logger.error("Longbridge daily request failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            guard attempt == 1, isTransportError(lastError) else { break }
            guard await waitForNetwork() else { break }
            try? await Task.sleep(for: .milliseconds(650))
        }
        throw lastError ?? OnlineMarketDataError.network("Unknown error")
    }

    func searchSecurities(matching query: String, locale: Locale) async throws -> [Security] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var lastError: Error?
        for endpoint in endpoints {
            do {
                let catalog = try await securityCatalog(endpoint: endpoint, locale: locale)
                let matches = Array(Self.filterCatalog(catalog, matching: trimmed, locale: locale).prefix(500))
                guard !matches.isEmpty else { return [] }

                // The security catalog does not expose a security type. Enrich the
                // matched rows with static information so HK warrants do not get
                // mixed in with ordinary shares. Search must still work if this
                // optional enrichment request is unavailable.
                let staticInfo = (try? await requestStaticInfo(
                    symbols: matches.map(\.security.id),
                    endpoint: endpoint
                )) ?? []
                let boardBySymbol = Dictionary(
                    staticInfo.map { ($0.symbol, $0.board) },
                    uniquingKeysWith: { first, _ in first }
                )

                return matches.sorted {
                    let lhsPriority = Self.searchSortPriority(
                        board: boardBySymbol[$0.security.id],
                        names: $0.names
                    )
                    let rhsPriority = Self.searchSortPriority(
                        board: boardBySymbol[$1.security.id],
                        names: $1.names
                    )
                    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                    if $0.score != $1.score { return $0.score < $1.score }
                    return $0.security.id < $1.security.id
                }
                .map(\.security)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? OnlineMarketDataError.network("Unknown error")
    }

    private func securityCatalog(
        endpoint: LongbridgeEndpoint,
        locale: Locale
    ) async throws -> [LongbridgeCatalogSecurity] {
        let language = Self.acceptLanguage(for: locale)
        let cacheKey = "\(dataCenter)|\(language)"
        if let cached = await Self.catalogCache.value(for: cacheKey) { return cached }

        let markets = ["US", "HK"]
        var catalog: [LongbridgeCatalogSecurity] = []
        var firstError: Error?
        await withTaskGroup(of: Result<[LongbridgeCatalogSecurity], Error>.self) { group in
            for market in markets {
                group.addTask {
                    do {
                        return .success(try await requestSecurityCatalog(
                            market: market,
                            endpoint: endpoint,
                            acceptLanguage: language
                        ))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case let .success(values): catalog.append(contentsOf: values)
                case let .failure(error): firstError = firstError ?? error
                }
            }
        }

        // A partial catalog is misleading for cross-listed companies. If either
        // market fails, retry through the next Longbridge access point instead
        // of silently presenting only the surviving market.
        if let firstError { throw firstError }

        let unique = catalog.reduce(into: [String: LongbridgeCatalogSecurity]()) { result, item in
            result[item.symbol] = item
        }.values.sorted { $0.symbol < $1.symbol }
        guard !unique.isEmpty else { throw firstError ?? OnlineMarketDataError.noData }
        await Self.catalogCache.store(unique, for: cacheKey)
        return unique
    }

    private func requestSecurityCatalog(
        market: String,
        endpoint: LongbridgeEndpoint,
        acceptLanguage: String
    ) async throws -> [LongbridgeCatalogSecurity] {
        let pageSize = 1_000
        var page = 1
        var values: [LongbridgeCatalogSecurity] = []

        while page <= 20 {
            let query = [
                URLQueryItem(name: "count", value: String(pageSize)),
                URLQueryItem(name: "market", value: market),
                URLQueryItem(name: "page", value: String(page))
            ]
            let request = try signedHTTPRequest(
                endpoint: endpoint,
                path: "/v1/quote/get_security_list",
                queryItems: query,
                acceptLanguage: acceptLanguage
            )
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await Self.session.data(for: request)
            } catch {
                throw OnlineMarketDataError.network(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else { throw OnlineMarketDataError.malformed }
            guard 200..<300 ~= http.statusCode else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw OnlineMarketDataError.authentication
                }
                throw OnlineMarketDataError.network("HTTP \(http.statusCode)")
            }
            let envelope = try JSONDecoder().decode(LongbridgeCatalogEnvelope.self, from: data)
            guard envelope.code == 0 else {
                throw OnlineMarketDataError.network(envelope.message ?? "Longbridge \(envelope.code)")
            }
            let batch = envelope.data?.list ?? []
            values.append(contentsOf: batch)
            guard batch.count == pageSize else { break }
            page += 1
        }
        return values
    }

    private func signedHTTPRequest(
        endpoint: LongbridgeEndpoint,
        path: String,
        queryItems: [URLQueryItem],
        acceptLanguage: String
    ) throws -> URLRequest {
        var components = URLComponents(url: endpoint.http.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.sorted { $0.name < $1.name }
        guard let url = components?.url else { throw OnlineMarketDataError.malformed }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signedHeaders = "authorization:\(credentials.accessToken)\nx-api-key:\(credentials.appKey)\nx-timestamp:\(timestamp)\n"
        let canonical = "GET|\(path)|\(components?.percentEncodedQuery ?? "")|\(signedHeaders)|authorization;x-api-key;x-timestamp|"
        let stringToSign = "HMAC-SHA256|\(sha1(Data(canonical.utf8)))"
        let key = SymmetricKey(data: Data(credentials.appSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()

        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue(credentials.appKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(credentials.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(dataCenter, forHTTPHeaderField: "X-Dc-Region")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "HMAC-SHA256 SignedHeaders=authorization;x-api-key;x-timestamp, Signature=\(signature)",
            forHTTPHeaderField: "X-Api-Signature"
        )
        return request
    }

    private func requestStaticInfo(
        symbols: [String],
        endpoint: LongbridgeEndpoint
    ) async throws -> [LongbridgeProto.StaticSecurityInfo] {
        let otp = try await socketToken(endpoint: endpoint)
        var request = URLRequest(url: endpoint.quote)
        request.setValue(dataCenter, forHTTPHeaderField: "X-Dc-Region")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        let socket = Self.session.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        try await socket.send(.data(LongbridgeWire.request(command: 2, id: 1, body: LongbridgeProto.auth(otp))))
        guard try await receive(socket, id: 1).status == 0 else { throw OnlineMarketDataError.authentication }

        try await socket.send(.data(LongbridgeWire.request(command: 4, id: 2, body: LongbridgeProto.profile())))
        let profile = try await receive(socket, id: 2)
        guard profile.status == 0 else { throw OnlineMarketDataError.entitlement(Int(profile.status)) }

        try await socket.send(.data(LongbridgeWire.request(
            command: 10,
            id: 3,
            body: LongbridgeProto.staticInfo(symbols: symbols)
        )))
        let response = try await receive(socket, id: 3)
        guard response.status == 0 else { throw OnlineMarketDataError.entitlement(Int(response.status)) }
        return try LongbridgeProto.decodeStaticInfo(response.body)
    }

    private func requestDailyCandles(
        for security: Security,
        from: Date,
        to: Date,
        endpoint: LongbridgeEndpoint
    ) async throws -> [Candle] {
        let otp = try await socketToken(endpoint: endpoint)
        var request = URLRequest(url: endpoint.quote)
        request.setValue(dataCenter, forHTTPHeaderField: "X-Dc-Region")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        let socket = Self.session.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        try await socket.send(.data(LongbridgeWire.request(command: 2, id: 1, body: LongbridgeProto.auth(otp))))
        guard try await receive(socket, id: 1).status == 0 else { throw OnlineMarketDataError.authentication }

        try await socket.send(.data(LongbridgeWire.request(command: 4, id: 2, body: LongbridgeProto.profile())))
        let profile = try await receive(socket, id: 2)
        guard profile.status == 0 else { throw OnlineMarketDataError.entitlement(Int(profile.status)) }

        let calendar = marketCalendar(for: security.market)
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"
        let body = LongbridgeProto.history(
            symbol: security.id,
            start: formatter.string(from: start),
            end: formatter.string(from: end)
        )
        try await socket.send(.data(LongbridgeWire.request(command: 27, id: 3, body: body)))
        let response = try await receive(socket, id: 3)
        guard response.status == 0 else { throw OnlineMarketDataError.history(Int(response.status)) }
        let candles = try LongbridgeProto.decodeCandles(response.body).sorted { $0.date < $1.date }
        guard !candles.isEmpty else { throw OnlineMarketDataError.noData }
        return candles
    }

    private func socketToken(
        endpoint: LongbridgeEndpoint,
        requestTimeout: TimeInterval? = nil
    ) async throws -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signedHeaders = "authorization:\(credentials.accessToken)\nx-api-key:\(credentials.appKey)\nx-timestamp:\(timestamp)\n"
        let canonical = "GET|/v1/socket/token||\(signedHeaders)|authorization;x-api-key;x-timestamp|"
        let stringToSign = "HMAC-SHA256|\(sha1(Data(canonical.utf8)))"
        let key = SymmetricKey(data: Data(credentials.appSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
        var request = URLRequest(url: endpoint.http.appending(path: "/v1/socket/token"))
        if let requestTimeout {
            request.timeoutInterval = requestTimeout
        }
        request.setValue(credentials.appKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(credentials.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(dataCenter, forHTTPHeaderField: "X-Dc-Region")
        request.setValue("HMAC-SHA256 SignedHeaders=authorization;x-api-key;x-timestamp, Signature=\(signature)", forHTTPHeaderField: "X-Api-Signature")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw OnlineMarketDataError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw OnlineMarketDataError.token
        }
        let envelope = try JSONDecoder().decode(SocketTokenEnvelope.self, from: data)
        guard envelope.code == 0, let otp = envelope.data?.otp, !otp.isEmpty else {
            throw OnlineMarketDataError.token
        }
        return otp
    }

    private func receive(_ socket: URLSessionWebSocketTask, id: UInt32) async throws -> LongbridgeWire.Response {
        while true {
            do {
                guard case let .data(data) = try await socket.receive() else { continue }
                if let response = try LongbridgeWire.response(data), response.id == id { return response }
            } catch let error as OnlineMarketDataError {
                throw error
            } catch {
                throw OnlineMarketDataError.network(error.localizedDescription)
            }
        }
    }

    private var dataCenter: String {
        [credentials.appKey, credentials.appSecret, credentials.accessToken].contains { $0.hasPrefix("us_") } ? "us" : "ap"
    }

    private var endpoints: [LongbridgeEndpoint] {
        dataCenter == "us" ? [.international] : [.mainland, .international]
    }

    private func marketCalendar(for market: Market) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: market == .hk ? "Asia/Hong_Kong" : "America/New_York") ?? .current
        return calendar
    }

    private func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func isTransportError(_ error: Error?) -> Bool {
        guard let error else { return false }
        if case .network = error as? OnlineMarketDataError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain || nsError.domain == NSPOSIXErrorDomain
    }

    private func waitForNetwork() async -> Bool {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.tradelab.v2.network-authorization")
        monitor.start(queue: queue)
        defer { monitor.cancel() }
        for _ in 0..<120 {
            if monitor.currentPath.status == .satisfied { return true }
            guard !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    static func normalizedSearchText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh-Hans")
        ).lowercased()
    }

    private static func filterCatalog(
        _ catalog: [LongbridgeCatalogSecurity],
        matching query: String,
        locale: Locale
    ) -> [(security: Security, score: Int, names: [String])] {
        let needle = normalizedSearchText(query)
        let directlyMatchedItems = catalog.filter { item in
            let symbol = item.symbol.split(separator: ".").first.map(String.init) ?? item.symbol
            return ([item.symbol, symbol, item.name, item.nameCN, item.nameHK, item.nameEN]
                .compactMap { $0 }
                .map(normalizedSearchText))
                .contains(where: { $0.contains(needle) })
        }
        let referencedUSSymbols = Set(directlyMatchedItems.compactMap { item -> String? in
            guard item.symbol.hasSuffix(".US") else { return nil }
            let symbol = item.symbol.split(separator: ".").first.map(String.init) ?? item.symbol
            guard (2...6).contains(symbol.count),
                  symbol.allSatisfy({ $0.isLetter || $0.isNumber })
            else { return nil }
            return symbol
        })

        return catalog.compactMap { item -> (Security, Int, [String])? in
            let symbol = item.symbol.split(separator: ".").first.map(String.init) ?? item.symbol
            let names = [item.name, item.nameCN, item.nameHK, item.nameEN].compactMap { $0 }
            let searchable = [item.symbol, symbol] + names
            let normalized = searchable
                .map(normalizedSearchText)
            let isDirectMatch = normalized.contains(where: { $0.contains(needle) })
            let isRelatedProduct = !isDirectMatch && referencedUSSymbols.contains { underlyingSymbol in
                names.contains { containsSecuritySymbolToken($0, symbol: underlyingSymbol) }
            }
            guard isDirectMatch || isRelatedProduct else { return nil }
            let score: Int
            if isRelatedProduct { score = 3 }
            else if normalized.contains(needle) { score = 0 }
            else if normalized.contains(where: { $0.hasPrefix(needle) }) { score = 1 }
            else { score = 2 }
            let market: Market = item.symbol.hasSuffix(".HK") ? .hk : .us
            return (
                Security(
                    id: item.symbol,
                    symbol: symbol,
                    name: item.localizedName(locale: locale),
                    market: market,
                    currency: market == .hk ? "HKD" : "USD",
                    isSyntheticDemo: false
                ),
                score,
                names
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.security.id < $1.security.id
        }
    }

    /// Matches a ticker as a complete name token so `NIO` finds products whose
    /// name references NIO, without treating symbols such as `NIOG` as an
    /// implicit relationship on their own.
    static func containsSecuritySymbolToken(_ text: String, symbol: String) -> Bool {
        let expected = symbol.uppercased()
        return text.uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { String($0) == expected }
    }

    /// Search display order: ordinary shares, ETFs/ETNs, then warrants and
    /// other derivatives. Longbridge identifies HK warrants through `board`,
    /// while its static-info response does not provide a dedicated ETF type.
    /// ETF detection therefore uses all localized catalog names.
    static func searchSortPriority(board: String?, names: [String]) -> Int {
        let normalizedBoard = board?.uppercased() ?? ""
        if normalizedBoard.contains("WARRANT") || normalizedBoard.contains("OPTION") {
            return 2
        }

        let normalizedNames = names.map { $0.uppercased() }
        let isETF = normalizedNames.contains { name in
            name.contains("ETF") ||
                name.contains("ETN") ||
                name.contains("ETP") ||
                name.contains("EXCHANGE TRADED") ||
                name.contains("2X LONG") ||
                name.contains("3X LONG") ||
                name.contains("2X SHORT") ||
                name.contains("3X SHORT") ||
                name.contains("交易所买卖基金") ||
                name.contains("交易所買賣基金")
        }
        return isETF ? 1 : 0
    }

    private static func acceptLanguage(for locale: Locale) -> String {
        if locale.identifier.lowercased().contains("hant") || locale.identifier.lowercased().contains("hk") {
            return "zh-HK"
        }
        if locale.language.languageCode?.identifier == "zh" { return "zh-CN" }
        return "en-US"
    }

    private static let catalogCache = LongbridgeCatalogCache()
}

private struct LongbridgeCatalogEnvelope: Decodable {
    let code: Int
    let message: String?
    let data: Payload?

    struct Payload: Decodable {
        let list: [LongbridgeCatalogSecurity]?
    }
}

private struct LongbridgeCatalogSecurity: Decodable, Sendable {
    let symbol: String
    let name: String?
    let nameCN: String?
    let nameHK: String?
    let nameEN: String?

    enum CodingKeys: String, CodingKey {
        case symbol, name
        case nameCN = "name_cn"
        case nameHK = "name_hk"
        case nameEN = "name_en"
    }

    func localizedName(locale: Locale) -> String {
        let identifier = locale.identifier.lowercased()
        if identifier.contains("hant") || identifier.contains("hk") {
            return nameHK ?? name ?? nameCN ?? nameEN ?? symbol
        }
        if locale.language.languageCode?.identifier == "zh" {
            return nameCN ?? name ?? nameHK ?? nameEN ?? symbol
        }
        return nameEN ?? name ?? nameCN ?? nameHK ?? symbol
    }
}

private actor LongbridgeCatalogCache {
    private var storage: [String: [LongbridgeCatalogSecurity]] = [:]

    func value(for key: String) -> [LongbridgeCatalogSecurity]? { storage[key] }
    func store(_ value: [LongbridgeCatalogSecurity], for key: String) { storage[key] = value }
}

private struct SocketTokenEnvelope: Decodable {
    let code: Int
    let data: Payload?
    struct Payload: Decodable { let otp: String }
}

private enum LongbridgeWire {
    struct Response { let id: UInt32; let status: UInt8; let body: Data }

    static func request(command: UInt8, id: UInt32, body: Data) -> Data {
        var data = Data([0x01, command])
        data.appendUInt32BE(id)
        data.appendUInt16BE(30_000)
        data.appendUInt24BE(UInt32(body.count))
        data.append(body)
        return data
    }

    static func response(_ data: Data) throws -> Response? {
        guard data.count >= 10 else { throw OnlineMarketDataError.malformed }
        guard data[0] & 0x0F == 2 else { return nil }
        let compressed = data[0] & 0x20 != 0
        let length = Int(data.uint24BE(at: 7))
        guard data.count >= 10 + length else { throw OnlineMarketDataError.malformed }
        let body = data.subdata(in: 10..<(10 + length))
        return Response(
            id: data.uint32BE(at: 2),
            status: data[6],
            body: compressed ? try decompress(body) : body
        )
    }

    private static func decompress(_ input: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw OnlineMarketDataError.malformed
        }
        defer { inflateEnd(&stream) }
        return try input.withUnsafeBytes { inputBuffer in
            guard let source = inputBuffer.bindMemory(to: Bytef.self).baseAddress else { return Data() }
            stream.next_in = UnsafeMutablePointer(mutating: source)
            stream.avail_in = uInt(input.count)
            var output = Data()
            var result = Z_OK
            repeat {
                var buffer = [UInt8](repeating: 0, count: 32_768)
                let capacity = buffer.count
                result = buffer.withUnsafeMutableBytes { bytes in
                    stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(bytes.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                guard result == Z_OK || result == Z_STREAM_END else { throw OnlineMarketDataError.malformed }
                output.append(buffer, count: capacity - Int(stream.avail_out))
            } while result != Z_STREAM_END
            return output
        }
    }
}

private enum LongbridgeProto {
    struct StaticSecurityInfo {
        let symbol: String
        let nameCN: String
        let nameEN: String
        let nameHK: String
        let currency: String
        let board: String

        func localizedName(locale: Locale) -> String {
            let identifier = locale.identifier.lowercased()
            if identifier.contains("hant"), !nameHK.isEmpty { return nameHK }
            if identifier.hasPrefix("zh"), !nameCN.isEmpty { return nameCN }
            if !nameEN.isEmpty { return nameEN }
            if !nameCN.isEmpty { return nameCN }
            return symbol
        }
    }

    static func auth(_ token: String) -> Data { fieldString(1, token) }
    static func profile() -> Data { fieldString(1, "en-US") }

    static func staticInfo(symbols: [String]) -> Data {
        symbols.reduce(into: Data()) { data, symbol in
            data += fieldString(1, symbol)
        }
    }

    static func history(symbol: String, start: String, end: String) -> Data {
        var data = fieldString(1, symbol)
        data += fieldVarint(2, 1_000)
        data += fieldVarint(3, 0)
        data += fieldVarint(4, 2)
        var dates = fieldString(1, start)
        dates += fieldString(2, end)
        data += fieldMessage(6, dates)
        data += fieldVarint(7, 0)
        return data
    }

    static func decodeCandles(_ data: Data) throws -> [Candle] {
        try fields(data).compactMap { field in
            guard field.number == 2, case let .bytes(bytes) = field.value else { return nil }
            let parts = try fields(bytes)
            func text(_ number: Int) -> String? {
                parts.first { $0.number == number }.flatMap {
                    if case let .bytes(value) = $0.value { String(data: value, encoding: .utf8) } else { nil }
                }
            }
            func integer(_ number: Int) -> UInt64? {
                parts.first { $0.number == number }.flatMap {
                    if case let .varint(value) = $0.value { value } else { nil }
                }
            }
            guard let close = text(1).flatMap(Double.init),
                  let open = text(2).flatMap(Double.init),
                  let low = text(3).flatMap(Double.init),
                  let high = text(4).flatMap(Double.init),
                  let timestamp = integer(7)
            else { return nil }
            return Candle(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: Double(integer(5) ?? 0)
            )
        }
    }

    static func decodeStaticInfo(_ data: Data) throws -> [StaticSecurityInfo] {
        try fields(data).compactMap { field in
            guard field.number == 1, case let .bytes(bytes) = field.value else { return nil }
            let parts = try fields(bytes)
            func text(_ number: Int) -> String {
                parts.first { $0.number == number }.flatMap {
                    if case let .bytes(value) = $0.value { String(data: value, encoding: .utf8) } else { nil }
                } ?? ""
            }
            let symbol = text(1)
            guard !symbol.isEmpty else { return nil }
            return StaticSecurityInfo(
                symbol: symbol,
                nameCN: text(2),
                nameEN: text(3),
                nameHK: text(4),
                currency: text(7),
                board: text(17)
            )
        }
    }

    private enum Value { case varint(UInt64), bytes(Data) }
    private struct Field { let number: Int; let value: Value }

    private static func fields(_ data: Data) throws -> [Field] {
        var index = 0
        var result: [Field] = []
        while index < data.count {
            let key = try readVarint(data, &index)
            let number = Int(key >> 3)
            switch key & 7 {
            case 0: result.append(Field(number: number, value: .varint(try readVarint(data, &index))))
            case 2:
                let length = Int(try readVarint(data, &index))
                guard index + length <= data.count else { throw OnlineMarketDataError.malformed }
                result.append(Field(number: number, value: .bytes(data.subdata(in: index..<(index + length)))))
                index += length
            default: throw OnlineMarketDataError.malformed
            }
        }
        return result
    }

    private static func fieldString(_ tag: Int, _ value: String) -> Data { fieldMessage(tag, Data(value.utf8)) }
    private static func fieldMessage(_ tag: Int, _ value: Data) -> Data {
        var data = varint(UInt64(tag << 3 | 2)); data += varint(UInt64(value.count)); data += value; return data
    }
    private static func fieldVarint(_ tag: Int, _ value: UInt64) -> Data {
        var data = varint(UInt64(tag << 3)); data += varint(value); return data
    }
    private static func varint(_ value: UInt64) -> Data {
        var number = value
        var data = Data()
        repeat {
            var byte = UInt8(number & 0x7F); number >>= 7
            if number != 0 { byte |= 0x80 }
            data.append(byte)
        } while number != 0
        return data
    }
    private static func readVarint(_ data: Data, _ index: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.count, shift < 64 {
            let byte = data[index]; index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        throw OnlineMarketDataError.malformed
    }
}

private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func appendUInt24BE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }
    func uint24BE(at index: Int) -> UInt32 { UInt32(self[index]) << 16 | UInt32(self[index + 1]) << 8 | UInt32(self[index + 2]) }
    func uint32BE(at index: Int) -> UInt32 { UInt32(self[index]) << 24 | UInt32(self[index + 1]) << 16 | UInt32(self[index + 2]) << 8 | UInt32(self[index + 3]) }
}
