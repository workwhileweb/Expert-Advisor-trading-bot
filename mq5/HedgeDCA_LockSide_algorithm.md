# Phân tích thuật toán HedgeDCA / Matrix Milion (Lock Side v12.00)

Tài liệu được suy luận từ: ảnh **Inputs** (1.png), **History** (2.png), **Trade** đang mở (4.png), và **log Experts** (3.txt). Tên hiển thị trên chart/log là *Matrix Milion* / *HedgeDCA Lock Side v12.00* — cùng một họ chiến lược hedge + DCA + “khóa phía”.

---

## 1. Mục tiêu chiến lược

- Duy trì **lưới hai chiều** (BUY và SELL) trên cùng một symbol, không gán SL/TP cố định từng lệnh (quản lý thoát bằng code — khớp cột S/L, T/P trống trên Trade/History).
- Dùng **DCA** (thêm lệnh theo khoảng giá) và **nhân lot** (martingale nhẹ) để gom vị thế.
- Cơ chế **“lock side”**: tại mỗi thời điểm, một phía (BUY hoặc SELL) được ưu tiên đóng khi đạt **ngưỡng lãi theo pip**; phía còn lại tiếp tục DCA hoặc được xử lý ở chu kỳ sau.
- **Giới hạn tổng lot** (Buy + Sell) và **cắt theo drawdown tài khoản** để hạn chế bùng nổ rủi ro.

---

## 2. Tham số từ cấu hình (1.png)

| Nhóm | Tham số | Giá trị mẫu | Ý nghĩa |
|------|---------|-------------|---------|
| Lệnh gốc | `InpInitLot` | 0.01 | Lot khởi đầu mỗi phía / bước 0 |
| | `InpMagic` | 20250417 | Magic nhận diện lệnh bot |
| | `InpSlippage` | 20 | Slippage (points) |
| Bước DCA | Khoảng cách mỗi bước | 100 **points** | Khoảng giá giữa các mức DCA (trên XAU thường quy ước point/pip khác nhau theo broker) |
| | Số bước DCA tối đa mỗi phía | 8 | Tối đa số lệnh DCA **thêm** (hoặc tổng bước) mỗi chiều |
| Hệ số nhân lot | STOP (DCA dương) | 1.09 | Hệ số nhân cho nhánh kiểu *stop* (thườn gắn với DCA theo chiều “đẩy” giá) |
| | LIMIT (DCA âm) | 1.09 | Hệ số nhân cho nhánh *limit* (thườn gắn với DCA ngược chiều / trung bình giá) |
| Chốt lời | Pip lãi chốt **bên bị lock** | 50 | Khi phía đang lock đạt đủ lãi (quy đổi pip trên basket phía đó), đóng toàn bộ lệnh **cùng phía đó** |
| Bảo vệ | `InpMaxDD_USD` | 200 | Nếu **lỗ nổi tổng** (hoặc drawdown) vượt ngưỡng → đóng hết / dừng chu kỳ |
| | `InpAutoRestart` | true | Sau khi chu kỳ “trống vị thế”, tự mở lại lệnh gốc |
| Giới hạn lot | Tổng lot tối đa (Buy+Sell) | 1.0 | Không mở thêm nếu tổng khối lượng đạt trần |

**Ghi chú:** Log (3.txt) in `MultiStop=1.09 MultiLimit=1.09`, `MaxTotalLot=1.0` — khớp bảng trên.

---

## 3. Hành vi từ log (3.txt)

1. Khởi động: `=== HedgeDCA Lock Side v12.00 | XAUUSDm | pt=0.001 ===` — `pt` thường là bước nhỏ nhất của giá trên symbol (point).
2. `Initial orders OK` — bot đặt **lệnh gốc** (thường là cặp hedge ban đầu hoặc lưới pending tương đương).
3. `[LotCalc] step=k, mult=1.09, raw=..., norm=..., stepLot=0.01` — lot bước `k` tính theo công thức nhân (`raw ≈ init * mult^k`), sau đó **chuẩn hóa** theo bước lot tối thiểu của broker (`norm`, `stepLot`). Với mult 1.09 và bước 0.01, bước 1 có `raw=0.0109` nhưng vẫn **norm=0.01** nếu volume step = 0.01.
4. **Không lock**, phía BUY đạt TP: `[TP] No lock, BUY đạt TP: pips=...` → `SyncGrid: Up=0 Dn=3` → `Chuyển lock sang SELL`.  
   - Diễn giải: sau khi **đóng hết BUY** (hoặc basket BUY đạt mục tiêu), còn **3 lệnh SELL** → trạng thái lock chuyển sang **SELL** (phía còn lại cần quản lý/chốt theo luật lock).
5. `Locked SELL đạt TP` → đóng SELL → `Up=1 Dn=0` → `Chuyển lock sang BUY, tiếp tục DCA` — còn 1 BUY, lock sang BUY, cho phép **tiếp tục DCA** phía BUY.
6. Lặp lock BUY / lock SELL theo pip mục tiêu.
7. `Reset cycle, ready to open initial orders` → chu kỳ kết thúc (thường là **không còn vị thế** hoặc điều kiện reset), sau đó lại `Initial orders OK`.

**Kết luận luồng lock:**

- `LOCK_NONE`: có thể đóng **một phía thắng** (ở đây log gọi là BUY đạt TP) theo tiêu chí riêng (pip tổng hoặc điều kiện basket) — không bắt buộc trùng số 50 pip của lock.
- `LOCK_BUY` / `LOCK_SELL`: chỉ đóng **toàn bộ lệnh cùng phía lock** khi **lãi basket phía đó** (theo pip) ≥ `InpLockSideTPPips` (50 trong config).

