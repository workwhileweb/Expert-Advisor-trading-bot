# Báo cáo phân tích tĩnh: `Quantum Queen MT5.ex5`

**Ngày phân tích:** 2026-05-11  
**Kích thước file:** 356 202 byte (~348 KiB)  
**Phương pháp:** quét header nhị phân, trích chuỗi (ASCII/UTF‑16 LE), tìm kiếm mẫu byte, **không** giải mã bytecode MQL5 (không có công cụ decompile chính thức trong phạm vi phân tích này).

---

## 1. File này là file gì?

Đây là **file bytecode đã biên dịch của nền tảng MetaTrader 5 (MT5)**, phần mở rộng **`.ex5`**.

- Theo quy ước MetaQuotes, `.ex5` thường là một trong các loại: **Expert Advisor (EA)**, **indicator**, hoặc **script** đã build từ nguồn MQL5 (`.mq5`/`.mqh`).
- **Tên file** `Quantum Queen MT5.ex5` gợi ý đây là sản phẩm mang tên *Quantum Queen* cho MT5; **tên này không xuất hiện dạng chữ rõ trong phần chuỗi đã trích** (có thể chỉ nằm ở tên file hoặc trong phần dữ liệu nén/đóng gói không dạng văn bản thuần).

**Bằng chứng nhận dạng định dạng MT5:**

- **4 byte đầu (magic):** `45 58 35 02` → ASCII **`EX5`** + byte phiên bản **`0x02`** (thường được hiểu là định dạng EX5 “generation”/phiên bản container nội bộ của terminal).
- Cấu trúc sau magic là **metadata + các khối dữ liệu nhị phân** đặc thù, **không** phải PE/ELF tiêu chuẩn.

```text
Offset 0x00: 45 58 35 02 71 00 1C 16 58 04 E0 00 ...
             ^^^^^^^^
             "EX5" + 0x02
```

---

## 2. Cấu trúc file (mức quan sát được)

Định dạng `.ex5` là **đóng, độc quyền**; không có đặc tả công khai đầy đủ từ MetaQuotes. Dựa trên dấu vết nhị phân thực tế, có thể mô tả **mô hình lớp** như sau:

| Vùng (ước lượng) | Nội dung quan sát được |
|------------------|-------------------------|
| **Header** | Magic `EX5` + `0x02`, theo sau là các trường số nguyên/offset (cụ thể chỉ có thể suy luận mức “container”, không map được từng field mà không có tài liệu nội bộ). |
| **Khối mã / bytecode** | Phần lớn file là dữ liệu không phải văn bản; không đọc được như script nguồn. |
| **Chuỗi & metadata hiển thị** | Chuỗi **UTF‑16 LE** (đặc trưng của Win32/terminal) cho văn bản giao diện / liên hệ tác giả. |
| **Tài nguyên UI** | Gần **cuối file** có bảng mô tả đường dẫn bitmap chuẩn của MT5: `res\*.bmp`. |

**Bằng chứng chuỗi UTF‑16 LE (mẫu byte `XX 00` cho ký tự Latin):**

- Tại offset khoảng **0xA8** trở đi xuất hiện chuỗi: `Click here to contact the author.`
- Tại offset khoảng **0x1A8**: `https://www.mql5.com/en/users/weredeu`
- Gần **EOF** (offset ~353 418): `res\Close.bmp`, và các đường dẫn tương tự (`Down.bmp`, `Left.bmp`, …) — đây là **tài nguyên dialog/chart UI** đi kèm nhiều EA/indicator trên MT5.

---

## 3. Chức năng chính là gì? Luồng xử lý, bằng chứng, mã giả

### 3.1. Kết luận chức năng (mức độ tin cậy)

