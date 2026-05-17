"""
Quét toàn bộ EA (.ex5) trong thư mục Experts của một bản MT5, gọi terminal64
với file cấu hình [Tester] để chạy Strategy Tester, xuất báo cáo .htm từng EA
và một index.html tổng hợp.

Tham khảo: MetaTrader 5 Help — "Running the platform with settings from the
configuration file" ([Tester] section).

Chạy (từ thư mục python):
  uv sync && uv run python batch_mt5_strategy_tester.py

Ví dụ:
  uv run python batch_mt5_strategy_tester.py --dry-run
  uv run python batch_mt5_strategy_tester.py --max 2 -o reports_out

Lưu ý:
- Cần terminal64.exe thuộc đúng bản MT5 có dữ liệu tại --terminal-data (thường
  là cùng broker). Nếu trong ...Terminal\\<hash>\\ có terminal64.exe (portable),
  script sẽ ưu tiên dùng.
- Symbol M1 và lịch sử phải có sẵn trong terminal đó (tải trước trên chart/tester).
- Mỗi EA chạy tuần tự; 1 năm M1 có thể rất lâu — dùng --max khi thử.
- File INI cho /config: luôn dùng đường dẫn tuyệt đối (cwd terminal khác thư mục script).
- terminal64 thường thoát ngay; script chờ file .htm xuất hiện (--timeout-per-ea, --report-poll).
- File cấu hình chạy tester: gộp `config/common.ini` của terminal (UTF-16) + khối [Tester]; MT5 thường bỏ qua INI chỉ UTF-8.
"""

from __future__ import annotations

import argparse
import html
import os
import re
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any


DEFAULT_EXPERTS_DIR = Path(
    r"C:\Users\workw\AppData\Roaming\MetaQuotes\Terminal"
    r"\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts"
)
DEFAULT_TERMINAL_DATA = Path(
    r"C:\Users\workw\AppData\Roaming\MetaQuotes\Terminal"
    r"\D0E8209F77C8CF37AD8BF550E51FF075"
)


def _utf8_stdio() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


def find_terminal64(terminal_data: Path, explicit: str | None) -> Path:
    if explicit:
        p = Path(explicit)
        if not p.is_file():
            raise FileNotFoundError(f"Không thấy terminal64: {p}")
        return p
    portable = terminal_data / "terminal64.exe"
    if portable.is_file():
        return portable
    roots = [
        Path(os.environ.get("PROGRAMFILES", r"C:\Program Files")),
        Path(os.environ.get("PROGRAMFILES(X86)", r"C:\Program Files (x86)")),
    ]
    for root in roots:
        cand = root / "MetaTrader 5" / "terminal64.exe"
        if cand.is_file():
            return cand
    roaming = Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal"
    if roaming.is_dir():
        for sub in sorted(roaming.iterdir()):
            exe = sub / "terminal64.exe"
            if exe.is_file():
                return exe
    raise FileNotFoundError(
        "Không tìm thấy terminal64.exe. Truyền --terminal64 đường dẫn đầy đủ."
    )


def expert_ini_key(ex5: Path, experts_root: Path) -> str:
    rel = ex5.resolve().relative_to(experts_root.resolve())
    stem = rel.with_suffix("")
    return str(stem).replace("/", "\\")


def safe_slug(s: str) -> str:
    out = re.sub(r"[^\w\-.]+", "_", s, flags=re.UNICODE).strip("_")
    return out[:100] if out else "ea"


@dataclass
class RunResult:
    ex5: Path
    expert_key: str
    slug: str
    report_htm: Path | None = None
    error: str | None = None
    metrics: dict[str, Any] = field(default_factory=dict)


def strip_tester_section(text: str) -> str:
    """Bỏ khối [Tester] ... (tới section [ khác) khỏi nội dung common.ini."""
    lines = text.splitlines()
    out: list[str] = []
    skip = False
    for line in lines:
        s = line.strip()
        if len(s) >= 2 and s.startswith("[") and s.endswith("]"):
            name = s[1:-1].strip().lower()
            if name == "tester":
                skip = True
                continue
            skip = False
        if not skip:
            out.append(line)
    return "\r\n".join(out).rstrip("\r\n")


