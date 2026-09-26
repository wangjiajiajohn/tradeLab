# Offline market data

The versioned runtime dataset lives in `Resources/OfflineMarketData` and is
included unchanged in both Debug and Release builds. `MarketData.json` supplies
daily candles to the current backtest engine. The `daily` and `minute`
directories retain the exported CSV datasets for chart integration.

`manifest.json` records row counts, date ranges, time zones, and SHA-256 hashes.
`validation.json` records ordering, uniqueness, and trading-session checks.

`MarketDataSmokeCheck.swift` exercises every built-in stock/strategy
combination. `EngineSmokeCheck.swift` checks the backtest engine independently.