| Mức độ | Phát biểu |
|--------|-----------|
| **Chắc chắn** | Đây là module chạy trong **MetaTrader 5** (định dạng `.ex5`), có **chuỗi liên hệ tác giả** và **URL MQL5**; có **tài nguyên giao diện** kiểu dialog (bitmap `res\...`). |
| **Rất có khả năng** | Được dùng như **Expert Advisor hoặc công cụ giao dịch tự động/bán tự động** (đúng bối cảnh tên file và phân phối qua MQL5 Community). |
| **Không thể xác minh tĩnh** | Chiến lược vào lệnh cụ thể (tín hiệu, chỉ báo, grid, martingale, v.v.), điều kiện SL/TP, quản trị vốn, **mà không có mã nguồn `.mq5` hoặc decompiler đáng tin cậy**. |

**Bằng chứng “có UI / có tác giả trên MQL5”:**

- Chuỗi: `Click here to contact the author.`
- URL: `https://www.mql5.com/en/users/weredeu`
- Đường dẫn tài nguyên: `res\Close.bmp`, `res\Down.bmp`, …

**Bằng chứng phủ định hữu hạn (trong phạm vi quét):**

- Không tìm thấy các literal ASCII/UTF‑8/UTF‑16 rõ ràng như `OrderSend`, `OnTick`, `WebRequest`, `#import`, v.v. trong file — **điều này không có nghĩa EA không gọi các API đó**; trình biên dịch MQL5 thường **không để nguyên tên hàm dạng chuỗi đọc được** trong toàn bộ bytecode.

### 3.2. Luồng hoạt động điển hình của một EA MT5 (mã giả — *khung tham chiếu*, không phải reverse chính xác file này)

```text
OnInit():
  đọc input người dùng (khối #property / input)
  tạo timer hoặc đăng ký sự kiện chart (nếu có)
  tải/tạo handle chỉ báo (nếu có)
  vẽ panel UI (nếu có) — khớp với việc tồn tại res\*.bmp

OnTick() hoặc OnTimer():
  lấy giá / series / buffer chỉ báo
  nếu điều kiện chiến lược thỏa:
      gửi lệnh qua trade API nội bộ MT5
  quản lý lệnh mở (trailing, đóng một phần, v.v.) — nếu được mã hóa

OnDeinit():
  giải phóng handle, xóa đối tượng đồ họa
```

**Ánh xạ sang bằng chứng trong file:**

- **UI/panel:** có đường dẫn `res\*.bmp` → khả năng có **dialog hoặc control tùy biến**.
- **Nguồn phân phối / tác giả:** URL MQL5 → có thể tra cứu thêm mô tả sản phẩm trên trang người dùng đó (ngoài phạm vi file nhị phân).

### 3.3. Góc nhìn bảo mật / vận hành

- **Rủi ro vận hành:** EA có quyền **gửi lệnh thật** trên tài khoản nếu người dùng cho phép “Algo Trading” và quyền tài khoản phù hợp.
- **Rủi ro tin cậy:** Không có mã nguồn thì **không kiểm chứng được** hành vi trong mọi trường hợp (lỗi logic, điều kiện race, gọi `WebRequest`, đọc/ghi file, v.v.).
- **Gợi ý kiểm soát:** chỉ chạy trên **demo / strategy tester**, giới hạn quyền, theo dõi Journal/Experts log, và ưu tiên lấy bản build từ nguồn tin cậy (MQL5 Market / tác giả xác minh).

---

## 4. Tóm tắt điều tra viên

| Hạng mục | Kết quả |
|----------|---------|
| **Loại file** | Bytecode **MetaTrader 5** (`.ex5`), magic **`EX5` + 0x02** |
| **Cấu trúc** | Header đặc thù + khối nhị phân + chuỗi UTF‑16 + mô tả tài nguyên `res\*.bmp` gần cuối file |
| **Chức năng suy diễn** | Module MT5 có **UI** và **liên kết tác giả MQL5**; khả năng cao phục vụ **giao dịch tự động** — **không** khôi phục được logic chi tiết từ phân tích tĩnh này |
| **Bằng chứng then chốt** | Magic header; chuỗi liên hệ + URL `mql5.com/.../weredeu`; đường dẫn bitmap chuẩn MT5 |

---

*Tài liệu được tạo tự động từ phân tích tĩnh workspace. Không thay thế việc đọc mô tả chính thức trên MQL5 Market hoặc kiểm thử trong Strategy Tester.*