def format_tester_section(
    *,
    expert_key: str,
    symbol: str,
    period: str,
    from_date: date,
    to_date: date,
    deposit: int,
    currency: str,
    leverage: str,
    model: int,
    report_path_no_ext: str,
    expert_parameters: str | None,
) -> str:
    """Chỉ khối [Tester] (không gồm [Common]). report_path_no_ext: path không đuôi .htm."""
    lines = [
        "[Tester]",
        f"Expert={expert_key}",
        f"Symbol={symbol}",
        f"Period={period}",
        "Login=0",
        f"Model={model}",
        "ExecutionMode=0",
        "Optimization=0",
        "OptimizationCriterion=0",
        f"FromDate={from_date.year:04d}.{from_date.month:02d}.{from_date.day:02d}",
        f"ToDate={to_date.year:04d}.{to_date.month:02d}.{to_date.day:02d}",
        "ForwardMode=0",
        f"Deposit={deposit}",
        f"Currency={currency}",
        f"Leverage={leverage}",
        f"Report={report_path_no_ext}",
        "ReplaceReport=1",
        "ShutdownTerminal=1",
        "Visual=0",
        "UseLocal=1",
        "UseRemote=0",
        "UseCloud=0",
    ]
    if expert_parameters:
        ins_at = lines.index("[Tester]") + 2
        lines.insert(ins_at, f"ExpertParameters={expert_parameters}")
    return "\r\n".join(lines)


def compose_runner_ini_text(terminal_data: Path, tester_section: str) -> str:
    """
    Gộp config/common.ini (UTF-16, có BOM) của terminal với [Tester].
    Nếu không có common.ini thì dùng [Common] tối thiểu.
    """
    common = terminal_data / "config" / "common.ini"
    if common.is_file():
        raw = common.read_text(encoding="utf-16", errors="replace")
        base = strip_tester_section(raw).rstrip() + "\r\n\r\n"
        return base + tester_section.strip() + "\r\n"
    return (
        "[Common]\r\nKeepPrivate=1\r\nNewsEnable=0\r\n\r\n"
        + tester_section.strip()
        + "\r\n"
    )


def write_terminal_ini(path: Path, text: str) -> None:
    """Ghi UTF-16 với BOM (codec utf-16 của Python), giống common.ini MT5."""
    path.write_bytes(text.encode("utf-16"))


def _parse_money(s: str) -> float | None:
    s = s.strip().replace(" ", "").replace("\u00a0", "")
    s = s.replace(",", "")
    if re.fullmatch(r"-?[\d.]+", s):
        try:
            return float(s)
        except ValueError:
            return None
    m = re.search(r"-?[\d.]+", s)
    if m:
        try:
            return float(m.group(0))
        except ValueError:
            return None
    return None


def parse_tester_htm(path: Path) -> dict[str, Any]:
    """Trích xuất tối thiểu từ báo cáo Strategy Tester (.htm) — EN/VN label."""
    raw = path.read_text(encoding="utf-8", errors="ignore")
    text = re.sub(r"<script[\s\S]*?</script>", " ", raw, flags=re.I)
    text = re.sub(r"<style[\s\S]*?</style>", " ", text, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text)

    def grab(*labels: str) -> float | None:
        for lb in labels:
            pat = re.compile(
                re.escape(lb) + r"[\s:]*([-\d\s.,\u00a0]+)",
                re.I,
            )
            m = pat.search(text)
            if m:
                v = _parse_money(m.group(1))
                if v is not None:
                    return v
        return None

    net = grab("Total net profit", "Tổng lợi nhuận ròng", "Total Net Profit")
    gross_profit = grab("Gross profit", "Tổng lãi", "Gross Profit")
    gross_loss = grab("Gross loss", "Tổng lỗ", "Gross Loss")
    balance_end = grab("Ending balance", "Số dư cuối", "Balance")
    profit_factor = grab("Profit factor", "Hệ số lợi nhuận", "Profit Factor")

    equity_curve: list[float] = []
    # Một số bản nhúng mảng số trong JS
    for pat in (
        r"balance\s*[:=]\s*\[([\d\s.,\-]+)\]",
        r"graphBalance\s*=\s*\[([\d\s.,\-]+)\]",
        r"\"balance\"\s*:\s*\[([\d\s.,\-]+)\]",
    ):
        m = re.search(pat, raw, re.I)
        if m:
            parts = re.split(r"[\s,]+", m.group(1).strip())
            for p in parts:
                if not p:
                    continue
                v = _parse_money(p)
                if v is not None:
                    equity_curve.append(v)
            if equity_curve:
                break

    inputs_block = ""
    m_in = re.search(
        r"(Input parameters|Thông số đầu vào|Inputs)[\s\S]{0,8000}?(<table[\s\S]*?</table>)",
        raw,
        re.I,
    )
    if m_in:
        inputs_block = m_in.group(2)

    return {
        "total_net_profit": net,
        "gross_profit": gross_profit,
        "gross_loss": gross_loss,
        "profit_factor": profit_factor,
        "balance_end": balance_end,
        "equity_curve": equity_curve,
        "inputs_table_html": inputs_block,
    }


