# Hướng dẫn cấu hình `config.json`

Tài liệu này giải thích từng tham số trong `config.json` và cách chỉnh cho người mới. File nằm cùng thư mục gốc dự án, định dạng **JSON** (phải hợp lệ: dấu phẩy, ngoặc, chuỗi trong dấu ngoặc kép).

## Bắt đầu nhanh

1. Sao chép `config.json` thành bản backup trước khi sửa.
2. Mở file bằng trình soạn thảo UTF-8 (VS Code, Notepad++).
3. Sau khi sửa, chạy kiểm tra: `config_manager.exe` — nếu cấu hình hợp lệ, chương trình in trạng thái tải config thành công; nếu sai, sẽ có thông báo lỗi cụ thể (thiếu mục, giá trị không hợp lệ, v.v.).

## Cấu trúc tổng quan

File gồm **5 mục bắt buộc** (thiếu một mục là `ConfigManager` báo lỗi):

| Mục        | Mục đích |
|------------|----------|
| `trading`  | Rủi ro, spread, magic number |
| `analysis` | Tham số chỉ báo / phân tích kỹ thuật |
| `symbols`  | Danh sách cặp tiền và khung thời gian |
| `logging`  | Ghi log khi chạy Python |
| `mt5`      | Đường dẫn terminal MT5, timeout, thử lại |

---

## 1. `trading` — giao dịch và rủi ro

| Tham số | Kiểu | Ý nghĩa | Gợi ý cho người mới |
|---------|------|---------|---------------------|
| `risk_amount` | số thực | Số **tiền rủi ro mỗi lệnh** (theo đơn vị tiền tài khoản, ví dụ USD). Dùng khi tính khối lượng lot tương ứng khoảng cách SL. | Bắt đầu nhỏ (10–50) trên tài khoản demo. **Phải &gt; 0** (bắt buộc). |
| `max_daily_loss` | số thực | Ngưỡng **lỗ tối đa trong ngày** (cùng đơn vị tiền TK). Vượt quá thì logic bot có thể dừng giao dịch trong ngày. | Đặt theo khả chịu đựng (ví dụ 1–2% vốn). **Phải &gt; 0**. |
| `min_risk_reward` | số thực | **Tỷ lệ R:R tối thiểu** (lợi nhuận mục tiêu so với rủi ro). Ví dụ `2.0` nghĩa là TP xa gấp đôi khoảng SL. | Thường từ 1.5–3. **Phải ≥ 1.0** (validator yêu cầu). |
| `max_spread_pips` | số thực | Giới hạn spread tối đa theo **pip** (dùng cho mô tả cấu hình; đồng bộ với logic thực tế tùy code EA/Python). | Với cặp chính, 2–4 pip là tham chiếu; chỉnh theo broker. |
| `max_risk_percent` | số thực | **Phần trăm vốn** tối đa chấp nhận cho một lệnh (ví dụ `5.0` = 5%). | Giữ thấp khi mới tập (1–5%). |
| `magic_number` | số nguyên | **Mã magic** để nhận diện lệnh do bot đặt (tránh lẫn lệnh tay). | Mỗi EA/bot một số riêng; không trùng EA khác trên cùng tài khoản nếu cần tách lệnh. |

---

## 2. `analysis` — phân tích (MACD, vùng giá)

Các giá trị này mô tả **chu kỳ chỉ báo và ngưỡng vùng hỗ trợ/kháng cự**. Trong mã hiện tại, EA `bot.mq5` dùng MACD cố định 12, 26, 9 trên M1 — nếu bạn đổi trong JSON, hãy **cập nhật tương ứng trong EA** để đồng nhất.

| Tham số | Kiểu | Ý nghĩa |
|---------|------|---------|
| `lookback_period` | số nguyên | Số nến nhìn lại để xác định vùng hỗ trợ/kháng cự. |
| `macd_fast` | số nguyên | Chu kỳ đường MACD nhanh (thường 12). |
| `macd_slow` | số nguyên | Chu kỳ đường MACD chậm (thước 26). |
| `macd_signal` | số nguyên | Chu kỳ đường tín hiệu (thường 9). |
| `support_resistance_touches` | số nguyên | Số lần “chạm” tối thiểu để coi là vùng S/R (logic chi tiết trong EA). |
| `candle_body_threshold` | số thực | Ngưỡng so sánh thân nến (lọc nến mạnh/yếu). |

---

## 3. `symbols` — danh sách cặp giao dịch

Đây là **mảng** các object. **Không được để mảng rỗng** — ít nhất một symbol.

Mỗi phần tử gồm:

