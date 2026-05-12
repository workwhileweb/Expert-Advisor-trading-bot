# Expert Advisor Trading Bot — Hướng dẫn sử dụng (tiếng Việt)

Tài liệu này dành cho **người dùng cuối**: cách cài đặt MetaTrader 5, chạy các công cụ kiểm tra kèm bản **Windows (.exe)**, gắn Expert Advisor và vận hành an toàn. Nội dung kỹ thuật sâu (mã nguồn, build từ Python) không nằm trong phạm vi hướng dẫn này.

**Nhà phát triển:** bản README đầy đủ (clone, `pip`, lệnh `python`, cấu trúc repo, đóng góp) được giữ trong [`readme_dev.md`](readme_dev.md).

**Cảnh báo rủi ro:** Giao dịch forex có rủi ro cao. Hiệu suất trong quá khứ không đảm bảo kết quả tương lai. Chỉ dùng vốn bạn chấp nhận mất. Trên tài khoản thật, hãy đọc kỹ điều khoản broker và thử **demo** trước.

---

## Bot làm gì (tóm tắt)

- Expert Advisor chạy trên **MetaTrader 5**, phân tích kỹ thuật (MACD, fractal S/R, Fair Value Gap, đa khung) và có lớp quản lý rủi ro (lot động, giới hạn lỗ ngày, spread, hòa vốn khi đạt R:R 1:1, v.v.).
- Các file **`.exe`** trong thư mục `dist` thay cho việc gõ lệnh `python …`: kiểm tra kết nối MT5, xem thông tin tài khoản, kiểm tra `config.json`, và công cụ thử chức năng (có thể liên quan đặt lệnh — xem mục tương ứng bên dưới).

---

## Điều kiện cần có

| Hạng mục | Yêu cầu |
|----------|---------|
| Hệ điều hành | **Windows 10/11** 64-bit (khuyến nghị) |
| Phần mềm | **MetaTrader 5** đã cài, đã mở ít nhất một lần (để tạo thư mục dữ liệu) |
| Tài khoản | Tài khoản MT5 đăng nhập được; bật **Giao dịch thuật toán** (Algo Trading); nếu broker yêu cầu, bật **Cho phép import DLL** trong cài đặt terminal |
| Phần cứng / mạng | RAM và ổ đĩa theo yêu cầu MT5; kết nối internet ổn định |
| Bản công cụ `.exe` | Thư mục `dist` chứa các file: `init-test.exe`, `account-info.exe`, `config_manager.exe`, `test-function.exe` và file **`config.json`** đặt **cùng thư mục** với các `.exe` khi chạy |

**Lưu ý:** Bạn **không cần cài Python** để chạy các bước trong hướng dẫn này nếu đã có đủ file trong `dist`.

---

## Chuẩn bị file trước khi chạy `.exe`

1. Mở thư mục `dist` của gói bạn nhận được.
2. Đảm bảo có **`config.json`** nằm **cùng thư mục** với các file `.exe`. Nếu `config.json` đang ở thư mục gốc dự án, hãy **sao chép** một bản vào `dist` (hoặc luôn mở Command Prompt / PowerShell tại đúng thư mục chứa cả `.exe` và `config.json`).
3. Khi chạy bằng cách double-click hoặc từ dòng lệnh, **thư mục làm việc hiện tại** nên là thư mục đó để chương trình tìm thấy `config.json` (cách chắc chắn: mở terminal trong thư mục `dist` rồi gõ tên file `.exe` như ví dụ dưới).

Giải thích tham số từng mục trong `config.json` (rủi ro, symbol, MT5, …): xem file **`HUONG_DAN_CONFIG.md`** trong gói (mở bằng Notepad++ hoặc VS Code, lưu UTF-8).

---

## Cài Expert Advisor (`bot`) vào MetaTrader 5

### Cách nhanh (Windows)

1. Đặt **`install-ea.bat`** cùng thư mục với **`bot.mq5`** (và nếu có sẵn **`bot.ex5`**).
2. **Chuột phải** → **Chạy với quyền quản trị viên** nếu Windows chặn ghi vào `Program Files`.
3. Làm theo hộp thoại: script quét các cài đặt MT5, liệt kê đích; chọn cài vào **một** terminal hoặc **tất cả**.
4. Nếu không có `bot.ex5`, sau khi copy `bot.mq5` bạn mở **MetaEditor** (F4 trong MT5), mở `bot.mq5`, nhấn **Compile** (F7) để tạo `bot.ex5`.

### Gắn EA lên biểu đồ

1. Mở **MetaTrader 5**, đăng nhập tài khoản.
2. **Navigator** → **Expert Advisors** → kéo **`bot`** lên biểu đồ symbol / khung thời gian bạn muốn.
3. Trong hộp thoại thuộc tính EA, kiểm tra tham số (bảng tham số mẫu ở cuối tài liệu).
4. Bật **AutoTrading** (phím tắt thường dùng: **Ctrl+E**). Kiểm tra biểu tượng giao dịch thuật toán trên thanh công cụ.

---

## Thứ tự chạy công cụ `.exe` (thay cho lệnh Python)

**Luôn mở MetaTrader 5 và đăng nhập** trước khi chạy các bước kiểm tra kết nối.

Giả sử bạn đang đứng trong thư mục chứa `.exe` và `config.json` (ví dụ `dist`):

| Bước | Mục đích | File chạy |
|------|-----------|-----------|
| 1 | Kiểm tra kết nối terminal, khởi tạo API MT5, các bài test cơ bản | `init-test.exe` |
| 2 | Xem số dư, equity, server, leverage… | `account-info.exe` |
| 3 | Kiểm tra `config.json` có hợp lệ và tải được không | `config_manager.exe` |
| 4 | (Tùy chọn, **nguy hiểm** trên tài khoản thật) Thử chức năng liên quan lệnh — chỉ dùng khi bạn hiểu rõ | `test-function.exe` |