`SyncGrid: Up=x Dn=y` được hiểu là đồng bộ đếm lưới hai phía (ví dụ **Up = số/chiều BUY**, **Dn = SELL** hoặc ngược lại — quan trọng là **còn bao nhiêu lệnh mỗi phía** sau sự kiện TP).

---

## 4. Quan sát từ Trade mở (4.png)

- Nhiều lệnh **buy** và **sell** cùng lúc, khối lượng chủ yếu **0.01**, sau đó tăng **0.02** — phù hợp **nhân lot theo bước** (martingale theo cấp DCA).
- Không có SL/TP broker — thoát theo basket / lock.

---

## 5. Quan sát từ History (2.png)

- Chuỗi nhiều lệnh nhỏ đóng **cùng giây** — đóng **theo nhóm** (basket), không phải từng ticket tách rời.
- Có giai đoạn lot lớn hơn (mô tả 0.31) — có thể là phiên bản/cấu hình khác hoặc cơ chế “recovery”; **EA mẫu** dưới đây chỉ triển khai **init + DCA + nhân lot + lock** như log và tab Inputs, không bắt chước thêm nhánh 0.31 nếu không có trong cùng bộ tham số.

---

## 6. Thuật toán tổng hợp (pseudo-code)

```
Khởi tạo state: lock = NONE, cycle hoạt động

Hàm PipSize():
  // broker XAU: thường 1 pip = 10 * Point hoặc tương đương — nên cho input PointsPerPip

Hàm BasketPipsBuy():
  // Giá đóng tham chiếu = Bid
  // Weighted AvgOpenBuy = sum(lot_i * open_i) / sum(lot_i)
  // pips = (Bid - AvgOpenBuy) / PipSize()   // >0 khi buy đang lãi theo giá

Hàm BasketPipsSell():
  // pips = (AvgOpenSell - Ask) / PipSize()

Mỗi tick / OnTimer:
  Nếu MaxDD_USD vi phạm → đóng tất cả lệnh magic, tắt chu kỳ (hoặc chờ AutoRestart theo policy)

  Nếu không có vị thế nào (Buy+Sell=0) và AutoRestart:
     Mở Initial: Buy(initLot) + Sell(initLot) tại thị trường
     lock = NONE
     Ghi log Initial orders OK

  // DCA (ví dụ bám giá trung bình có trọng số — đơn giản hóa: bám “cực” giá)
  Nếu tổng lot < MaxTotalLot và số bước buy < MaxSteps:
     Nếu Bid <= (LowestBuyOpen - StepPoints * Point):
        lotNext = lotBuyLast * MultLimit (hoặc MultStop tùy chiều — EA dùng MultLimit cho buy thêm khi giá giảm)
        Mở Buy(lotNext)

  Tương tự phía Sell khi Ask >= HighestSellOpen + StepPoints * Point với MultStop

  // TP + Lock
  Nếu lock == NONE và có cả Buy và Sell:
     Nếu BasketPipsBuy() >= NoLockWinnerTP:
        Đóng tất cả Buy; lock = SELL
     Nếu BasketPipsSell() >= NoLockWinnerTP:
        Đóng tất cả Sell; lock = BUY

  Nếu lock == BUY:
     Nếu BasketPipsBuy() >= LockTP:
        Đóng tất cả Buy
        Nếu không còn lệnh → Reset cycle (Initial nếu AutoRestart)
        Ngược lại → lock = SELL (nếu còn sell) hoặc NONE

  Nếu lock == SELL: đối xứng

  // (Tuỳ chọn) Nếu chỉ còn một phía và lock NONE: có thể gán lock mặc định cho phía còn lại — tùy biến thể Matrix gốc
```

**Điểm cố ý đơn giản hóa trong file .mq5 kèm theo:**

- **No-lock TP** và **Lock TP** tách hai input: `InpNoLockWinnerTPPips` (mặc định 200 để linh hoạt; log có giá trị ~162 pip kiểu hiển thị) và `InpLockedSideTPPips` (50 theo config).
- **DCA**: thêm BUY khi giá giảm đủ `StepPoints` dưới **mức mở BUY thấp nhất**; thêm SELL khi giá tăng đủ trên **mức SELL cao nhất** — tách **MultLimit** (buy thêm) / **MultStop** (sell thêm) đúng tinh thần “LIMIT vs STOP” trên form.
- **Không** triển khai pending BuyStop/BuyLimit đầy đủ như một số bản Matrix (chỉ dùng **market** cho DCA) để giảm độ phức tạp và vẫn khớp quan sát “nhiều lệnh market nhỏ”.

---

## 7. Rủi ro và hạn chế bản tái hiện

- Martingale + hedge **không đảm bảo** lợi nhuận; log/history mẫu có thể thua lớn.
- Khác biệt **định nghĩa pip/point** giữa broker làm lệch số pip so với log.
- Bot gốc có thể có thêm: spread filter, giờ giao dịch, news filter, partial close, magic đa tier — **không có trong tài liệu** thì không thêm vào EA mẫu.

---

## 8. File mã nguồn

- `HedgeDCA_LockSide_core.mqh` — logic chung; biến thể qua `HDCA_VARIANT` (xem `HedgeDCA_Lop2_phong_ho_song_lon.md` §7.1).
- `HedgeDCA_LockSide.mq5` — EA BASE (không RiskGov P0–P4).
- `HedgeDCA_LockSide_p0.mq5` … `_p4.mq5`, `HedgeDCA_LockSide_p0p1.mq5`, `HedgeDCA_LockSide_p0p2.mq5`, `HedgeDCA_LockSide_p1p2.mq5`, `HedgeDCA_LockSide_p0p1p2.mq5` — EA RiskGov (`HDCA_VARIANT` 10…50, **110**, **120**, **130**, **210**).