| Trường | Kiểu | Ý nghĩa |
|--------|------|---------|
| `name` | chuỗi | Tên symbol trên MT5, ví dụ `EURUSD`, `XAUUSD` (phải khớp broker). |
| `enabled` | `true` / `false` | `true` mới được coi là “bật” khi code gọi `get_enabled_symbols()`. |
| `max_spread` | số thực | Spread tối đa chấp nhận được, theo **giá** (price), ví dụ `0.0003` ≈ 3 pip cho cặp 5 chữ số. |
| `timeframe` | chuỗi | Khung thời gian gợi ý, ví dụ `M1`, `M5` (để thống nhất tài liệu; EA mặc định dùng M1 ở nhiều chỗ). |

**Ví dụ thêm một cặp:**

```json
{
  "name": "USDJPY",
  "enabled": true,
  "max_spread": 0.02,
  "timeframe": "M1"
}
```

(Lưu ý: `max_spread` cho JPY thường khác thang đo so với EURUSD — chỉnh theo quan sát spread thực tế trên MT5.)

---

## 4. `logging` — ghi log (Python)

| Tham số | Kiểu | Ý nghĩa |
|---------|------|---------|
| `enabled` | `true` / `false` | Bật/tắt logging tổng thể. |
| `level` | chuỗi | Mức log: thường `DEBUG`, `INFO`, `WARNING`, `ERROR`. |
| `log_trades` | `true` / `false` | Có ghi chi tiết lệnh hay không. |
| `log_analysis` | `true` / `false` | Có ghi log bước phân tích hay không (thường nhiều hơn, tắt nếu chỉ cần gọn). |

---

## 5. `mt5` — kết nối MetaTrader 5

| Tham số | Kiểu | Ý nghĩa |
|---------|------|---------|
| `terminal_paths` | mảng chuỗi | Một hoặc nhiều đường dẫn tới `terminal64.exe`. Thứ tự ưu tiên thử khi khởi tạo. Trên Windows dùng `\\` trong JSON. |
| `connection_timeout` | số nguyên | Thời gian chờ kết nối (giây). |
| `retry_attempts` | số nguyên | Số lần thử lại khi lỗi tạm thời. |

Nếu MT5 cài chỗ khác, thêm đường dẫn đầy đủ vào mảng này.

---

## Kiểm tra hợp lệ (validator trong `config_manager`)

Chương trình kiểm tra:

- Đủ 5 mục: `trading`, `analysis`, `symbols`, `logging`, `mt5`.
- `trading.risk_amount` &gt; 0.
- `trading.max_daily_loss` &gt; 0.
- `trading.min_risk_reward` ≥ 1.0.
- `symbols` không rỗng.

Các trường khác **vẫn nên điền đúng kiểu** để tránh lỗi khi code đọc sau này.

---

## Quan trọng: `config.json` và Expert Advisor `bot.mq5`

- **`config.json`** được class `ConfigManager` (Python) đọc khi bạn viết script dùng nó.
- **EA trên MT5** nhận tham số qua tab **Inputs** trong MetaEditor/MT5 (`RiskAmount`, `MaxDailyLoss`, `LookbackPeriod`, …), **không tự đọc file JSON**.

Để hành vi giống nhau giữa Python và EA, bạn cần **đồng bộ tay** các giá trị tương ứng (rủi ro, MACD, spread tối đa, magic, v.v.). Nếu chỉ sửa JSON mà không đổi Inputs của EA, lệnh chạy trên chart vẫn theo tham số cũ của EA.

---

## Sửa lỗi JSON thường gặp

- Thiếu dấu phẩy giữa các trường hoặc phần tử mảng.
- Dấu nháy trong chuỗi Windows: dùng `\\` (ví dụ `C:\\Program Files\\...`).
- Số không đặt trong dấu ngoặc kép; chuỗi như `"EURUSD"` phải có ngoặc kép.
- Phần cuối object/mảng **không** có dấu phẩy thừa trước `}` hoặc `]`.

---

## Tóm tắt một dòng

| Bạn muốn… | Sửa chủ yếu ở đâu |
|-----------|-------------------|
| Giảm rủi ro mỗi lệnh | `trading.risk_amount` (+ Inputs EA `RiskAmount`) |
| Dừng sớm khi lỗ nhiều trong ngày | `trading.max_daily_loss` (+ `MaxDailyLoss` trên EA) |
| Chỉ giao dịch khi spread thấp | `symbols[].max_spread` và/hoặc logic spread trên EA |
| Tắt một cặp tạm thời | `symbols[].enabled`: `false` |
| Trỏ đúng bản MT5 | `mt5.terminal_paths` |

Nếu cần, có thể mở `config_manager` (hàm `validate_config` và `create_default_config`) để xem giá trị mặc định và quy tắc mới nhất trong mã nguồn.
