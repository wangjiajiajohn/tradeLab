# Development market data

`fetch_longbridge_minutes.py` downloads regular-session, one-minute OHLCV bars
for the seven development symbols. The default range is the most recent year.

The generated files are written below `DevelopmentData/`, which is ignored by
Git and is not included in the Xcode resource build phase. They must never be
copied into a Release archive.

## Setup and authorization

```sh
brew install --cask longbridge/tap/longbridge-terminal
longbridge auth login
```

Then run:

```sh
python3 Tools/fetch_longbridge_minutes.py
```

The default universe is `AAPL.US`, `NVDA.US`, `TSLA.US`, `MU.US`, `SNDK.US`,
`700.HK`, and `9988.HK`.
