# TradeLab V2

TradeLab V2 is a clean iOS implementation of an offline-first strategy backtesting product. The original TradeLab project is intentionally left untouched.

## Current vertical slice

- Four-step first-backtest flow: stock, strategy, settings, run
- Seven selectable offline stocks with no first-run network request
- Four reproducible strategies: monthly DCA, buy-and-hold, 10/30 moving average, and 20-day breakout
- Commission and slippage-aware execution
- Price/signals, equity comparison, risk-adjusted metrics, saved results, and side-by-side comparison
- Manual real-trade journaling, flexible CSV import, FIFO realized profit, fees, positions, and data-quality warnings
- Optional OpenAI or DeepSeek strategy drafting with credentials stored in the system Keychain
- Optional user-configured market-data credentials; first-run remains fully offline
- English, Simplified Chinese, and Traditional Chinese resources
- System appearance support and privacy manifest
- Unit tests plus a host-side engine smoke check

Debug and Release builds use the same versioned dataset in
`Resources/OfflineMarketData`. It contains one year of daily and one-minute data
for the seven built-in securities. Backtests currently read `MarketData.json`;
the compressed minute files are bundled for chart integration.

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

## Data boundaries

Backtests are deterministic and run on device. AI is used only to turn a natural-language idea into a constrained local strategy draft. Imported trades and provider credentials remain on device; secrets are stored in the system Keychain.
