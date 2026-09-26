import Foundation

struct MarketDataLibrary: Sendable {
    let securities: [Security]
    let candlesBySecurityID: [String: [Candle]]

    func candles(for securityID: String) -> [Candle] {
        candlesBySecurityID[securityID] ?? []
    }
}

enum BuiltInMarketDataProvider {
    private struct BundlePayload: Decodable {
        let securities: [BundleSecurity]
    }

    private struct BundleSecurity: Decodable {
        let symbol: String
        let market: String
        let currency: String
        let candles: [BundleCandle]
    }

    private struct BundleCandle: Decodable {
        let date: String
        let open: Double
        let high: Double
        let low: Double
        let close: Double
        let volume: Double
    }

    private struct Descriptor {
        let id: String
        let symbol: String
        let nameKey: String
        let market: Market
        let currency: String
    }

    private static let descriptors = [
        Descriptor(id: "AAPL.US", symbol: "AAPL", nameKey: "security.aapl", market: .us, currency: "USD"),
        Descriptor(id: "NVDA.US", symbol: "NVDA", nameKey: "security.nvidia", market: .us, currency: "USD"),
        Descriptor(id: "TSLA.US", symbol: "TSLA", nameKey: "security.tesla", market: .us, currency: "USD"),
        Descriptor(id: "MU.US", symbol: "MU", nameKey: "security.micron", market: .us, currency: "USD"),
        Descriptor(id: "SNDK.US", symbol: "SNDK", nameKey: "security.sandisk", market: .us, currency: "USD"),
        Descriptor(id: "700.HK", symbol: "700", nameKey: "security.tencent", market: .hk, currency: "HKD"),
        Descriptor(id: "9988.HK", symbol: "9988", nameKey: "security.alibaba", market: .hk, currency: "HKD"),
    ]

    static func load(bundle: Bundle = .main) -> MarketDataLibrary {
        if let payload = loadDevelopmentPayload(bundle: bundle) {
            return makeLibrary(payload: payload)
        }
        return makeSyntheticLibrary()
    }

    private static func loadDevelopmentPayload(bundle: Bundle) -> BundlePayload? {
        #if DEBUG
        guard let url = bundle.url(forResource: "DevelopmentMarketData", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(BundlePayload.self, from: data)
        else { return nil }
        return payload
        #else
        return nil
        #endif
    }

    private static func makeLibrary(payload: BundlePayload) -> MarketDataLibrary {
        let dateFormatter = ISO8601DateFormatter()
        let payloadByID = Dictionary(uniqueKeysWithValues: payload.securities.map { ($0.symbol, $0) })
        var securities: [Security] = []
        var candlesByID: [String: [Candle]] = [:]

        for descriptor in descriptors {
            guard let item = payloadByID[descriptor.id] else { continue }
            let candles = item.candles.compactMap { value -> Candle? in
                guard let date = dateFormatter.date(from: value.date) else { return nil }
                return Candle(
                    date: date,
                    open: value.open,
                    high: value.high,
                    low: value.low,
                    close: value.close,
                    volume: value.volume
                )
            }
            guard !candles.isEmpty else { continue }
            let market: Market = item.market == "HK" ? .hk : .us
            let security = Security(
                id: descriptor.id,
                symbol: descriptor.symbol,
                name: String(localized: String.LocalizationValue(descriptor.nameKey)),
                market: market,
                currency: item.currency,
                isSyntheticDemo: false
            )
            securities.append(security)
            candlesByID[security.id] = candles
        }
        return MarketDataLibrary(securities: securities, candlesBySecurityID: candlesByID)
    }

    private static func makeSyntheticLibrary() -> MarketDataLibrary {
        var securities: [Security] = []
        var candlesByID: [String: [Candle]] = [:]
        for (index, descriptor) in descriptors.enumerated() {
            let security = Security(
                id: descriptor.id,
                symbol: descriptor.symbol,
                name: String(localized: String.LocalizationValue(descriptor.nameKey)),
                market: descriptor.market,
                currency: descriptor.currency,
                isSyntheticDemo: true
            )
            securities.append(security)
            candlesByID[security.id] = DemoMarketDataProvider.candles(seed: index + 1)
        }
        return MarketDataLibrary(securities: securities, candlesBySecurityID: candlesByID)
    }
}
