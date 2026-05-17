"""
Tải N nến M1 của XAUUSDm (hoặc symbol khác) từ MT5 cục bộ đang chạy, lưu CSV.

Chạy (từ thư mục python):
  uv sync && uv run python download_xauusd_m1_mt5.py

Hoặc không cần sync trước:
  uv run --directory . python download_xauusd_m1_mt5.py
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import MetaTrader5 as mt5
import numpy as np


def _init_mt5(terminal_path: str | None) -> bool:
    if terminal_path:
        ok = mt5.initialize(terminal_path)
    else:
        ok = mt5.initialize()
    if ok:
        return True
    username = os.getenv("USERNAME", "")
    candidates = [
        r"C:\Program Files\MetaTrader 5\terminal64.exe",
        r"C:\Program Files (x86)\MetaTrader 5\terminal64.exe",
    ]
    for p in candidates:
        if os.path.isfile(p) and mt5.initialize(p):
            print(f"MT5: đã kết nối qua {p}")
            return True
    roaming = Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal"
    if roaming.is_dir():
        for sub in sorted(roaming.iterdir()):
            exe = sub / "terminal64.exe"
            if exe.is_file() and mt5.initialize(str(exe)):
                print(f"MT5: đã kết nối qua {exe}")
                return True
    print("MT5 initialize thất bại:", mt5.last_error())
    return False


def _copy_rates_chunked(symbol: str, timeframe: int, total: int, chunk: int) -> np.ndarray | None:
    """Lấy total nến từ hiện tại về quá khứ (pos 0 = nến mới nhất)."""
    parts: list[np.ndarray] = []
    pos = 0
    while pos < total:
        n = min(chunk, total - pos)
        batch = mt5.copy_rates_from_pos(symbol, timeframe, pos, n)
        if batch is None or len(batch) == 0:
            break
        parts.append(batch)
        pos += len(batch)
        if len(batch) < n:
            break
    if not parts:
        return None
    return np.concatenate(parts)


def main() -> int:
    # Windows console thường là cp1252; tránh UnicodeEncodeError khi in tiếng Việt
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    parser = argparse.ArgumentParser(description="Tải nến M1 từ MT5 local, lưu CSV.")
    parser.add_argument("--symbol", default="XAUUSDm", help="Tên symbol trên MT5 (mặc định: XAUUSDm)")
    parser.add_argument("--count", type=int, default=100_000, help="Số nến (mặc định: 100000)")
    parser.add_argument(
        "-o",
        "--output",
        default="",
        help="Đường dẫn file CSV (mặc định: data/xauusd_m1_<symbol>_<count>_<timestamp>.csv trong repo)",
    )
    parser.add_argument("--terminal", default="", help="Đường dẫn terminal64.exe nếu cần chỉ định")
    parser.add_argument("--chunk", type=int, default=20_000, help="Số nến mỗi lần gọi API (tránh giới hạn từng request)")
    args = parser.parse_args()

    term = args.terminal.strip() or None
    if not _init_mt5(term):
        return 1

    if not mt5.symbol_select(args.symbol, True):
        print(f"Không chọn được symbol {args.symbol}. Kiểm tra tên trên Market Watch.")
        mt5.shutdown()
        return 1

    rates = _copy_rates_chunked(args.symbol, mt5.TIMEFRAME_M1, args.count, max(500, args.chunk))
    if rates is None or len(rates) == 0:
        print("Không lấy được dữ liệu (copy_rates_from_pos trả về rỗng). Kiểm tra lịch sử M1 trên server.")
        mt5.shutdown()
        return 1

    out = args.output.strip()
    if not out:
        repo_root = Path(__file__).resolve().parents[1]
        data_dir = repo_root / "data"
        data_dir.mkdir(parents=True, exist_ok=True)
        ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        safe_sym = "".join(c if c.isalnum() else "_" for c in args.symbol)
        out = str(data_dir / f"xauusd_m1_{safe_sym}_{len(rates)}_{ts}.csv")

    # time trong MT5: giây UTC từ 1970
    fieldnames = ["time_utc", "open", "high", "low", "close", "tick_volume", "spread", "real_volume"]
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for row in rates:
            tsec = int(row["time"])
            w.writerow(
                {
                    "time_utc": datetime.fromtimestamp(tsec, tz=timezone.utc).isoformat(),
                    "open": row["open"],
                    "high": row["high"],
                    "low": row["low"],
                    "close": row["close"],
                    "tick_volume": row["tick_volume"],
                    "spread": row["spread"],
                    "real_volume": row["real_volume"],
                }
            )

    print(f"Đã ghi {len(rates)} nến M1 -> {out}")
    mt5.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
