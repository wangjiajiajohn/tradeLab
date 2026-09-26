# TradeLab V2

TradeLab V2 is a clean iOS implementation of an offline-first strategy backtesting product. The original TradeLab project is intentionally left untouched.

## Current vertical slice

- Four-step first-backtest flow: stock, strategy, settings, run
- Seven selectable offline stocks with no first-run network request
- Three reproducible strategies: buy-and-hold, 10/30 moving average, and 20-day breakout
- Commission and slippage-aware execution
- Price/signals, equity comparison, summary metrics, and trade history
- English, Simplified Chinese, and Traditional Chinese resources
- System appearance support and privacy manifest
- Unit tests plus a host-side engine smoke check

Release builds use deterministic synthetic series that are clearly disclosed in
the UI. A local Debug build can use development-only market data generated with
the scripts in `Tools/`; that data is ignored by Git and never copied by the
Release build.

## Generate and build

```sh
xcodegen generate
xcodebuild \
  -project TradeLabV2.xcodeproj \
  -scheme TradeLabV2 \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Open `TradeLabV2.xcodeproj` in Xcode to run on an iOS 17 or newer simulator/device. Xcode 27 supplies the newest system presentation automatically while the app retains an iOS 17 deployment target.

## Engine smoke check

```sh
xcrun swiftc -disable-sandbox \
  Sources/Domain/Models.swift \
  Sources/Domain/BacktestEngine.swift \
  Sources/Data/DemoMarketDataProvider.swift \
  Tools/EngineSmokeCheck.swift \
  -o /tmp/tradelab-v2-engine-check
/tmp/tradelab-v2-engine-check
```

## Next slices

1. Structured strategy creation and validation
2. CSV import with broker-format mapping and data-quality reporting
3. Saved backtests and side-by-side review
4. Optional user-configured market-data and AI providers
