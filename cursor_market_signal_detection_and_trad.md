# Market signal detection and trading strategy
_Exported on 5/24/2026 at 04:08:38 GMT+7 from Cursor (3.5.33)_

---

**User**

@Hybrid_LSTM_TA_Signal.mqh tạo 1 file code mq5 mới, bổ sung thêm phát hiện tín hiệu thị trường (đo theo giây) sideway để cho phép đánh hay không, sử dụng tín hiệu từ file đính kèm để vào lệnh trade tương ứng, giá trị vào lệnh đầu input =0.01 lot mặc định, nếu lệnh đó có lời thì chờ chốt lời (= input = 10% giá trị vào lệnh), nếu lỗ thì đánh tiếp 1 lệnh cùng chiều giá trị vào lệnh tính theo lệnh đầu (=input = 1.1 lệnh đầu), theo dõi lệnh đánh thứ 2 nếu vẫn lỗ thì đánh tiếp lệnh thứ 2 cùng chiều = 1,1*lệnh 2, nếu vẫn lỗ thì đánh 1 lệnh quay đầu = input = 5*lệnh đầu, có input chế độ chốt lời và cắt lỗ cho mọi lệnh và cho toàn bộ tài khoản (=0 là không cắt), mọi tham số phải ghi chú rõ ràng dễ hiểu, mọi lệnh và log phải giải thích rõ ràng vì sao và kết quả là lời lỗ trong các lệnh chốt lời cắt lỗ, cần có multi lines ui panel rõ ràng

---

**Cursor**

Đang đọc file tín hiệu và EA tham chiếu để tạo EA MQ5 mới với phát hiện sideway và logic martingale như yêu cầu.


Đang tạo EA mới với phát hiện sideway theo giây, chuỗi martingale theo yêu cầu và panel đa dòng.


Đã tạo EA mới **`mq5/Hybrid_LSTM_TA_SidewayMartTrade.mq5`** — biên dịch **0 lỗi**.

## Chức năng chính

### 1. Tín hiệu vào lệnh
- Dùng `Hybrid_LSTM_TA_Signal.mqh` → `HybridSignal_FetchForecast` (LONG / SHORT / NEUTRAL).
- Chỉ mở **lệnh mồi** khi có hướng ≠ 0.

### 2. Lọc sideway (theo giây)
- Mỗi `InpSidewaySampleSec` (mặc định 1s) lấy mẫu **BID**.
- Trong `InpSidewayWindowSec` (mặc định 60s): nếu biên độ ≤ `InpSidewayMaxRangePips` (8 pip) → **SIDEWAY** → **không mở basket mới** (`InpBlockEntryWhenSideway`).
- Basket đang mở vẫn được quản lý bình thường.

### 3. Chuỗi lot (đúng mô tả của bạn)
| Bước | Điều kiện | Hành động |
|------|----------|-----------|
| Mồi | Tín hiệu + không sideway | `InpFirstLot` = **0.01** |
| Leg cuối **lãi** | — | Chờ chốt basket (không nhồi) |
| Mồi **lỗ** | Leg cuối lỗ | Nhồi #2 cùng chiều = lot trước × **1.1** |
| #2 **lỗ** | Leg cuối lỗ | Nhồi #3 = lot #2 × **1.1** |
| #3 **lỗ** | Leg cuối lỗ | **Quay đầu** ngược chiều = lot mồi × **5** |

### 4. Chốt lời / cắt lỗ
- **Basket:** `InpBasketTakeProfitPct` = **10%** giá trị lệnh mồi (`|lot×contract×giá mở|`); `InpBasketStopLossPct` = **0** → tắt.
- **Tài khoản:** `InpAccountTakeProfitPct` / `InpAccountStopLossPct` = **0** → tắt; so với **balance lúc mở basket**.

### 5. Log & panel
- Mỗi lệnh mở / đóng có **lý do** + **LÃI/LỖ** trong Experts.
- Panel **đa dòng** (`OBJ_EDIT`): sideway, dự báo, P+L ròng, TP/SL còn lại, leg cuối.

## Input quan trọng (đã ghi chú trong code)

```mq5
InpFirstLot = 0.01
InpMartingaleMult = 1.1
InpReversalMult = 5.0
InpBasketTakeProfitPct = 10.0
InpBasketStopLossPct = 0.0        // 0 = không cắt basket
InpAccountTakeProfitPct = 0.0     // 0 = không chốt theo TK
InpAccountStopLossPct = 0.0
InpSidewayWindowSec = 60
InpSidewayMaxRangePips = 8.0
```

## Cách dùng
1. Copy `Hybrid_LSTM_TA_SidewayMartTrade.mq5` + `Hybrid_LSTM_TA_Signal.mqh` vào `MQL5\Experts` (hoặc compile từ repo — `.ex5` vào data folder MT5).
2. Gắn EA lên chart, bật **InpShowPanel = true** nếu muốn xem trên chart thay vì chỉ log.
3. Tham số Hybrid (LSTM, ONNX, ngôn ngữ log…) nằm ở nhóm input từ file `.mqh`.

Log compile: `mq5/Hybrid_LSTM_TA_SidewayMartTrade_compile.log`.

---

**User**

ui panel chỉ hiện thị 1 line

---

**Cursor**

Đang kiểm tra cách panel được tạo và so sánh với EA khác đã hiển thị đa dòng thành công.


`OBJ_EDIT` trên nhiều bản MT5 vẫn chỉ hiển thị một dòng. Chuyển sang nhiều `OBJ_LABEL` xếp chồng — cách ổn định nhất.


