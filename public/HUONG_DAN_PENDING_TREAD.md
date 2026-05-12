# Hướng dẫn sử dụng EA Pending_tread

Expert Advisor **Pending_tread** duy trì lưới lệnh **chờ** (Buy Stop / Buy Limit / Sell Stop / Sell Limit) quanh giá thị trường, phù hợp giao dịch ngắn hạn (ví dụ XAUUSD). Tài liệu này mô tả cách cài đặt, tham số và cách đọc báo cáo định kỳ trên tab **Experts** của MetaTrader 5.

---

## 1. Cài đặt nhanh

1. Sao chép `Pending_tread.mq5` vào thư mục `MQL5\Experts\` của terminal MT5.
2. Mở MetaEditor, biên dịch (Compile) để tạo `Pending_tread.ex5`.
3. Kéo EA lên biểu đồ **đúng symbol** bạn muốn giao dịch (EA dùng `_Symbol` hiện tại).
4. Bật **Algo Trading** trên terminal.
5. Trong tab **Common** của EA: tick **Allow Algo Trading** (và nếu cần: **Allow DLL imports** chỉ khi bạn tự thêm DLL — bản mặc định không cần).

---

## 2. Tham số đầu vào (Inputs)

### Cài đặt chung (lưới & rủi ro)

| Tham số | Ý nghĩa |
|--------|---------|
| **PipStep** | Khoảng cách giữa các mức giá lệnh chờ (theo “pip” nội bộ EA: có nhân hệ số với 3/5 chữ số thập phân). |
| **TakeProfitPips** | Chốt lời tính theo pip (cùng quy ước với PipStep). |
| **StopLossPips** | Cắt lỗ theo pip (chỉ gửi lệnh nếu **EnableStopLoss** = true). |
| **LotSize** | Khối lượng mỗi lệnh chờ (được chuẩn hóa theo bước lot của broker). |
| **Slippage** | Độ lệch giá tối đa chấp nhận khi đóng vị thế / xóa lệnh. |
| **EnableBuyGrid** | Bật lưới phía **trên** thị trường (theo **AboveMarketTradeType**). |
| **AboveMarketTradeType** | Chuỗi `BUY` hoặc `SELL`: loại lệnh chờ phía trên giá (Buy Stop vs Sell Limit). |
| **EnableSellGrid** | Bật lưới phía **dưới** thị trường (theo **BelowMarketTradeType**). |
| **BelowMarketTradeType** | `BUY` hoặc `SELL`: loại lệnh chờ phía dưới giá (Buy Limit vs Sell Stop). |
| **EnableStopLoss** | Có gắn SL khi đặt lệnh chờ hay không. |
| **MinimumEquity** | Nếu **equity** tài khoản thấp hơn giá trị này, EA **không** duy trì lưới (bảo vệ tài khoản nhỏ). |
| **EnableEquityLossProtection** | Bật giới hạn lỗ theo % so với số dư **lúc EA khởi động**. |
| **MaxLossPercent** | Ngưỡng %: nếu equity ≤ số dư khởi tạo × (1 − MaxLossPercent/100) thì đóng hết vị thế và xóa lệnh chờ của EA. |
| **MagicNumber** | Mã nhận diện lệnh của EA (lọc khi đếm và xóa lệnh chờ). |

### Báo cáo định kỳ

| Tham số | Ý nghĩa |
|--------|---------|
| **EnablePeriodicStatus** | Bật in báo cáo định kỳ ra log (tab Experts). |
| **StatusIntervalSeconds** | Khoảng cách giữa hai báo cáo (giây). **Tối thiểu 10** nếu bật báo cáo. |
| **InpLanguage** | Tiếng Việt hoặc English cho nội dung báo cáo. |

---

## 3. Cách EA hoạt động (tóm tắt hành vi)

- Mỗi vài giây (tối thiểu **5 giây** giữa hai lần xử lý lưới), EA kiểm tra số lệnh chờ đúng symbol + magic + loại lệnh; nếu thiếu so với **10 lệnh mỗi phía** (hằng `totalOrdersPerSide` trong code), EA sẽ cố gắng **bổ sung** lệnh chờ theo bước **PipStep**.
- Giá đặt lệnh phải thỏa **SYMBOL_TRADE_STOPS_LEVEL** (khoảng cách tối thiểu tới giá thị trường); nếu không đủ, một số mức có thể bị bỏ qua (`continue`).
- Khi bảo vệ lỗ vốn kích hoạt, EA đóng **mọi** vị thế (theo symbol khi gọi `PositionClose`) và xóa lệnh chờ có đúng **MagicNumber**.

Chi tiết thuật toán xem file **THUAT_TOAN_PENDING_TREAD_CHI_TIET.md**.

---

## 4. Báo cáo định kỳ: % “sẵn sàng duy trì lưới”

Mỗi **StatusIntervalSeconds**, EA in một khối log gồm:

- **Sẵn sàng duy trì lưới: X% (a/7)** — tỷ lệ **7 điều kiện** sau đang thỏa:
  1. Equity ≥ **MinimumEquity**
  2. **Bảo vệ lỗ vốn**: tắt bảo vệ **hoặc** chưa vượt ngưỡng **MaxLossPercent**
  3. **Không bận trade** (context không báo mã bận 10006/10010/10011)
  4. **Chỗ lệnh Buy**: tắt Buy grid **hoặc** số lệnh chờ phía Buy &lt; 10
  5. **Chỗ lệnh Sell**: tắt Sell grid **hoặc** số lệnh chờ phía Sell &lt; 10
  6. **Chờ tick lưới**: đã qua ≥ 5 giây kể từ lần cập nhật lưới gần nhất (hoặc EA vừa khởi động)
  7. **Symbol cho phép giao dịch** (không ở chế độ disabled)

Dòng tiếp theo liệt kê **Đạt** / **Chưa** (hoặc **OK** / **No** nếu chọn English) cho từng mục, kèm số lệnh chờ Buy-side / Sell-side và equity.

> **Lưu ý:** % này phản ánh điều kiện **môi trường + chỗ trống lưới**, không phải dự báo lợi nhuận. Kể cả 100% vẫn có thể từ chối lệnh do quy tắc broker, freeze level, hoặc margin.

---

## 5. Khuyến nghị & rủi ro

- **Grid + pending** có thể mở nhiều vị thế liên tiếp khi giá chạy qua các mức — cần vốn và **MaxLossPercent** / **MinimumEquity** phù hợp.
- Kiểm tra **contract size** và **pip** của symbol (vàng, FX, chỉ số) trước khi áp PipStep/TP/SL cố định.
- Luôn chạy **Strategy Tester** và tài khoản demo trước khi dùng thật.
- Phần mô tả gốc của EA có cảnh báo: dùng trên **rủi ro của bạn**; tác giả script không chịu trách nhiệm thiệt hại.

---

## 6. Xử lý sự cố thường gặp

| Hiện tượng | Gợi ý |
|------------|--------|
| Không có lệnh chờ mới | Xem log: equity thấp, trade busy, hoặc stops level chặn giá. |
| Báo cáo luôn thấp % | Kiểm tra MinimumEquity, bảo vệ lỗ, hoặc đã đủ 10/10 lệnh mỗi phía. |
| EA đóng hết lệnh đột ngột | Có thể **EnableEquityLossProtection** đã chạm ngưỡng — kiểm tra equity so với số dư lúc bật EA. |
| Lỗi compile | Chỉ cần `#include <Trade\Trade.mqh>` và build trên MT5 build hiện hành. |

---

*Tài liệu đi kèm mã nguồn trong repo Expert-Advisor-trading-bot.*
