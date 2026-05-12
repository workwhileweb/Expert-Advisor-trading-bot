# Hướng dẫn sử dụng Expert Advisor `bot` và ý nghĩa các Input

Tài liệu này mô tả cách vận hành EA **`bot`** (file `bot.mq5` / `bot.ex5`), cách chỉnh **tab Inputs** trong MetaTrader 5, và ý nghĩa từng tham số. Phần cài MT5, chạy `.exe`, và `config.json` xem thêm [`README.md`](README.md) và [`HUONG_DAN_CONFIG.md`](HUONG_DAN_CONFIG.md).

**Cảnh báo:** Giao dịch có rủi ro. Chỉ dùng vốn chấp nhận mất. Nên thử **demo** và **Strategy Tester** trước khi chạy tài khoản thật.

---

## 1. EA làm gì (tóm tắt)

- Chạy trên **một biểu đồ** của MetaTrader 5; mọi lệnh dùng **`Symbol()`** — tức **symbol của chart** đang gắn EA.
- Bên trong code, MACD và phân tích nến/vùng giá dùng khung **M1** (`PERIOD_M1`), không phụ thuộc khung thời gian bạn chọn cho chart (chart vẫn nên là symbol đúng ý định giao dịch).
- Chiến lược hiện tại chỉ đặt **lệnh chờ bán — Sell Limit** khi đủ điều kiện kỹ thuật; **không** có logic mua (Buy).

---

## 2. Chuẩn bị file và cài EA

