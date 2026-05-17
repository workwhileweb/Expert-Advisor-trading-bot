# Phân tích sâu HedgeDCA Lock Side (Matrix-style)

Tài liệu này bổ sung và đi sâu hơn so với `HedgeDCA_LockSide_algorithm.md`, đồng bộ với triển khai thực tế trong `HedgeDCA_LockSide.mq5` (EA tái hiện chiến lược hedge + DCA + khóa phía + giới hạn rủi ro).

---

## 1. Tóm tắt vận hành

EA duy trì **cùng lúc** lệnh **BUY** và/hoặc **SELL** trên một symbol, **không** đặt SL/TP cố định trên từng ticket; thoát lệnh theo **lãi basket theo pip** (giá trung bình có trọng số theo lot) và theo **trạng thái lock**.

Luồng chính mỗi tick (`OnTick`):

1. Kiểm tra **MaxDD USD** — nếu lỗ nổi (profit + swap) ≤ −ngưỡng → đóng hết, có thể dừng hẳn nếu tắt AutoRestart.
2. Nếu **không còn vị thế** → reset lock, mở lại cặp gốc BUY+SELL (nếu bật AutoRestart và không bị halt DD).
3. Nếu còn vị thế → `ProcessTpAndLock` (ưu tiên chốt theo lock / no-lock / single-side) rồi mới `TryDcaBuy` / `TryDcaSell`.

Thứ tự này quan trọng: **chốt basket được xử lý trước DCA** trong cùng tick, tránh mở thêm lệnh khi điều kiện thoát đã thỏa.

---

## 2. Mô hình trạng thái (lock)

| Trạng thái | Ý nghĩa |
|-------------|---------|
| `LOCK_NONE` | Hai phía có thể cùng tồn tại; nếu **cả BUY và SELL** đều > 0, phía nào đạt `InpNoLockWinnerTPPips` trước thì **đóng toàn bộ phía đó**, lock chuyển sang phía còn lại. |
| `LOCK_BUY` | Ưu tiên quản lý/chốt **BUY**: khi basket BUY đạt `InpLockedSideTPPips` → đóng hết BUY; sau đó hoặc reset chu kỳ, hoặc chuyển lock sang SELL nếu vẫn còn SELL. |
| `LOCK_SELL` | Đối xứng với BUY. |

**No-lock winner** (`InpNoLockWinnerTPPips`): thường **cao hơn** TP phía lock — ý tưởng là khi còn hedge đầy đủ, chỉ “nhặt” phía đang thắng rõ khi lãi basket đủ lớn; sau đó phía còn lại được xử lý theo luật lock với ngưỡng nhỏ hơn (`InpLockedSideTPPips`).

**Một phía còn sót** (`nb>0, ns==0` hoặc ngược lại) và `LOCK_NONE`: EA dùng **`InpLockedSideTPPips`** để thoát basket đơn — tránh kẹt một chiều vô hạn.

---

## 3. DCA và công thức lot

### 3.1. Điều kiện thêm lệnh

- **BUY thêm**: số lệnh BUY `n` thỏa `1 ≤ n < 1 + InpMaxDcaAdds`, và **Bid** ≤ (giá mở BUY **thấp nhất** − `InpDcaStepPoints * _Point`).
- **SELL thêm**: tương tự, **Ask** ≥ (giá mở SELL **cao nhất** + bước).

Nghĩa là DCA **theo cực trị giá mở** (lowest buy / highest sell), không theo giá trung bình — điển hình của lưới “đuổi giá” một chiều trên mỗi phía.

### 3.2. Martingale theo bước

- BUY bước `addIndex` (ở code = `n` = số lệnh BUY hiện có khi chuẩn bị mở thêm):  
  `raw = InpInitLot * InpMultLimit^addIndex`
- SELL: `raw = InpInitLot * InpMultStop^addIndex`

Sau đó `NormLot` làm tròn **xuống** theo `SYMBOL_VOLUME_STEP`, kẹp min/max broker.

**Hệ quả**: với `InpInitLot = 0.01`, `mult = 1.09`, bước lot 0.01, nhiều bước đầu vẫn ra **0.01** vì `raw` chưa vượt đủ để nhảy bước — martingale **thực tế chỉ “bật” rõ** ở các bậc cao hơn. Người dùng cần hiểu điều này khi backtest.

### 3.3. Trần tổng lot

`TotalLotsOur() + lot mới > InpMaxTotalLot` → không mở thêm DCA phía đó. Đây là phanh cứng trước khi khối lượng bùng nổ.

---

## 4. Pip basket (toán học)

- **Giá mở trung bình có trọng số** phía BUY:  
  `avg_B = Σ(open_i * lot_i) / Σ(lot_i)`  
  **Pip BUY** ≈ `(Bid - avg_B) / (InpPointsPerPip * _Point)`  
- **Pip SELL** ≈ `(avg_S - Ask) / (InpPointsPerPip * _Point)`

