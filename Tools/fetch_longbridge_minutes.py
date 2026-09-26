#!/usr/bin/env python3
"""Download development-only Longbridge one-minute candles via the official CLI."""

from __future__ import annotations

import argparse
import gzip
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable
from zoneinfo import ZoneInfo


DEFAULT_SYMBOLS = (
    "AAPL.US",
    "NVDA.US",
    "TSLA.US",
    "MU.US",
    "SNDK.US",
    "700.HK",
    "9988.HK",
)
SCHEMA_VERSION = 1


@dataclass(frozen=True)
class SymbolSpec:
    symbol: str
    timezone_name: str

    @property
    def timezone(self) -> ZoneInfo:
        return ZoneInfo(self.timezone_name)


def symbol_spec(symbol: str) -> SymbolSpec:
    if symbol.endswith(".US"):
        return SymbolSpec(symbol, "America/New_York")
    if symbol.endswith(".HK"):
        return SymbolSpec(symbol, "Asia/Hong_Kong")
    raise ValueError(f"Unsupported market for {symbol}")


def default_cli_path() -> str:
    installed = shutil.which("longbridge")
    if installed:
        return installed
    temporary = Path("/private/tmp/tradelab-longbridge-cli/longbridge")
    return str(temporary) if temporary.exists() else "longbridge"


def parse_args() -> argparse.Namespace:
    today = date.today()
    parser = argparse.ArgumentParser(
        description="Fetch one year of regular-session 1-minute candles from Longbridge."
    )
    parser.add_argument("--symbols", nargs="+", default=list(DEFAULT_SYMBOLS))
    parser.add_argument("--start", type=date.fromisoformat, default=today - timedelta(days=365))
    parser.add_argument("--end", type=date.fromisoformat, default=today)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("DevelopmentData/Longbridge/one-year-1m"),
    )
    parser.add_argument("--cli", default=os.environ.get("LONGBRIDGE_CLI", default_cli_path()))
    parser.add_argument(
        "--chunk-days",
        type=int,
        default=2,
        help="Calendar days per request; two days stays below the 1,000-bar cap.",
    )
    parser.add_argument("--request-delay", type=float, default=0.15)
    return parser.parse_args()


def ensure_cli(cli: str) -> None:
    try:
        result = subprocess.run(
            [cli, "auth", "status", "--format", "json"],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as error:
        raise SystemExit(
            "Longbridge CLI is not installed. See https://open.longbridge.com/docs/cli/install"
        ) from error
    try:
        payload = json.loads(result.stdout)
        status = payload["token"]["status"]
    except (json.JSONDecodeError, KeyError, TypeError) as error:
        raise SystemExit(f"Unable to read Longbridge authorization status: {result.stderr}") from error
    if status not in {"valid", "authenticated"}:
        raise SystemExit("Longbridge is not authorized. Run: longbridge auth login")


def date_chunks(start: date, end: date, chunk_days: int) -> Iterable[tuple[date, date]]:
    if chunk_days < 1:
        raise ValueError("--chunk-days must be at least 1")
    cursor = start
    while cursor <= end:
        chunk_end = min(end, cursor + timedelta(days=chunk_days - 1))
        yield cursor, chunk_end
        cursor = chunk_end + timedelta(days=1)


def normalize_time(value: str) -> str:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def serialize_cli_candle(candle: dict[str, Any]) -> dict[str, Any]:
    candle_time = candle.get("time") or candle.get("timestamp")
    if not isinstance(candle_time, str):
        raise ValueError(f"Candle has no timestamp: {candle}")
    return {
        "ts": normalize_time(candle_time),
        "o": str(candle["open"]),
        "h": str(candle["high"]),
        "l": str(candle["low"]),
        "c": str(candle["close"]),
        "v": int(candle["volume"]),
        "turnover": str(candle.get("turnover", "0")),
        "session": "intraday",
    }


def fetch_chunk(cli: str, symbol: str, start: date, end: date) -> list[dict[str, Any]]:
    result = subprocess.run(
        [
            cli,
            "kline",
            "history",
            symbol,
            "--period",
            "1m",
            "--session",
            "intraday",
            "--start",
            start.isoformat(),
            "--end",
            end.isoformat(),
            "--format",
            "json",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Longbridge request failed for {symbol} {start}...{end}: {result.stderr.strip()}"
        )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"Longbridge returned invalid JSON for {symbol} {start}...{end}"
        ) from error
    if not isinstance(payload, list):
        raise RuntimeError(f"Unexpected Longbridge response for {symbol}: {payload}")
    if len(payload) >= 1_000:
        raise RuntimeError(
            f"Chunk {start}...{end} reached the 1,000-bar cap; rerun with --chunk-days 1"
        )
    return [serialize_cli_candle(item) for item in payload]


def download_symbol(
    cli: str,
    spec: SymbolSpec,
    start: date,
    end: date,
    chunk_days: int,
    request_delay: float,
) -> list[dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    chunks = list(date_chunks(start, end, chunk_days))
    for index, (chunk_start, chunk_end) in enumerate(chunks, start=1):
        rows = fetch_chunk(cli, spec.symbol, chunk_start, chunk_end)
        for row in rows:
            records[row["ts"]] = row
        print(
            f"{spec.symbol}: {index}/{len(chunks)} {chunk_start}...{chunk_end}, "
            f"received {len(rows)}, total {len(records)}",
            flush=True,
        )
        time.sleep(max(0, request_delay))
    return [records[key] for key in sorted(records)]


def write_dataset(path: Path, metadata: dict[str, Any], rows: Iterable[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_suffix(path.suffix + ".partial")
    with gzip.open(partial, "wt", encoding="utf-8", newline="\n") as output:
        output.write(json.dumps({"meta": metadata}, ensure_ascii=False, separators=(",", ":")))
        output.write("\n")
        for row in rows:
            output.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
            output.write("\n")
    partial.replace(path)


def main() -> int:
    args = parse_args()
    if args.start > args.end:
        raise SystemExit("--start must not be later than --end")
    ensure_cli(args.cli)

    output_root = args.output.resolve()
    manifest: dict[str, Any] = {
        "schema": "tradelab-minute-bars",
        "version": SCHEMA_VERSION,
        "source": "longbridge-development-only",
        "period": "1m",
        "tradeSessions": "intraday",
        "start": args.start.isoformat(),
        "end": args.end.isoformat(),
        "generatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "symbols": [],
    }

    for symbol in args.symbols:
        spec = symbol_spec(symbol)
        rows = download_symbol(
            args.cli,
            spec,
            args.start,
            args.end,
            args.chunk_days,
            args.request_delay,
        )
        output_file = output_root / f"{symbol}.jsonl.gz"
        metadata = {
            "schema": "tradelab-minute-bars",
            "version": SCHEMA_VERSION,
            "source": "longbridge-development-only",
            "symbol": symbol,
            "timezone": spec.timezone_name,
            "period": "1m",
            "tradeSessions": "intraday",
            "start": args.start.isoformat(),
            "end": args.end.isoformat(),
            "count": len(rows),
        }
        write_dataset(output_file, metadata, rows)
        manifest["symbols"].append(
            {"symbol": symbol, "file": output_file.name, "count": len(rows)}
        )
        print(f"{symbol}: wrote {len(rows)} rows to {output_file}", flush=True)

    output_root.mkdir(parents=True, exist_ok=True)
    manifest_path = output_root / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