1. Sao chép `bot.mq5` (và `bot.ex5` nếu đã compile) vào thư mục **`MQL5\Experts\`** của terminal MT5, hoặc dùng script `install-ea.bat` như trong [`README.md`](README.md).
2. Mở **MetaEditor** (F4 trong MT5), mở `bot.mq5`, nhấn **Compile** (F7). Nếu thành công sẽ có `bot.ex5` cùng thư mục.
3. Trong MT5: **Navigator** → **Expert Advisors** → kéo **`bot`** lên biểu đồ.

---

## 3. Cách mở và sửa Input

1. Khi kéo EA lên chart, cửa sổ thuộc tính EA hiện ra.
2. Chọn tab **Inputs** (Đầu vào / Inputs).
3. Chỉnh các giá trị, sau đó nhấn **OK**.

**Để sửa Input sau khi EA đã chạy:** chuột phải vào **mặt smiley** / tên EA góc chart → **Expert list** hoặc **Thuộc tính** tương đương → mở lại EA → tab **Inputs**. Lưu ý: một số thay đổi chỉ áp dụng rõ ràng khi **gỡ EA và gắn lại** (ví dụ logic phụ thuộc trạng thái khởi tạo).

---

## 4. Bảng tham số Input và ý nghĩa

| Tên trong MT5 | Kiểu | Mặc định (tham chiếu) | Ý nghĩa |
|---------------|------|------------------------|---------|
| **InpLanguage** | Enum (Tiếng Việt / English) | Tiếng Việt | Ngôn ngữ các thông báo `Print` trong tab **Experts** / nhật ký: tiếng Việt hoặc tiếng Anh. **Không** ảnh hưởng giá vào lệnh. |
| **RiskAmount** | Số thực | `50.0` | **Rủi ro tiền** bạn chấp nhận cho **một** lệnh (đơn vị = **tiền tệ tài khoản**), dùng để tính **khối lượng (lot)** từ khoảng cách tới Stop Loss. Phải **> 0**. |
| **MaxDailyLoss** | Số thực | `200.0` | Khi **lỗ lũy kế** (so với số dư lúc EA khởi động) đạt ngưỡng này, EA **dừng** tìm lệnh mới. Phải **> 0**. *Ghi chú kỹ thuật:* mốc so sánh là balance tại **`OnInit`** (lúc gắn/tải lại EA), không tự reset theo lịch 0h — nếu cần “ngày mới”, hãy **tải lại EA** trên chart hoặc chờ bản EA hỗ trợ reset theo lịch. |
| **LookbackPeriod** | Số nguyên | `20` | Số nến (M1) dùng khi tìm vùng **hỗ trợ / kháng cự** (fractal). Giá trị lớn hơn → nhìn xa hơn, có thể thay đổi “độ mượt” của mức S/R. |
| **MinRiskReward** | Số thực | `2.0` | **Tỷ lệ lợi nhuận / rủi ro tối thiểu** cho Take Profit so với khoảng cách entry–support (R:R). Phải **> 1.0** (trong code, `<= 1.0` sẽ báo tham số không hợp lệ và EA không khởi động). |
| **MagicNumber** | Số nguyên | `234567` | **Mã magic** gắn vào lệnh/vị thế để EA chỉ quản lý đúng lệnh của mình (tránh lẫn tay với EA khác hoặc lệnh thủ công nếu bạn cũng dùng magic khác). |
| **EnableLogging** | true/false | `true` | Bật/tắt nhiều dòng **log chi tiết** (spread, MACD, S/R, lỗi đặt lệnh…). Tắt (`false`) nếu muốn nhật ký gọn hơn; **không** tắt rủi ro tài chính, chỉ giảm log. |
| **MaxSpreadPoints** | Số nguyên | `0` | Giới hạn **spread theo đúng số mà MT5 báo** (`SYMBOL_SPREAD`, đơn vị *points* — khác nhau từng symbol). **`0` = tắt** kiểm tra spread (tránh lỗi “Spread too high” trên vàng/CFD khi trước đây ngưỡng cố định theo giá chỉ hợp forex). Nếu muốn lọc: xem spread hiện tại trên MT5 (Market Watch → cột Spread hoặc log), đặt ví dụ **30–40** cho EURUSD 5 số, **400–600** cho XAUUSD tùy broker. |
| **EnablePeriodicStatus** | true/false | `true` | Bật **báo cáo định kỳ** trên tab **Experts**: symbol, **% đủ điều kiện vào lệnh** (9 bước đánh giá độc lập), từng mục Đạt/Chưa, spread hiện tại và `MaxSpreadPoints`. Giúp biết EA đang chạy và còn thiếu điều kiện nào (không thay cho log chi tiết từng tick). |
| **StatusIntervalSeconds** | Số nguyên | `60` | Khoảng cách giữa hai báo cáo (giây). **Tối thiểu 10** (nhỏ hơn EA không khởi động). Đặt **`0`** để không gửi báo cáo theo chu kỳ (kết hợp tắt `EnablePeriodicStatus` hoặc để interval = 0). |

**9 bước dùng để tính %:** (1) Chưa vượt lỗ ngày (2) `tradingEnabled` (3) Đã qua 60 giây sau lệnh trước (4) Không có vị thế mở (5) Spread (6) MACD (7) Vùng giảm (8) Hỗ trợ/Kháng cự hợp lệ (9) FVG + kháng cự. **100%** = đủ điều kiện để EA **có thể** đặt Sell Limit (còn phụ thuộc tick khớp logic đặt lệnh).

**Kiểm tra khi khởi động:** Nếu `RiskAmount ≤ 0`, `MaxDailyLoss ≤ 0`, hoặc `MinRiskReward ≤ 1.0`, EA báo lỗi tham số và **không chạy** (`INIT_FAILED`). Nếu **EnablePeriodicStatus** bật và `0 < StatusIntervalSeconds < 10`, EA cũng **không chạy**.

---

## 5. Bật giao dịch tự động (AutoTrading)

EA chỉ gửi lệnh khi:

1. Nút **Algo Trading / AutoTrading** trên MT5 đang **bật** (thường **Ctrl+E**).
2. Trong thuộc tính EA, tab **Common**: tick **Allow Algo Trading** (Cho phép giao dịch thuật toán).
3. Tài khoản và server broker cho phép EA giao dịch; đủ ký quỹ; symbol cho phép pending order.

Khi thị trường có **tick**, MT5 gọi `OnTick()` — EA tự đánh giá điều kiện; bạn không cần bấm tay từng lệnh.

---

## 6. Điều kiện để EA đặt lệnh (luồng tóm tắt)

EA **không** vào lệnh liên tục; mỗi tick phải qua lần lượt các bước sau (thiếu một bước là bỏ qua):

1. Chưa vượt **MaxDailyLoss** (so với balance lúc khởi động EA).
2. Trạng thái cho phép trade (sau khi vượt ngưỡng lỗ, EA tự tắt tìm lệnh mới cho đến khi bạn gắn lại).
3. Đã qua ít nhất **60 giây** kể từ lần đặt lệnh thành công trước.
4. **Không** có vị thế đang mở (`PositionsTotal() == 0`).
5. **Spread** (nếu **MaxSpreadPoints** > 0): spread theo MT5 không được vượt ngưỡng; **`0` = bỏ qua** bước này.
6. **MACD M1:** tín hiệu xác nhận (cắt xuống + động lượng giảm) theo logic trong `CheckMACD()`.
7. Phát hiện **vùng giảm** sau đẩy tăng (`DetectBearishZone`).
8. **Hỗ trợ / kháng cự** hợp lệ từ `LookbackPeriod`.
9. Điều kiện **FVG và kháng cự** (`IsFVGAndResistanceAligned`).

Thỏa mãn → đặt **Sell Limit** với SL/TP và lot tính từ **RiskAmount** và **MinRiskReward**.

---

## 7. Gợi ý chỉnh Input theo mục đích

| Mục đích | Gợi ý |
|----------|--------|
| Giảm rủi ro mỗi lệnh | Giảm **RiskAmount** (ví dụ 10–25 trên demo nhỏ). |
| Chặt chẽ hơn với chuỗi lỗ | Giảm **MaxDailyLoss** hoặc gắn lại EA đầu phiên để reset mốc balance. |
| TP xa hơn / gần hơn | Tăng/giảm **MinRiskReward** (luôn > 1). |
| Nhiều EA trên cùng symbol | Đổi **MagicNumber** cho từng EA để không chồng chéo quản lý vị thế. |
| S/R “rộng” hoặc “hẹp” hơn | Tăng/giảm **LookbackPeriod** và quan sát trên Tester / demo. |
| Vàng/XAU bị log “Spread too high” | Để **MaxSpreadPoints = 0** (tắt lọc) hoặc đặt số **lớn hơn** spread thực tế (ví dụ 500) sau khi đọc cột Spread trên terminal. |

---

## 8. Kiểm thử (Strategy Tester)

1. **View** → **Strategy Tester** (**Ctrl+R**).
2. Expert: **bot**, symbol và khoảng ngày có dữ liệu M1 đủ dài.
3. Model: **Every tick** nếu máy cho phép.
4. Tab **Inputs** trong Tester: chỉnh giống ý định chạy thật.

---

## 9. Xử lý nhanh khi “EA không trade”

- **AutoTrading** đã bật chưa?
- Tab **Experts** có báo “tham số không hợp lệ”, “spread quá cao”, “Hỗ trợ/Kháng cự không hợp lệ” không? (Bật **EnableLogging** để dễ đọc.) Nếu log so spread kiểu **points** với ngưỡng quá nhỏ: chỉnh **MaxSpreadPoints** hoặc đặt **0**.
- Tài khoản có đang có **position** mở khiến EA chờ không?
- Symbol có cho phép **Sell Limit** và khớp quy tắc broker không?

---

**Tóm tắt:** Gắn **bot** lên chart đúng symbol → tab **Inputs** chỉnh rủi ro và ngưỡng → bật **Algo Trading** → theo dõi log. Tham số `config.json` chỉ dùng cho công cụ **Python / .exe** kèm repo, **không** thay thế các Input của file `bot.mq5`.