**Lưu ý**: công thức dùng Bid/Ask tách biệt — đúng hướng cho P/L thực tế nhưng **không trừ spread tích lũy** ra một “mục tiêu pip hiển thị”; spread và commission vẫn ảnh hưởng **USD** qua `POSITION_PROFIT`.

`InpPointsPerPip` (mặc định 10 cho XAU kiểu 2 số lẻ) **bắt buộc** khớp quy ước broker/symbol; sai → mọi ngưỡng pip sai tỉ lệ.

---

## 5. Ưu điểm

| Ưu điểm | Giải thích ngắn |
|---------|------------------|
| Hedge tự nhiên | Có cả BUY và SELL giúp **giảm độ nhạy** với biến động hai chiều trong vùng giá so với chỉ một chiều martingale thuần. |
| Thoát theo basket | Tránh phụ thuộc SL từng lệnh; có thể “gom” nhiều ticket một lần khi điều kiện pip thỏa. |
| Phân tầng TP | No-lock TP lớn + lock TP nhỏ tạo **lộ trình**: ưu tiên chốt phía thắng mạnh khi full hedge, sau đó xử lý phía còn lại gọn hơn. |
| Giới hạn lot | `InpMaxTotalLot` cắt ngang đà tăng khối lượng. |
| Cắt lỗ tài khoản | `InpMaxDD_USD` đặt **ngưỡng thực dụng** theo tiền, không chỉ theo pip. |
| AutoRestart | Sau khi flat, có thể **tự tái nhập** chu kỳ mới — phù hợp bot chạy liên tục. |
| Single-side escape | Nhánh một phía dùng lock TP để **không bị kẹt** khi đã đóng hết phía đối diện. |

---

## 6. Nhược điểm và rủi ro

| Nhược điểm / rủi ro | Chi tiết |
|---------------------|----------|
| Xu hướng mạnh | Một chiều trend dài làm một phía **DCA liên tục**, phía kia chốt lặp; tổng P/L vẫn có thể **âm sâu** trước khi chạm MaxDD. |
| Martingale | Dù có trần lot, **tỷ lệ rủi ro / lần thắng** không được đảm bảo toán học; backtest quá khứ không chứng minh tương lai. |
| Spread & trượt giá | Pip basket không “đội” spread; giá thực vào/ra làm **lệch** so với pip lý thuyết, đặc biệt XAU giờ tin. |
| Định nghĩa pip | `InpPointsPerPip` sai → TP sớm/muộn, hành vi khó debug. |
| Một tick nhiều lệnh đóng | `CloseSide` lặp ticket — broker có thể **từ chối một phần**; EA không có retry phức tạp (tùy môi trường). |
| MaxDD theo floating | Dùng profit nổi + swap; **không** phân biệt equity spike hay commission riêng; có thể cần tinh chỉnh theo tài khoản raw vs net. |
| `g_ddHalt` | Khi MaxDD hit và `InpAutoRestart = false` → `g_ddHalt` chặn mở lại; cần reload EA hoặn đảo cờ logic nếu muốn chạy tiếp sau can thiệp tay. |
| Không lọc phiên / tin | Dễ vào lệnh trong điều kiện spread giãn, biến động bất thường. |

---

## 7. Thông số (input), ý nghĩa và gợi ý giá trị

> Gợi ý mang tính **tham khảo**; luôn tối ưu trên **symbol, khung thời gian, spread và vốn** của bạn.

### 7.1. Nhóm lệnh gốc

| Input | Ý nghĩa | Gợi ý |
|-------|---------|--------|
| `InpInitLot` | Lot khởi đầu mỗi phía; cơ sở cho lũy thừa martingale. | Bắt đầu nhỏ so với vốn (ví dụ 0.01 trên vài nghìn USD với XAU tùy rủi ro). Tăng init lot đồng nghĩa tăng mọi bậc sau. |
| `InpMagic` | Lọc vị thế của EA. | Một magic cố định / theo chiến dịch; tránh trùng EA khác cùng symbol. |
| `InpSlippage` | Độ lệch chấp nhận (points). | XAU volatile: 20–80 tùy broker; quá thấp dễ requote, quá cao giá xấu. |

### 7.2. Bước DCA

| Input | Ý nghĩa | Gợi ý |
|-------|---------|--------|
| `InpDcaStepPoints` | Khoảng giá (points) từ cực trị mở đến khi thêm lệnh. | Nhỏ → lưới dày, vào DCA nhanh, rủi ro tăng. Lớn → ít lệnh hơn nhưng mỗi lệnh “xa” hơn. XAU: thử 80–300 points tùy chiến lược và spread. |
| `InpMaxDcaAdds` | Số lệnh DCA **tối đa thêm** mỗi phía (tổng tối đa = 1 + giá trị này). | 5–12 phổ biến; tăng số bước = tăng khả năng gánh trend nhưng tăng exposure. |

### 7.3. Hệ số nhân lot