def svg_polyline_from_series(values: list[float], width: int = 640, height: int = 120) -> str:
    if len(values) < 2:
        return ""
    vmin, vmax = min(values), max(values)
    pad = 4
    if vmax - vmin < 1e-9:
        vmax = vmin + 1.0
    pts: list[str] = []
    n = len(values) - 1
    for i, v in enumerate(values):
        x = pad + (width - 2 * pad) * (i / max(n, 1))
        y = height - pad - (height - 2 * pad) * ((v - vmin) / (vmax - vmin))
        pts.append(f"{x:.1f},{y:.1f}")
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <rect width="100%" height="100%" fill="#f8fafc"/>
  <polyline fill="none" stroke="#2563eb" stroke-width="2" points="{' '.join(pts)}"/>
</svg>"""


def find_report_file(
    slug: str,
    terminal_data: Path,
    terminal64: Path,
    files_rel: Path,
) -> Path | None:
    """Tìm file .htm vừa sinh (theo tên gốc slug). files_rel = MQL5/Files/ea_batch_reports/<batch_id>."""
    dirs = [
        terminal_data / files_rel,
        terminal64.parent / files_rel,
    ]
    names = [f"{slug}.htm", f"{slug}.html"]
    for d in dirs:
        if not d.is_dir():
            continue
        for nm in names:
            p = d / nm
            if p.is_file():
                return p
    # fallback: newest matching slug prefix
    for d in dirs:
        if not d.is_dir():
            continue
        matches = sorted(d.glob(f"{slug}*.htm"), key=lambda p: p.stat().st_mtime, reverse=True)
        if matches:
            return matches[0]
    return None


def wait_for_report_file(
    *,
    expected_htm: Path,
    slug: str,
    terminal_data: Path,
    terminal64: Path,
    files_rel: Path | None,
    poll_seconds: float = 3.0,
    timeout_seconds: float | None = None,
) -> Path | None:
    """
    MT5 thường trả shell ngay khi chạy terminal64; báo cáo .htm xuất sau khi test xong.
    Ưu tiên file tại expected_htm (Report= đường dẫn tuyệt đối), sau đó thư mục terminal/cài đặt.
    """
    deadline = (
        None
        if timeout_seconds is None or timeout_seconds <= 0
        else time.monotonic() + float(timeout_seconds)
    )
    last_size = -1
    stable_rounds = 0
    started = time.monotonic()
    round_n = 0
    while True:
        round_n += 1
        if round_n > 1 and round_n % max(1, int(60 / max(poll_seconds, 0.5))) == 0:
            elapsed = int(time.monotonic() - started)
            print(f"  ... vẫn chờ file .htm ({elapsed}s)", flush=True)
        rep: Path | None = None
        if expected_htm.is_file():
            rep = expected_htm
        elif expected_htm.with_suffix(".html").is_file():
            rep = expected_htm.with_suffix(".html")
        elif files_rel is not None:
            rep = find_report_file(slug, terminal_data, terminal64, files_rel)
        if rep is not None and rep.is_file():
            try:
                sz = rep.stat().st_size
            except OSError:
                sz = 0
            if sz >= 64:
                if sz == last_size:
                    stable_rounds += 1
                    if stable_rounds >= 2:
                        return rep
                else:
                    stable_rounds = 0
                last_size = sz
        if deadline is not None and time.monotonic() > deadline:
            return None
        time.sleep(poll_seconds)


def write_aggregate_html(
    out_dir: Path,
    results: list[RunResult],
    *,
    symbol: str,
    period: str,
    from_date: date,
    to_date: date,
    deposit: int,
    generated_at: str,
) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    detail_dir = out_dir / "detail"
    detail_dir.mkdir(exist_ok=True)

    rows: list[str] = []
    sections: list[str] = []

    for r in results:
        name = html.escape(r.ex5.name)
        key = html.escape(r.expert_key)
        err = html.escape(r.error or "")
        m = r.metrics
        profit = m.get("total_net_profit")
        profit_s = f"{profit:,.2f}" if isinstance(profit, (int, float)) else "—"
        curve = m.get("equity_curve") or []
        curve_svg = svg_polyline_from_series(curve) if len(curve) >= 2 else ""
        if not curve_svg and r.report_htm:
            curve_svg = (
                f'<p class="muted">Không trích được chuỗi vốn từ HTML; '
                f'xem biểu đồ trong báo cáo gốc bên dưới.</p>'
            )

        rel_detail = ""
        if r.report_htm and r.report_htm.exists():
            dest = detail_dir / f"{r.slug}.htm"
            try:
                dest.write_bytes(r.report_htm.read_bytes())
                rel_detail = f"detail/{html.escape(dest.name)}"
            except OSError:
                rel_detail = ""

        inp_tbl = m.get("inputs_table_html") or ""
        if inp_tbl:
            inp_tbl = f'<div class="inputs">{inp_tbl}</div>'
        else:
            inp_tbl = '<p class="muted">Không đọc được bảng input từ .htm (dùng mặc định EA hoặc file .set).</p>'

        detail_link = (
            f'<a href="{html.escape(rel_detail)}">Chi tiết</a>' if rel_detail else "—"
        )
        rows.append(
            "<tr>"
            f"<td>{name}</td>"
            f"<td><code>{key}</code></td>"
            f"<td>{profit_s}</td>"
            f"<td>{'OK' if r.report_htm and not r.error else err or 'Thiếu báo cáo'}</td>"
            f"<td>{detail_link}</td>"
            "</tr>"
        )

        sections.append(
            f'<section class="card"><h2>{name}</h2>'
            f"<p><strong>Expert (Tester):</strong> <code>{key}</code></p>"
            f"<p><strong>Symbol:</strong> {html.escape(symbol)} &nbsp;|&nbsp; "
            f"<strong>Timeframe:</strong> {html.escape(period)} &nbsp;|&nbsp; "
            f"<strong>Từ–đến:</strong> {from_date} → {to_date} &nbsp;|&nbsp; "
            f"<strong>Vốn:</strong> {deposit:,.0f}</p>"
            f"<p><strong>Lãi/lỗ (ròng, nếu đọc được):</strong> {profit_s}</p>"
            f"<h3>Đường cong vốn (ước lượng từ dữ liệu trong báo cáo)</h3>"
            f'<div class="curve">{curve_svg}</div>'
            f"<h3>Thông số đầu vào (từ báo cáo HTML)</h3>{inp_tbl}"
            + (
                f'<iframe title="report" src="{html.escape(rel_detail)}"></iframe>'
                if rel_detail
                else f"<p class=\"muted\">{err}</p>"
            )
            + "</section>"
        )

    index = out_dir / "index.html"
    body = f"""<!DOCTYPE html>
