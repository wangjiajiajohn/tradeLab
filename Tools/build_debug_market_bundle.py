#!/usr/bin/env python3
"""Aggregate development-only minute bars into a compact Debug app resource."""

from __future__ import annotations

import argparse
import gzip
import json
from collections import OrderedDict
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


SYMBOLS = {
    "AAPL.US": ("US", "USD", "America/New_York"),
    "NVDA.US": ("US", "USD", "America/New_York"),
    "TSLA.US": ("US", "USD", "America/New_York"),
    "MU.US": ("US", "USD", "America/New_York"),
    "SNDK.US": ("US", "USD", "America/New_York"),
    "700.HK": ("HK", "HKD", "Asia/Hong_Kong"),
    "9988.HK": ("HK", "HKD", "Asia/Hong_Kong"),
}


def aggregate(path: Path, timezone_name: str) -> list[dict[str, object]]:
    timezone = ZoneInfo(timezone_name)
    days: OrderedDict[str, dict[str, object]] = OrderedDict()

    with gzip.open(path, "rt", encoding="utf-8") as source:
        next(source)  # metadata line
        for line in source:
            minute = json.loads(line)
            timestamp = datetime.fromisoformat(minute["ts"].replace("Z", "+00:00"))
            day = timestamp.astimezone(timezone).date().isoformat()
            open_price = float(minute["o"])
            high = float(minute["h"])
            low = float(minute["l"])
            close = float(minute["c"])
            volume = float(minute["v"])

            if day not in days:
                days[day] = {
                    "date": f"{day}T00:00:00Z",
                    "open": open_price,
                    "high": max(open_price, high, low, close),
                    "low": min(open_price, high, low, close),
                    "close": close,
                    "volume": volume,
                }
            else:
                candle = days[day]
                candle["high"] = max(float(candle["high"]), open_price, high, low, close)
                candle["low"] = min(float(candle["low"]), open_price, high, low, close)
                candle["close"] = close
                candle["volume"] = float(candle["volume"]) + volume

    return list(days.values())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input",
        type=Path,
        default=Path("DevelopmentData/Longbridge/one-year-1m"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("DevelopmentData/DebugBundle/DevelopmentMarketData.json"),
    )
    args = parser.parse_args()

    securities = []
    for symbol, (market, currency, timezone_name) in SYMBOLS.items():
        source = args.input / f"{symbol}.jsonl.gz"
        if not source.exists():
            raise SystemExit(f"Missing source data: {source}")
        candles = aggregate(source, timezone_name)
        securities.append(
            {
                "symbol": symbol,
                "market": market,
                "currency": currency,
                "timezone": timezone_name,
                "candles": candles,
            }
        )
        print(f"{symbol}: {len(candles)} daily candles")

    payload = {
        "schema": "tradelab-development-market-data",
        "version": 1,
        "source": "longbridge-development-only",
        "securities": securities,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    print(f"Wrote {args.output} ({args.output.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