| Input | Ý nghĩa | Gợi ý |
|-------|---------|--------|
| `InpMultLimit` | Hệ số nhánh BUY (DCA khi giá giảm). | 1.0–1.15: càng gần 1 càng “êm” nhưng recovery chậm; >1.15 thường rất gắt với XAU. |
| `InpMultStop` | Hệ số nhánh SELL (DCA khi giá tăng). | Có thể **asymmetric** với MultLimit nếu bạn tin tính không đối xứng của symbol (cẩn trọng). |

### 7.4. Chốt lời pip

| Input | Ý nghĩa | Gợi ý |
|-------|---------|--------|
| `InpLockedSideTPPips` | TP basket cho phía **đang lock** và cho **trường hợp một phía**. | 30–100 pip “kiểu hiển thị” tùy `PointsPerPip`; cần khớp backtest. Quá nhỏ → nhiều vòng, phí/spread ăn mòn. |
| `InpNoLockWinnerTPPips` | Khi còn cả hai phía, đóng phía thắng nếu đạt pip này. | Thường **> Lock TP** (ví dụ 150–400); log mẫu ~162 pip — chỉnh để khớp hành vi mong muốn. |
| `InpPointsPerPip` | Quy đổi point → pip. | XAU 2 số lẻ thường 10; symbol 5 digit forex JPY có thể khác. **Kiểm tra trên từng broker.** |

### 7.5. Bảo vệ và lot tổng

| Input | Ý nghĩa | Gợi ý |
|-------|---------|--------|
| `InpMaxDD_USD` | Đóng hết khi lỗ nổi ≤ −ngưỡng. | Đặt theo % vốn tâm lý (ví dụ 2–5% vốn); 0 = tắt (không khuyến nghị). |
| `InpAutoRestart` | Sau flat có mở lại cặp gốc không; sau MaxDD có cho phép EA “sống” tiếp không (kết hợp `g_ddHalt`). | Demo: true để quan sát; live: cân nhắc false sau khi hit DD để kiểm soát tay. |
| `InpMaxTotalLot` | Trần tổng lot Buy+Sell. | Thiết kế sao cho worst-case loss × point value vẫn trong giới hạn; ví dụ 0.5–2.0 lot trên tài khoản nhỏ tùy rủi ro. |

### 7.6. Khác

| Input | Ý nghĩa |
|-------|---------|
| `InpVerboseLog` | Log LotCalc, TP, lock — hữu ích debug, tắt khi cần giảm I/O. |

---

## 8. Các hướng cải thiện đề xuất

Ưu tiên theo mức độ tác động đến **an toàn vận hành** và **sát thực tế broker**:

1. **Spread / commission trong mục tiêu**  
   Điều chỉnh ngưỡng pip hoặc thêm “buffer pip” = f(spread trung bình) để tránh chốt ảo trên giấy nhưng thua trên tiền.

2. **Adaptive DCA step**  
   Bước DCA theo ATR hoặc độ rộng Bollinger để giảm mật độ lệnh khi thị trường “dãn” và tăng khi sideway nhỏ.

3. **OnTimer + cờ tick**  
   Giảm tải khi có hàng trăm symbol hoặc VPS yếu; logic quản lý basket không cần thiết mỗi tick.

4. **Retry đóng lệnh**  
   Khi `PositionClose` thất bại (Requote, trade context busy), backoff và thử lại có giới hạn.

5. **Bộ lọc thời gian / tin tức**  
   Ngừng mở DCA mới trước/sau sự kiện lịch; tránh spread phình.

6. **DD theo % equity**  
   Song song hoặc thay cho DD USD để tự scale theo tài khoản tăng/giảm.

7. **Partial close / scale-out**  
   Giảm lot phía thua từng phần khi phía thắng đủ lớn — phức tạp hơn nhưng linh hoạt hơn “đóng hết một phía”.

8. **Kiểm thử**  
   Strategy Tester với **real ticks**, nhiều giai đoạn thị trường (trend / range / shock), và so sánh khi đổi `InpPointsPerPip`.

9. **Tài liệu hành vi MaxDD + AutoRestart**  
   Làm rõ trong UI/log khi nào EA dừng vĩnh viễn cần can thiệp người — tránh hiểu nhầm “bot tự chết”.

---

## 9. Kết luận

HedgeDCA Lock Side là chiến lược **lưới hai phía + martingale có trần + thoát theo basket + máy trạng thái lock**. Điểm mạnh nằm ở **cấu trúc thoát có kiểm soát** và **phanh rủi ro** (max lot, max DD). Điểm yếu cố hữu là **nhạy với trend mạnh và chi phí giao dịch**; tham số pip và point phải **khớp broker**, và martingale cần được hiểu kèm **làm tròn lot** thực tế.

---

## 10. Tham chiếu mã nguồn

- Thuật toán tóm tắt: `HedgeDCA_LockSide_algorithm.md`  
- Triển khai: `HedgeDCA_LockSide.mq5`
