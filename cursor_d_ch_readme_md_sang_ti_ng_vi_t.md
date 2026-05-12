# Dịch README.md sang tiếng Việt
_Exported on 5/11/2026 at 10:00:37 GMT+7 from Cursor (3.3.30)_

---

**User**

@README.md dịch sang tiếng việt

---

**Cursor**

Đang đọc README.md để dịch toàn bộ sang tiếng Việt.



Đang ghi `README.md` bản tiếng Việt, giữ nguyên lệnh, đường dẫn và khối mã.



Đã dịch toàn bộ `README.md` sang tiếng Việt và ghi đè file.

**Đã giữ nguyên:** tiêu đề dự án, lệnh `bash`/`pip`, khối `json` và `python`, đường dẫn Windows, tên file, bảng tham số (tên cột tiếng Anh trong code vẫn giữ như `RiskAmount`…), liên kết GitHub và cấu trúc thư mục.

**Đã Việt hóa:** mô tả, hướng dẫn cài đặt, sử dụng, rủi ro, troubleshooting, đóng góp, disclaimer và phần tác giả. Thuật ngữ chuyên ngành (MACD, Expert Advisor, Fair Value Gap, R:R, backtest…) giữ song ngữ hoặc dịch kèm khi cần để dễ đọc.

Nếu bạn muốn thêm bản song ngữ (Anh + Việt) hoặc tách `README.vi.md` và giữ `README.md` tiếng Anh, nói rõ để chỉnh tiếp.

---

**User**

@bot.mq5 @account-info.py @config_manager.py @init-test.py @test-function.py @mt5-init.py áp dụng i18n cho text, dịch sang tiếng việt và đặt làm mặc định

---

**Cursor**

Đang đọc các file để nắm chuỗi cần i18n và thiết kế cách triển khai thống nhất.



Đang tạo module `i18n.py` dùng chung (mặc định `vi`, hỗ trợ `en` qua biến môi trường) và cập nhật `bot.mq5` với hàm `L()` cùng `input` chọn ngôn ngữ.



Đang thêm khóa tiêu đề cột cho `init-test` và sửa `i18n.py` (loại bỏ `it_market_header` gây nhầm).



Đang cập nhật `bot.mq5`: thêm enum ngôn ngữ, hàm `L()` và thay mọi chuỗi `Print`/comment.



Đã áp dụng i18n với **tiếng Việt làm mặc định** trên toàn bộ các file bạn liệt kê.

### Python — `i18n.py`
- Bảng chuỗi **`vi`** và **`en`** (khóa dùng chung cho mọi script).
- **`DEFAULT_LOCALE = "vi"`**; có thể đổi sang tiếng Anh bằng biến môi trường **`EA_BOT_LANG=en`** (trước khi chạy Python).
- Hàm **`t(key, **kwargs)`** cho chuỗi có `str.format`.
- Có **`set_locale("vi"|"en")`** nếu cần đổi trong cùng process.

### Đã cập nhật
- **`account-info.py`**, **`config_manager.py`**, **`init-test.py`**, **`test-function.py`**, **`mt5-init.py`**: mọi `print` người dùng thấy đi qua **`t(...)`**.
- **`bot.mq5`**: thêm **`ENUM_BOT_LANG`**, input **`InpLanguage`** (mặc định **Tiếng Việt**), hàm **`L(textVi, textEn)`** cho mọi **`Print`** / **`StringFormat`**; ghi chú tham số `input` bằng tiếng Việt; comment lệnh: **`EA Giới hạn bán`** (VI) / **`EA Sell Limit`** (EN).

### Cách dùng
- **EA / log MT5**: trong tab Inputs chọn **English** nếu muốn log tiếng Anh.
- **Script Python**: mặc định tiếng Việt; tiếng Anh:  
  PowerShell: `$env:EA_BOT_LANG='en'; python init-test.py`

Đã chạy **`python -m py_compile`** cho các module Python — không lỗi cú pháp. File **`bot.mq5`** cần biên dịch lại trong MetaEditor (F7) để kiểm tra `StringFormat` / `%I64u` trên bản build MT5 của bạn.

