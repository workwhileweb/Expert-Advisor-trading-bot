# Batch file for bot directory management
_Exported on 5/11/2026 at 09:59:17 GMT+7 from Cursor (3.3.30)_

---

**User**

@README.md:76-81 tạo bat file để tìm thư mục và chép bot vào

---

**Cursor**

Tạo file batch `install-ea.bat` để tự tìm thư mục MT5 Experts và copy `bot.mq5` + `bot.ex5` vào.

Test thử file batch để chắc chắn cú pháp đúng và phát hiện đúng thư mục MT5.

Có lỗi cú pháp vì path `Program Files (x86)` có dấu ngoặc làm rối parser trong block `IF`. Sửa lại bằng cách dùng subroutine.

Test lại với input `Q` để check phát hiện folder không lỗi cú pháp.

Phát hiện đúng 1 thư mục MT5. Giờ test thử copy bằng option `A`.

Copy thành công. Cập nhật README để hướng dẫn dùng file batch mới.

Hoàn tất. Đã tạo `install-ea.bat` và test thành công.

**Tóm tắt việc đã làm:**

`install-ea.bat` (`c:\Users\workw\Downloads\Expert-Advisor-trading-bot\install-ea.bat`):
- Tự quét `%APPDATA%\MetaQuotes\Terminal\*\MQL5\Experts` (mọi terminal data folder)
- Quét thêm `C:\Program Files\MetaTrader 5`, `Program Files (x86)`, và các broker phổ biến (Exness/ICMarkets/FBS/XM)
- Hiển thị danh sách đánh số, cho chọn:
  - `A` = chép vào tất cả
  - `1..N` = chép vào folder cụ thể
  - `Q` = thoát
- Chép cả `bot.mq5` và `bot.ex5` (nếu có), thông báo nếu thiếu `.ex5` để nhắc biên dịch trong MetaEditor
- Báo lỗi rõ ràng khi không tìm thấy MT5 hay file nguồn

**Kết quả test:**
- Detect đúng folder: `C:\Users\workw\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts`
- Copy `bot.mq5` + `bot.ex5` thành công vào folder đó

Đã update `README.md` để bổ sung hướng dẫn dùng `install-ea.bat`.

**Cách dùng:** Bấm đôi vào `install-ea.bat` hoặc chạy lệnh `install-ea.bat` trong thư mục dự án.