### Ví dụ dòng lệnh (PowerShell hoặc CMD)

Chuyển vào thư mục `dist` (đường dẫn chỉnh theo máy bạn):

```text
cd C:\Users\<TênUser>\Downloads\Expert-Advisor-trading-bot\dist
```

Sau đó lần lượt:

```text
.\init-test.exe
.\account-info.exe
.\config_manager.exe
```

**`test-function.exe`:** chỉ chạy khi bạn **chắc chắn** nội dung script thử nghiệm (có thể đặt lệnh thử). Trên **demo** trước; trên **live** cần đọc kỹ mô tả từ người phát hành bản build.

**Ghi chú:** Trong mã nguồn dự án có script `mt5-init.py` phục vụ nhà phát triển. **Không có file `.exe` tương ứng** trong gói `dist` tiêu chuẩn; việc xác minh kết nối tương đương dùng **`init-test.exe`** với MT5 đang chạy.

---

## Sau khi kiểm tra xong

1. Điều chỉnh **`config.json`** và chạy lại **`config_manager.exe`** cho đến khi không báo lỗi cấu hình.
2. Trên MT5, kiểm tra lại symbol, spread, khung thời gian biểu đồ khớp ý định giao dịch.
3. Bật EA và theo dõi tab **Experts** / **Journal** trên MT5 nếu cần hỗ trợ xử lý sự cố.

---

## Kiểm thử trên Strategy Tester (MT5)

1. Trong MT5: **View** → **Strategy Tester** (hoặc **Ctrl+R**).
2. Chọn Expert: **`bot`**.
3. Chọn symbol (ví dụ EURUSD), khung thời gian (thường **M1** nếu chiến lược mặc định theo EA), khoảng ngày có đủ dữ liệu.
4. Model: **Every tick** (chậm hơn nhưng gần thực tế hơn) nếu máy cho phép.
5. Tham số đầu vào EA nên **thống nhất** với rủi ro và cài đặt bạn dùng khi chạy thật.

---

## Tham số Expert Advisor (tham khảo nhanh)

| Tham số | Mặc định (tham chiếu) | Ý nghĩa ngắn gọn |
|---------|----------------------|------------------|
| RiskAmount | 50.0 | Rủi ro mỗi lệnh (đơn vị tiền tài khoản) |
| MaxDailyLoss | 200.0 | Giới hạn lỗ tối đa trong ngày |
| LookbackPeriod | 20 | Số nến nhìn lại cho S/R |
| MinRiskReward | 2.0 | R:R tối thiểu |
| MagicNumber | 234567 | Mã nhận diện lệnh của EA |
| EnableLogging | true | Ghi log chi tiết |
| MaxSpreadPoints | 0 | Tối đa spread (points MT5); **0 = tắt** lọc (cần cho XAU/CFD). Chi tiết: **`HUONG_DAN_SU_DUNG_BOT_VA_INPUTS.md`**. |
| EnablePeriodicStatus | true | Báo cáo định kỳ % điều kiện vào lệnh (tab Experts). |
| StatusIntervalSeconds | 60 | Chu kỳ báo cáo (giây); tối thiểu 10 khi bật báo cáo. |

Chi tiết logic vào lệnh (động lượng, MACD, FVG, spread…) được mô tả tổng quan trong các phiên bản README dành cho nhà phát triển; người dùng chỉ cần nắm rủi ro và vận hành đúng thứ tự kiểm tra ở trên. Bảng đầy đủ Input: **`HUONG_DAN_SU_DUNG_BOT_VA_INPUTS.md`**.

---

## Xử lý sự cố thường gặp

| Hiện tượng | Việc nên làm |
|-------------|----------------|
| `.exe` báo không tìm thấy `config.json` | Đặt `config.json` cùng thư mục với `.exe`; chạy lệnh từ đúng thư mục đó. |
| Lỗi kết nối MT5 | MT5 đã mở và đã đăng nhập; Tools → Options → **Expert Advisors** → bật giao dịch thuật toán; chạy lại **`init-test.exe`**. |
| EA không giao dịch | Kiểm tra AutoTrading; quyền tài khoản; ký quỹ; spread; nhật ký Experts trên MT5. |
| Không copy được EA vào thư mục MT5 | Chạy **`install-ea.bat`** bằng quyền quản trị viên; hoặc copy tay vào `...\MQL5\Experts\` của đúng terminal ID. |

---

## Cấu trúc thư mục gợi ý cho người dùng

```text
Expert-Advisor-trading-bot/
├── dist/
│   ├── init-test.exe
│   ├── account-info.exe
│   ├── config_manager.exe
│   ├── test-function.exe
│   └── config.json          ← nên có tại đây khi chạy .exe
├── bot.mq5
├── install-ea.bat
├── HUONG_DAN_CONFIG.md
└── README.md                ← tài liệu này
```

---

## Giấy phép và hỗ trợ

- Giấy phép cụ thể (nếu có) theo file đi kèm gói phân phối hoặc thông tin trên kho mã nguồn.
- Báo lỗi / đề xuất: qua kênh issue hoặc liên hệ mà tác giả dự án công bố trên repository.

---

**Tóm tắt:** Mở MT5 → chạy **`init-test.exe`**, **`account-info.exe`**, **`config_manager.exe`** (cùng thư mục với **`config.json`**) → cài EA bằng **`install-ea.bat`** hoặc copy thủ công → gắn **`bot`** lên biểu đồ → bật AutoTrading. Chỉ dùng **`test-function.exe`** khi hiểu rõ hậu quả, ưu tiên tài khoản **demo**.
