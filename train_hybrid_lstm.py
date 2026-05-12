"""Train Hybrid LSTM features and export ONNX for Hybrid_LSTM_TA.mq5."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np

try:
    import MetaTrader5 as mt5
except ImportError:  # pragma: no cover
    mt5 = None

try:
    import torch
    import torch.nn as nn
    from torch.utils.data import DataLoader, TensorDataset
except ImportError as exc:  # pragma: no cover
    raise SystemExit("Install PyTorch first: py -m pip install torch") from exc


FEATURE_COUNT = 5
DEFAULT_SEQ_LEN = 48
DEFAULT_HIDDEN = 32
DEFAULT_FLAT_THRESHOLD = 2.0
DEFAULT_TERMINAL_PATHS = (
    r"C:\Program Files\MetaTrader 5\terminal64.exe",
    r"C:\Program Files (x86)\MetaTrader 5\terminal64.exe",
)


def configure_console_encoding() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


def timeframe_from_name(name: str) -> int:
    if mt5 is None:
        raise RuntimeError("MetaTrader5 package is not installed.")

    mapping = {
        "M1": mt5.TIMEFRAME_M1,
        "M5": mt5.TIMEFRAME_M5,
        "M15": mt5.TIMEFRAME_M15,
        "M30": mt5.TIMEFRAME_M30,
        "H1": mt5.TIMEFRAME_H1,
        "H4": mt5.TIMEFRAME_H4,
        "D1": mt5.TIMEFRAME_D1,
    }
    key = name.upper()
    if key not in mapping:
        raise ValueError(f"Unsupported timeframe: {name}")
    return mapping[key]


def ensure_mt5_initialized(terminal_path: str | None = None) -> None:
    if mt5 is None:
        raise RuntimeError("MetaTrader5 package is not installed.")

    if mt5.initialize():
        return

    candidate_paths: list[str] = []
    if terminal_path:
        candidate_paths.append(terminal_path)
    candidate_paths.extend(DEFAULT_TERMINAL_PATHS)

    for path in candidate_paths:
        if not path or not os.path.exists(path):
            continue
        if mt5.initialize(path):
            return

    raise RuntimeError(f"mt5.initialize() failed: {mt5.last_error()}")


def resolve_symbol(requested: str) -> str:
    if mt5.symbol_select(requested, True):
        info = mt5.symbol_info(requested)
        if info is not None:
            return requested

    requested_key = requested.lower().replace(" ", "")
    symbols = mt5.symbols_get()
    if symbols is None:
        raise RuntimeError(f"Cannot list symbols for {requested}: {mt5.last_error()}")

    exact: list[str] = []
    partial: list[str] = []
    for item in symbols:
        name = item.name
        key = name.lower()
        if key == requested_key:
            exact.append(name)
        elif requested_key in key or key in requested_key:
            partial.append(name)

    for name in exact + partial:
        if mt5.symbol_select(name, True):
            info = mt5.symbol_info(name)
            if info is not None:
                return name

    raise RuntimeError(f"Cannot resolve symbol {requested}: {mt5.last_error()}")


def symbol_point(symbol: str) -> float:
    info = mt5.symbol_info(symbol)
    if info is None:
        raise RuntimeError(f"symbol_info({symbol}) failed: {mt5.last_error()}")
    return float(info.point)


def load_rates(symbol: str, timeframe: str, bars: int) -> np.ndarray:
    rates = mt5.copy_rates_from_pos(symbol, timeframe_from_name(timeframe), 0, bars)
    if rates is None or len(rates) < DEFAULT_SEQ_LEN + 5:
        raise RuntimeError(f"Not enough bars for {symbol}: {mt5.last_error()}")
    return rates


def average_range(high: np.ndarray, low: np.ndarray, start: int, length: int, point: float) -> float:
    end = min(start + length, len(high))
    if end <= start:
        return point
    ranges = np.maximum(high[start:end] - low[start:end], point)
    return float(np.mean(ranges))


def build_bar_feature(
    open_: np.ndarray,
    high: np.ndarray,
    low: np.ndarray,
    close: np.ndarray,
    shift: int,
    avg_range: float,
    point: float,
) -> np.ndarray:
    range_ = max(float(high[shift] - low[shift]), point)
    body = float(close[shift] - open_[shift])
    prev_return = float((close[shift] - close[shift - 1]) / max(avg_range, point))
    upper_wick = float((high[shift] - max(open_[shift], close[shift])) / range_)
    lower_wick = float((min(open_[shift], close[shift]) - low[shift]) / range_)
    range_ratio = float(range_ / max(avg_range, point))
    return np.asarray([body / range_, prev_return, upper_wick, lower_wick, range_ratio], dtype=np.float32)


def build_dataset(
    rates: np.ndarray,
    seq_len: int,
    point: float,
    flat_threshold_points: float,
) -> tuple[np.ndarray, np.ndarray]:
    open_ = rates["open"].astype(np.float64)
    high = rates["high"].astype(np.float64)
    low = rates["low"].astype(np.float64)
    close = rates["close"].astype(np.float64)

    xs: list[np.ndarray] = []
    ys: list[int] = []

    for end in range(seq_len, len(close) - 1):
        avg_range = average_range(high, low, end - 20, 20, point)
        window = np.zeros((seq_len, FEATURE_COUNT), dtype=np.float32)
        for step, shift in enumerate(range(end - seq_len + 1, end + 1)):
            window[step] = build_bar_feature(open_, high, low, close, shift, avg_range, point)

        delta = float(close[end + 1] - close[end])
        if delta > flat_threshold_points * point:
            label = 0
        elif delta < -flat_threshold_points * point:
            label = 1
        else:
            continue

        xs.append(window)
        ys.append(label)

    if not xs:
        raise RuntimeError("No training samples were built. Increase bars or lower flat threshold.")

    return np.stack(xs), np.asarray(ys, dtype=np.int64)


class HybridLstm(nn.Module):
    def __init__(self, input_size: int, hidden_size: int):
        super().__init__()
        self.lstm = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.fc = nn.Linear(hidden_size, 2)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        out, _ = self.lstm(x)
        return self.fc(out[:, -1, :])


def train_model(x: np.ndarray, y: np.ndarray, hidden: int, epochs: int, batch_size: int, lr: float) -> HybridLstm:
    device = torch.device("cpu")
    model = HybridLstm(FEATURE_COUNT, hidden).to(device)
    dataset = TensorDataset(torch.from_numpy(x), torch.from_numpy(y))
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=True)

    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)

    model.train()
    for _ in range(epochs):
        for batch_x, batch_y in loader:
            batch_x = batch_x.to(device)
            batch_y = batch_y.to(device)
            optimizer.zero_grad()
            logits = model(batch_x)
            loss = criterion(logits, batch_y)
            loss.backward()
            optimizer.step()

    model.eval()
    return model


def export_onnx(model: HybridLstm, seq_len: int, out_path: Path) -> None:
    import onnx

    model.eval()
    dummy = torch.randn(1, seq_len, FEATURE_COUNT, dtype=torch.float32)
    export_path = out_path.with_suffix(".export.onnx")
    torch.onnx.export(
        model,
        dummy,
        str(export_path),
        input_names=["input"],
        output_names=["logits"],
        dynamic_axes=None,
        opset_version=18,
    )

    onnx_model = onnx.load(str(export_path), load_external_data=True)
    onnx.save_model(
        onnx_model,
        str(out_path),
        save_as_external_data=False,
        location="",
        size_threshold=0,
    )
    export_path.unlink(missing_ok=True)

    data_path = Path(f"{out_path}.data")
    if data_path.exists():
        data_path.unlink()


def write_metadata(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train Hybrid LSTM and export ONNX.")
    parser.add_argument("--symbol", default="XAUUSDm")
    parser.add_argument("--timeframe", default="M1")
    parser.add_argument("--bars", type=int, default=50000)
    parser.add_argument("--seq-len", type=int, default=DEFAULT_SEQ_LEN)
    parser.add_argument("--hidden", type=int, default=DEFAULT_HIDDEN)
    parser.add_argument("--epochs", type=int, default=8)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--flat-threshold-points", type=float, default=DEFAULT_FLAT_THRESHOLD)
    parser.add_argument("--terminal-path", default="")
    parser.add_argument("--out-dir", default="models")
    return parser.parse_args()


def main() -> None:
    configure_console_encoding()
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    terminal_path = args.terminal_path.strip() or None
    ensure_mt5_initialized(terminal_path)

    try:
        symbol = resolve_symbol(args.symbol)
        point = symbol_point(symbol)
        rates = load_rates(symbol, args.timeframe, args.bars)
        x, y = build_dataset(rates, args.seq_len, point, args.flat_threshold_points)
        model = train_model(x, y, args.hidden, args.epochs, args.batch_size, args.lr)

        onnx_path = out_dir / "hybrid_lstm.onnx"
        meta_path = out_dir / "hybrid_lstm_onnx.json"
        export_onnx(model, args.seq_len, onnx_path)
        write_metadata(
            meta_path,
            {
                "input_name": "input",
                "output_name": "logits",
                "feature_count": FEATURE_COUNT,
                "sequence_length": args.seq_len,
                "hidden_size": args.hidden,
                "symbol": symbol,
                "timeframe": args.timeframe.upper(),
                "label_up_index": 0,
                "label_down_index": 1,
                "feature_order": ["body_ratio", "prev_return", "upper_wick", "lower_wick", "range_ratio"],
                "notes": "Copy hybrid_lstm.onnx to Terminal/MQL5/Files and set InpOnnxModelFile in Hybrid_LSTM_TA.mq5.",
            },
        )

        print(f"Symbol: {symbol}")
        print(f"Samples: {len(x)}")
        print(f"ONNX: {onnx_path.resolve()}")
        print(f"Meta: {meta_path.resolve()}")
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    main()
