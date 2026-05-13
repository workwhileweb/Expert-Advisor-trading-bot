# Hướng dẫn cấu hình cho config.json
_Exported on 5/11/2026 at 09:59:42 GMT+7 from Cursor (3.3.30)_

---

**User**

@config.json tạo file md hướng dẫn các tham số và cách cấu hình chi tiết cho người mới, 

---

**Cursor**

Đang đọc `config.json` và `config_manager.py` để viết tài liệu hướng dẫn chính xác.



Đang kiểm tra cách bot và script Python sử dụng các tham số này.



Đang tạo `HUONG_DAN_CONFIG.md` — tài liệu đầy đủ, ghi rõ ràng phần được `ConfigManager` kiểm tra và phần dùng cho script Python vs EA.



Đã tạo file **`HUONG_DAN_CONFIG.md`** trong thư mục gốc dự án với nội dung:

- **Bắt đầu nhanh**: backup, UTF-8, cách chạy `python config_manager.py` để kiểm tra.
- **Bảng tổng quan** 5 mục bắt buộc.
- **Chi tiết từng tham số** trong `trading`, `analysis`, `symbols`, `logging`, `mt5` (ý nghĩa, kiểu dữ liệu, gợi ý cho người mới).
- **Ví dụ thêm symbol** (JSON).
- **Quy tắc validate** trong `config_manager.py` (rủi ro &gt; 0, `min_risk_reward` ≥ 1, `symbols` không rỗng, v.v.).
- **Lưu ý quan trọng**: `config.json` dùng cho Python/`ConfigManager`; EA `bot.mq5` dùng **Inputs** trên MT5 — cần **đồng bộ tay** nếu muốn giống nhau (và MACD/spread trong EA hiện hardcode ở một số chỗ, đã nêu trong md).
- **Lỗi JSON thường gặp** và bảng “muốn chỉnh gì → sửa đâu”.

Đường dẫn đầy đủ: `C:\Users\workw\Downloads\Expert-Advisor-trading-bot\HUONG_DAN_CONFIG.md`.

*(Đã thử chạy `python config_manager.py`; trên máy bạn console Windows đang dùng cp1252 nên `print` tiếng Việt từ `i18n` bị `UnicodeEncodeError` — đó là vấn đề encoding terminal, không phải do file md. Nếu cần, có thể chạy với `PYTHONUTF8=1` hoặc đổi code page sang UTF-8.)*

