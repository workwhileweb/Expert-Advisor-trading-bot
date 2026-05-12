# Chiến lược giao dịch Expert Advisor — phân tích theo mã nguồn (`bot.mq5`)

Tài liệu này mô tả **chi tiết chiến lược thực sự được cài trong code**, lý do từng khối logic, và **thứ tự các bước** khi EA chạy. Khung tham chiếu là file `bot.mq5` trong repository (cùng ý tưởng với phần “Chiến lược giao dịch” trong `readme_dev.md`, nhưng bám sát implementation).

---

## 1. Tổng quan chiến lược

EA chỉ tìm **cơ hội bán (bearish)** và đặt **lệnh chờ bán — Sell Limit** tại mức **kháng cự** đã xác định, khi thị trường thỏa chuỗi điều kiện: xác nhận MACD giảm, có “đẩy tăng” trước đó rồi nến giảm mạnh, có vùng hỗ trợ/kháng cự dạng fractal hợp lệ, và một kiểm tra **căn chỉnh FVG — Fair Value Gap** với kháng cự.

**Khung thời gian trong code:** toàn bộ dữ liệu giá và MACD đều dùng **`PERIOD_M1`** (1 phút). MACD cố định tham số **12, 26, 9** trên giá đóng (`PRICE_CLOSE`), tạo handle trong `OnInit()`.

---

## 2. Ý nghĩa và lý do chiến lược

### 2.1. Vì sao chỉ bán (supply / mean reversion từ kháng cự)?

- **Kháng cự** được hiểu là vùng **cung** — giá có xu hướng phản ứng khi tiếp cận lại sau động lượng.
- EA không vào lệnh market tại nến hiện tại mà đặt **Sell Limit tại `resistance`**: vào lệnh khi giá **hồi lên chạm lại** mức cung, thay vì đuổi theo giá đang chạy xuống — phù hợp tư duy “bán tại vùng được xác định trước”.

### 2.2. Vì sao cần “đẩy tăng” rồi nến giảm mạnh (`DetectBearishZone`)?

- Mục tiêu là lọc tình huống **đảo pha ngắn hạn**: trước đó có **ít nhất 3 nến tăng** trong cửa sổ nến quá khứ (chỉ số `i` từ 5 đến 8 trên M1), nến hiện tại **đóng thấp hơn mở (bearish)** và **thân nến lớn hơn ~1.5 lần** trung bình thân 5 nến trước.
- **Ý nghĩa:** tránh bán khi thị trường chỉ “sideway nhỏ”; ưu tiên khoảnh khắc **lực bán thể hiện rõ** sau một nhịp tăng.

### 2.3. Vì sao dùng MACD (`CheckMACD`)?

- **Giao cắt xuống:** đường MACD chính cắt **xuống dưới** đường tín hiệu (`macdMain[0] < macdSignal[0]` và trước đó `macdMain[1] >= macdSignal[1]`).
- **Động lượng giảm thêm:** `macdMain[0] < macdMain[1]` (đường MACD đang hướng xuống so với nến trước).
- **Ý nghĩa:** bám theo quán tính **momentum bearish** ngắn hạn trùng với ý đồ bán tại kháng cự.

### 2.4. Vì sao fractal cho S/R (`IdentifySupportZone` / `IdentifyResistanceZone`)?

- **Fractal đáy (hỗ trợ):** đáy cục bộ — `low[i]` thấp hơn 2 nến trước và 2 nến sau.
- **Fractal đỉnh (kháng cự):** đỉnh cục bộ — đối xứng với high.
- Trong số các fractal, EA chọn mức có **nhiều “chạm”** nhất: đếm số nến có `low` (hoặc `high`) nằm trong **5 point** của mức fractal đó.
- **Ý nghĩa:** ưu tiên mức giá **được thị trường kiểm tra nhiều lần** — gần với khái niệm S/R “có trọng lượng” hơn một swing đơn lẻ.

### 2.5. FVG trong code thực tế là gì? (`IsFVGAndResistanceAligned`)

Implementation **rất gọn**, khác với mô tả marketing đầy đủ “FVG + khối lượng” trong một số tài liệu tổng quan:

- `fvgStart = Low` của nến **shift 2** (M1).
- `fvgEnd = High` của nến **shift 0** (M1).
- Điều kiện: **`fvgStart < resistance` và `fvgEnd > resistance`** — tức mức **kháng cự** nằm trong **khoảng biên dưới–trên** được ghép từ hai mức giá đó.