<html lang="vi">
<head>
<meta charset="utf-8"/>
<title>Báo cáo tổng — Strategy Tester batch</title>
<style>
body {{ font-family: system-ui, sans-serif; margin: 24px; background: #0f172a0d; color: #0f172a; }}
h1 {{ font-size: 1.35rem; }}
table {{ border-collapse: collapse; width: 100%; background: #fff; }}
th, td {{ border: 1px solid #e2e8f0; padding: 8px 10px; text-align: left; vertical-align: top; }}
th {{ background: #f1f5f9; }}
.muted {{ color: #64748b; font-size: 0.9rem; }}
.card {{ background: #fff; border: 1px solid #e2e8f0; border-radius: 10px; padding: 16px 20px; margin: 20px 0; }}
iframe {{ width: 100%; height: 720px; border: 1px solid #cbd5e1; border-radius: 8px; margin-top: 12px; }}
.inputs {{ overflow-x: auto; max-height: 320px; }}
.inputs table {{ font-size: 0.85rem; }}
.curve {{ margin: 8px 0; }}
code {{ font-size: 0.85rem; }}
</style>
</head>
<body>
<h1>Báo cáo tổng Strategy Tester</h1>
<p class="muted">Tạo lúc: {html.escape(generated_at)} — Symbol: {html.escape(symbol)} — Khung: {html.escape(period)} — Khoảng: {from_date} → {to_date} — Vốn ban đầu: {deposit:,.0f}</p>
<table>
<thead><tr><th>EA (.ex5)</th><th>Expert=</th><th>Lãi/lỗ ròng (ước lượng)</th><th>Trạng thái</th><th>Chi tiết</th></tr></thead>
<tbody>
{"".join(rows)}
</tbody>
</table>
{"".join(sections)}
</body>
</html>"""
    index.write_text(body, encoding="utf-8")
    return index


def collect_ex5(experts_dir: Path) -> list[Path]:
    return sorted(experts_dir.rglob("*.ex5"), key=lambda p: str(p).lower())


def main() -> int:
    _utf8_stdio()
    parser = argparse.ArgumentParser(
        description="Quét .ex5, chạy Strategy Tester qua terminal64 + INI, gom báo cáo HTML.",
    )
    parser.add_argument(
        "--experts-dir",
        type=Path,
        default=DEFAULT_EXPERTS_DIR,
        help="Thư mục MQL5/Experts (chứa .ex5).",
    )
    parser.add_argument(
        "--terminal-data",
        type=Path,
        default=DEFAULT_TERMINAL_DATA,
        help="Thư mục dữ liệu terminal (…Terminal\\<hash>).",
    )
    parser.add_argument(
        "--terminal64",
        default=os.environ.get("MT5_TERMINAL64", ""),
        help="Đường dẫn terminal64.exe (hoặc biến môi trường MT5_TERMINAL64).",
    )
    parser.add_argument("--symbol", default="XAUUSDm", help="Symbol tester (mặc định: XAUUSDm).")
    parser.add_argument("--period", default="M1", help="Khung thời gian tester (mặc định: M1).")
    parser.add_argument("--deposit", type=int, default=10_000, help="Vốn đầu vào.")
    parser.add_argument("--currency", default="USD", help="Tiền tệ deposit (ISO).")
    parser.add_argument("--leverage", default="1:100", help="Đòn bẩy, ví dụ 1:100.")
    parser.add_argument(
        "--model",
        type=int,
        default=1,
        help="0 every tick, 1 OHLC 1 phút, 2 open only, 4 real ticks (xem help MT5). Mặc định 1 (nhanh hơn).",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        default=Path("mt5_batch_reports") / datetime.now().strftime("%Y%m%d_%H%M%S"),
        help="Thư mục chứa index.html + detail/*.htm.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=365,
        help="Số ngày backtest tính ngược từ --to-date (mặc định 365).",
    )
    parser.add_argument(
        "--to-date",
        type=str,
        default="",
        help="Ngày kết thúc YYYY-MM-DD (mặc định: hôm nay, theo máy local).",
    )
    parser.add_argument(
        "--expert-parameters",
        default="",
        help="Tên file .set trong MQL5\\\\Profiles\\\\Tester (ví dụ: MyEA.set). Để trống = mặc định EA.",
    )
    parser.add_argument("--max", type=int, default=0, help="Giới hạn số EA (0 = không giới hạn).")
    parser.add_argument("--dry-run", action="store_true", help="Chỉ liệt kê .ex5, không chạy tester.")
    parser.add_argument(
        "--timeout-per-ea",
        type=int,
        default=0,
        help="Số giây tối đa chờ file báo cáo .htm sau khi bật terminal (0 = không giới hạn). "
        "MT5 thường thoát process cha ngay; script sẽ poll file báo cáo.",
    )
    parser.add_argument(
        "--report-poll",
        type=float,
        default=3.0,
        help="Khoảng cách (giây) giữa mỗi lần kiểm tra file .htm đã sinh chưa.",
    )
    args = parser.parse_args()

    experts_dir: Path = args.experts_dir
    terminal_data: Path = args.terminal_data
    if not experts_dir.is_dir():
        print(f"Không có thư mục Experts: {experts_dir}", file=sys.stderr)
        return 1
    if not terminal_data.is_dir():
        print(f"Không có thư mục terminal-data: {terminal_data}", file=sys.stderr)
        return 1

    experts_root = experts_dir.resolve()
    ex5_list = collect_ex5(experts_root)
    if args.max and args.max > 0:
        ex5_list = ex5_list[: args.max]

    print(f"Tìm thấy {len(ex5_list)} file .ex5 trong {experts_root}")
    if args.dry_run:
        for p in ex5_list:
            print(" ", p)
        return 0

    if not ex5_list:
        print("Không có .ex5 để chạy.")
        return 0
    terminal64 = find_terminal64(terminal_data, args.terminal64.strip() or None)
    print(f"Dùng terminal64: {terminal64}")

    to_d = date.today()
    if args.to_date.strip():
        to_d = date.fromisoformat(args.to_date.strip())
    from_d = to_d - timedelta(days=args.days)

    batch_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:8]
    files_rel = Path("MQL5") / "Files" / "ea_batch_reports" / batch_id

    out_dir: Path = args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    out_abs = out_dir.resolve()
    reports_stem_base = out_abs / "mt5_reports" / batch_id
    reports_stem_base.mkdir(parents=True, exist_ok=True)
    config_dir = out_dir / "configs"
    config_dir.mkdir(exist_ok=True)

    expert_parameters = args.expert_parameters.strip() or None

    results: list[RunResult] = []
    for ex5 in ex5_list:
        try:
            ek = expert_ini_key(ex5, experts_root)
        except ValueError:
            results.append(
                RunResult(
                    ex5=ex5,
                    expert_key="",
                    slug=safe_slug(ex5.stem),
                    error="ex5 không nằm trong --experts-dir",
                )
            )
            continue

        slug = safe_slug(ek.replace("\\", "_"))
        report_stem = reports_stem_base / slug
        report_path_no_ext = str(report_stem).replace("/", "\\")
        tester_block = format_tester_section(
            expert_key=ek,
            symbol=args.symbol,
            period=args.period,
            from_date=from_d,
            to_date=to_d,
            deposit=args.deposit,
            currency=args.currency,
            leverage=args.leverage,
            model=args.model,
            report_path_no_ext=report_path_no_ext,
            expert_parameters=expert_parameters,
        )
        ini_full = compose_runner_ini_text(terminal_data, tester_block)
        ini_path = (config_dir / f"{slug}.ini").resolve()
        write_terminal_ini(ini_path, ini_full)
        # Một số bản MT5 ổn định hơn khi /config trỏ vào thư mục config của đúng terminal data.
        td_cfg = terminal_data / "config"
        td_cfg.mkdir(parents=True, exist_ok=True)
        ini_td = (td_cfg / f"ea_batch_run_{batch_id}_{slug}.ini").resolve()
        write_terminal_ini(ini_td, ini_full)

        ini_arg = str(ini_td)
        cmd = [str(terminal64), f"/config:{ini_arg}"]
        print(f"\n=== Chạy: {ek} ===")
        print("Lệnh:", " ".join(cmd))
        proc: subprocess.Popen[bytes] | None = None
        try:
            proc = subprocess.Popen(
                cmd,
                cwd=str(terminal_data),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as e:
            results.append(RunResult(ex5=ex5, expert_key=ek, slug=slug, error=str(e)))
            continue

        timeout_sec: float | None = float(args.timeout_per_ea) if args.timeout_per_ea > 0 else None
        print(
            "Đang chờ báo cáo .htm"
            + (f" (tối đa {args.timeout_per_ea}s)..." if timeout_sec else " (không giới hạn thời gian)..."),
            flush=True,
        )
        expected_htm = report_stem.with_suffix(".htm")
        print(f"Báo cáo dự kiến: {expected_htm}", flush=True)
        rep = wait_for_report_file(
            expected_htm=expected_htm,
            slug=slug,
            terminal_data=terminal_data,
            terminal64=terminal64,
            files_rel=files_rel,
            poll_seconds=max(0.5, float(args.report_poll)),
            timeout_seconds=timeout_sec,
        )

        if proc is not None:
            try:
                proc.wait(timeout=45)
            except subprocess.TimeoutExpired:
                pass

        if rep is None:
            print(
                "Không thấy .htm. Gợi ý: (1) Đóng hết cửa sổ MetaTrader 5 rồi chạy lại — "
                "terminal đang mở sẵn thường khiến lệnh /config không chạy Strategy Tester; "
                "(2) tăng --timeout-per-ea; (3) kiểm tra symbol và lịch sử trong Tester.\n"
                f"INI đã ghi: {ini_td}",
                flush=True,
            )
            results.append(
                RunResult(
                    ex5=ex5,
                    expert_key=ek,
                    slug=slug,
                    error="Hết thời gian chờ hoặc không tìm thấy .htm (xem gợi ý trên log).",
                )
            )
            continue

        metrics: dict[str, Any] = {}
        try:
            metrics = parse_tester_htm(rep)
        except OSError as e:
            metrics = {"parse_error": str(e)}
        results.append(RunResult(ex5=ex5, expert_key=ek, slug=slug, report_htm=rep, metrics=metrics))

    index = write_aggregate_html(
        out_dir.resolve(),
        results,
        symbol=args.symbol,
        period=args.period,
        from_date=from_d,
        to_date=to_d,
        deposit=args.deposit,
        generated_at=datetime.now().isoformat(timespec="seconds"),
    )
    print(f"\nXong. Báo cáo tổng: {index}")
    return 0 if all(r.error is None and r.report_htm for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