Đã sửa. Trên nhiều bản MT5, **`OBJ_EDIT` và `OBJ_LABEL` một khối** vẫn chỉ vẽ **một dòng** dù có `\n`.

**Cách mới:** mỗi dòng text = một **`OBJ_LABEL` riêng** (`HSSW_PL_0`, `HSSW_PL_1`, …) xếp dọc theo `InpPanelFontSize`. Nền `OBJ_RECTANGLE_LABEL` tự giãn cao theo số dòng.

**Việc cần làm:** compile lại `Hybrid_LSTM_TA_SidewayMartTrade.mq5` (F7) và gắn lại EA lên chart — object cũ `HSSW_PANEL_TX` sẽ bị xóa khi EA chạy.

Bạn sẽ thấy đủ các dòng: sideway, dự báo, basket, P+L, TP/SL, v.v. Nếu `Hybrid_LSTM_TA_SignalTrade` cũng bị 1 dòng, báo để áp dụng cùng cách đó.

---

**User**

tăng khoảng cách giữa các lines trong panel ui, đổi màu các line khác nhau cho dễ nhìn, đổi background black opacity 50%

---

**Cursor**

Đang cập nhật panel: tăng khoảng cách dòng, màu theo loại nội dung, nền đen 50% opacity.


Đã cập nhật panel trong `Hybrid_LSTM_TA_SidewayMartTrade.mq5` (compile 0 lỗi).

### Thay đổi

1. **Khoảng cách dòng** — `InpPanelLineGap` (mặc định **12** pixel, cộng vào cỡ chữ). Tăng lên 16–18 nếu muốn thoáng hơn.

2. **Màu từng dòng** (theo nội dung):
   - Tiêu đề: vàng gold  
   - Symbol/TF: xanh nhạt  
   - Sideway / xu hướng: cam / xanh lá  
   - LONG / SHORT / NEUTRAL: xanh / đỏ / vàng  
   - Basket, P+L lãi/lỗ, TP, SL: màu riêng  
   - Dòng khác: xen kẽ 4 tông nhạt  

3. **Nền đen 50%** — `ColorToARGB(clrBlack, 128)` qua `InpPanelBgOpacity` (mặc định **50**; 0 = trong suốt, 100 = đen đặc).

Gắn lại EA hoặc F7 compile rồi refresh chart để thấy nền mờ và màu dòng mới.

---

**User**

các log thông báo và ui text cần quy đổi các giá trị % hoặc tham số nhân thành giá trị thông báo rõ ràng

---

**Cursor**

Đang rà soát toàn bộ log và text panel để quy đổi %/hệ số thành giá trị cụ thể (lot, $, pip…).


Thêm hàm format giá trị cụ thể và cập nhật toàn bộ log + panel.


Đã cập nhật log và panel: mọi **%** và **hệ số nhân** đều kèm **giá trị quy đổi cụ thể**.

### Quy ước hiển thị
- **Tiền:** `10.50 USD` (FmtMoney)
- **% + tiền:** `10% (= 125.40 USD)` (FmtPctAndMoney)
- **Lot nhân:** `0.01 lot × 1.1 → 0.01 lot (chuẩn hóa)`
- **Sideway:** pip **và** biên quy ra **giá** (vd. `3.2 pip (0.32 giá) · ngưỡng ≤ 8.0 pip (0.80 giá)`)

### Panel (luôn thấy khi chờ lệnh)
- Kế hoạch lot: mồi `0.01` | nhồi `0.01`, `0.01` | quay đầu `0.05`
- Chốt lời basket: mốc `X USD` `(10% (= X USD), ref mồi Y USD)`
- Cắt lỗ / TK (nếu bật): ngưỡng **bằng số tiền**, kèm %

### Khi có basket
- Giá trị mồi (ref), mốc TP/SL đầy đủ
- `→ cần thêm 4.20 USD để chạm TP mốc 12.50 USD`

### Log Experts
- Mở mồi: lot + **giá trị ref** + mốc TP/SL khóa (tiền + %)
- Nhồi / quay đầu: `0.01 × 1.1 → 0.01 lot` thay vì chỉ “× 1.1”
- Đóng basket / TK: so sánh P+L với **mốc $** rõ ràng

Compile: **0 lỗi**. Gắn lại EA để thấy text mới trên chart và tab Experts.

---

**User**

bổ sung thêm tham số : số pip (mặc định = 20) lỗ để đánh lệnh nhồi tiếp theo hoặc đánh lệnh quay đầu

---

**Cursor**

Đã bổ sung tham số **`InpMartingaleAdversePips`** (mặc định **20**).

### Cách hoạt động
Để **nhồi #2 / #3** hoặc **quay đầu**, cần **đủ cả hai**:
1. Leg cuối đang theo dõi có **P+L < 0**
2. Giá đi **ngược** so với giá vào leg đó ≥ **20 pip** (BUY: giá giảm; SELL: giá tăng)

Mốc pip tính từ **giá mở leg cùng chiều mới nhất** (leg đang lỗ).

### Input mới
```mq5
InpMartingaleAdversePips = 20.0  // 0 = chỉ cần leg âm P+L, không lọc pip
```

### Panel & log
- Dòng: `Điều kiện nhồi/quay đầu: leg lỗ + giá ngược ≥ 20.0 pip so giá vào leg đó`
- Khi có basket: `pip bất lợi 12.3 / cần 20.0`
- Khi mở nhồi/quay đầu: log kèm `pip bất lợi 21.2 / cần 20.0 · giá vào leg 2650.50`

Compile: **0 lỗi**. Gắn lại EA để áp dụng.