**Ý nghĩa thực dụng trong code:** đây là bước **lọc thêm** để kháng cự không “lơ lửng” hoàn toàn ngoài vùng biến động giá rất gần hiện tại; không phải bộ quy tắc FVG SMC đầy đủ (imbalance ba nến, mitigation, v.v.) như trong phân tích tay.

---

## 3. Thực thi lệnh: giá vào, SL, TP (`SetSellLimit`)

| Thành phần | Công thức trong code |
|-------------|----------------------|
| **Giá vào (pending)** | `entryPrice = resistance` |
| **Stop loss** | `stopLoss = resistance + (resistance - support) * 0.5` — tức SL nằm **phía trên** entry một đoạn bằng **một nửa** biên độ `(resistance - support)` |
| **Take profit** | `riskRewardDistance = entryPrice - support`; `takeProfit = entryPrice - (riskRewardDistance * MinRiskReward)` |
| **R:R tối thiểu** | Input `MinRiskReward` (mặc định **2.0**) — dùng để kéo TP xa hơn entry theo bội số khoảng cách đến support |

**Lý do cấu trúc SL/TP:** rủi ro được neo theo **biên độ vùng** giữa support và resistance; TP scale theo `MinRiskReward` so với “nhịp” từ entry xuống support.

**Kiểm tra an toàn:** nếu `stopLoss <= entryPrice` hoặc `takeProfit >= entryPrice` thì **không gửi lệnh** (và log nếu bật logging).

**Loại lệnh:** `TRADE_ACTION_PENDING`, `ORDER_TYPE_SELL_LIMIT`, filling `ORDER_FILLING_IOC`, `magic = MagicNumber`, comment theo ngôn ngữ input.

---

## 4. Quản lý rủi ro và điều kiện vận hành

### 4.1. Khối lượng (`CalculateLotSize`)

- Tính **khoảng cách rủi ro** giá: `|stopLoss - entryPrice|`.
- Quy đổi sang tick, dùng `SYMBOL_TRADE_TICK_VALUE` và `SYMBOL_TRADE_TICK_SIZE` để suy ra lot sao cho **rủi ro tiền ~ `RiskAmount`** (đơn vị tiền tệ tài khoản).
- Làm tròn theo `SYMBOL_VOLUME_STEP`, clamp `minLot` / `maxLot`.
- **Trần bảo vệ:** không vượt quá **5% equity** tương đương rủi ro trên khoảng SL đó (`maxRiskPercent = 0.05`).

### 4.2. Giới hạn lỗ ngày (`CheckDailyLossLimit`)

- `dailyStartBalance` = số dư lúc `OnInit`.
- Mỗi tick: `dailyLoss = dailyStartBalance - currentBalance`; nếu `dailyLoss >= MaxDailyLoss` thì **`tradingEnabled = false`** và EA không còn phân tích vào lệnh mới.

**Lưu ý:** đây là so sánh **balance**, không phải equity peak-to-trough trong ngày; reset balance “ngày” không tách bạch theo lịch — chỉ từ lúc EA khởi động.

### 4.3. Spread (`IsSpreadAcceptable`)

- `maxSpread = 0.0003` **cố định trong code** (không đọc từ `config.json` trong EA).
- Spread = `SYMBOL_SPREAD * Point()`.

### 4.4. Chống spam lệnh

- `lastTradeTime`: sau khi đặt pending thành công, ghi thời gian; **60 giây** sau mới được phép chuỗi logic đặt lệnh tiếp (nếu các điều kiện khác vẫn thỏa).

### 4.5. Hòa vốn (`ManagePositions`)

- Với vị thế **SELL** của EA: `riskDistance = openPrice - stopLoss`; khi lợi nhuận thả nổi theo giá `currentProfit = openPrice - currentPrice` **≥ riskDistance** (tức đi được ít nhất **1R** theo khoảng entry–SL ban đầu) và SL chưa bằng giá mở, gửi **`TRADE_ACTION_SLTP`** đưa **SL về `openPrice`**.

---

## 5. Các bước xử lý trong `OnTick` (thứ tự thực thi)

Dưới đây là pipeline **đúng thứ tự trong mã**:

