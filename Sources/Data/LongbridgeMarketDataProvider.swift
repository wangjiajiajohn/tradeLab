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
        }
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

    private func socketToken(endpoint: LongbridgeEndpoint) async throws -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signedHeaders = "authorization:\(credentials.accessToken)\nx-api-key:\(credentials.appKey)\nx-timestamp:\(timestamp)\n"
        let canonical = "GET|/v1/socket/token||\(signedHeaders)|authorization;x-api-key;x-timestamp|"
        let stringToSign = "HMAC-SHA256|\(sha1(Data(canonical.utf8)))"
        let key = SymmetricKey(data: Data(credentials.appSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
        var request = URLRequest(url: endpoint.http.appending(path: "/v1/socket/token"))
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
    static func auth(_ token: String) -> Data { fieldString(1, token) }
    static func profile() -> Data { fieldString(1, "en-US") }

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
    mutating func appendUInt16BE(_ value: UInt16) { append(UInt8(value >> 8)); append(UInt8(value & 0xFF)) }
    mutating func appendUInt24BE(_ value: UInt32) { append(UInt8(value >> 16)); append(UInt8(value >> 8)); append(UInt8(value)) }
    mutating func appendUInt32BE(_ value: UInt32) { append(UInt8(value >> 24)); append(UInt8(value >> 16)); append(UInt8(value >> 8)); append(UInt8(value)) }
    func uint24BE(at index: Int) -> UInt32 { UInt32(self[index]) << 16 | UInt32(self[index + 1]) << 8 | UInt32(self[index + 2]) }
    func uint32BE(at index: Int) -> UInt32 { UInt32(self[index]) << 24 | UInt32(self[index + 1]) << 16 | UInt32(self[index + 2]) << 8 | UInt32(self[index + 3]) }
}