1. **`CheckDailyLossLimit()`** — nếu vượt ngưỡng → tắt giao dịch, thoát.
2. Nếu **`tradingEnabled == false`** → thoát.
3. Nếu chưa đủ **60 giây** sau `lastTradeTime` → thoát.
4. Nếu **`PositionsTotal() > 0`** → **thoát ngay** (không chạy các bước sau trên tick đó).
5. **`IsSpreadAcceptable()`** — spread quá lớn → thoát.
6. **`CheckMACD()`** — không có xác nhận MACD → thoát.
7. **`DetectBearishZone()`** — không có vùng giảm ý nghĩa → thoát.
8. **`IdentifySupportZone()`** và **`IdentifyResistanceZone()`** — nếu không hợp lệ hoặc `support >= resistance` → thoát (có thể log).
9. **`IsFVGAndResistanceAligned(support, resistance)`** — nếu đúng → **`SetSellLimit(support, resistance)`**.
10. **`ManagePositions()`** — được gọi **sau** khối trên.

**Ghi chú kỹ thuật quan trọng:** ở bước 4, khi **đã có ít nhất một vị thế mở**, hàm return trước bước 10, nên trong phiên bản code hiện tại **`ManagePositions()` thường không chạy khi đang giữ lệnh market**. Logic đưa SL về hòa vốn **được viết** nhưng **không được gọi** trong nhánh có position — đây là điểm cần sửa nếu muốn breakeven hoạt động đúng ý đồ (ví dụ: gọi `ManagePositions()` trước khi `return` khi có position, hoặc bỏ return sớm và tách nhánh “chỉ vào lệnh mới”).

**Lệnh chờ Sell Limit:** khi chỉ có pending mà chưa khớp, `PositionsTotal()` thường vẫn là 0, nên các tick vẫn có thể đi tới `ManagePositions()` — breakeven chỉ áp dụng khi đã có **position** SELL.

---

## 6. Tham số đầu vào (input) và ý nghĩa

| Input | Mặc định | Vai trò trong code |
|--------|----------|---------------------|
| `InpLanguage` | VI | Chỉ ảnh hưởng chuỗi log/comment. |
| `RiskAmount` | 50 | Rủi ro mục tiêu mỗi lệnh (tiền) khi tính lot. |
| `MaxDailyLoss` | 200 | Ngưỡng dừng EA theo chênh lệch balance. |
| `LookbackPeriod` | 20 | Độ dài copy low/high = `LookbackPeriod + 5` nến cho S/R fractal. |
| `MinRiskReward` | 2.0 | Hệ số nhân khoảng entry→support để đặt TP; phải **> 1.0** (validate `OnInit`). |
| `MagicNumber` | 234567 | Lọc lệnh/vị thế của EA. |
| `EnableLogging` | true | Bật/tắt log chi tiết lỗi/đặt lệnh. |

---

## 7. Bảng đối chiếu nhanh: `readme_dev.md` vs `bot.mq5`

| Nội dung trong readme | Trong code hiện tại |
|----------------------|---------------------|
| Phân tích đa khung | Chỉ **M1** cho MACD, S/R, FVG, bearish zone. |
| FVG “cải tiến”, xác nhận khối lượng | Chỉ kiểm tra **khoảng Low(2)–High(0)** có chứa `resistance`. |
| Histogram MACD | Chỉ dùng **đường MACD và đường signal**, không dùng buffer histogram. |
| Trailing stop tùy chọn | **Không có** trong `bot.mq5`. |
| `max_spread` từ `config.json` | EA dùng **0.0003 cố định**; file JSON phục vụ tooling Python. |

---

## 8. Tóm tắt một dòng

**Chiến lược:** trên **M1**, khi **MACD cắt xuống + momentum bearish**, có **nến giảm mạnh sau chuỗi tăng**, **fractal S/R hợp lệ** và **resistance nằm trong “vùng kiểm tra FVG” đơn giản**, EA đặt **Sell Limit tại resistance** với **SL/TP** xây từ biên support–resistance và **`MinRiskReward`**, lot theo **`RiskAmount`** và trần **5% equity**, kèm **giới hạn lỗ ngày** và **lọc spread**.

---

*Tài liệu phân tích mã — không phải lời khuyên đầu tư. Giao dịch có rủi ro; kiểm thử kỹ trước khi dùng thật.*
