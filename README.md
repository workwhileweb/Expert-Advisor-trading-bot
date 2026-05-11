# Expert Advisor Trading Bot

Expert Advisor MQL5 chuyên nghiệp với quản lý rủi ro nâng cao, xử lý lỗi toàn diện và công cụ tích hợp Python hiện đại. Bot giao dịch này triển khai thuật toán phân tích kỹ thuật tinh vi và biện pháp bảo mật phòng thủ cho giao dịch forex tự động.

## 🚀 Tính năng chính

### Logic giao dịch nâng cao
- **Phân tích MACD hiện đại**: Dùng cú pháp MQL5 hiện tại với handle chỉ báo đúng chuẩn
- **Hỗ trợ / kháng cự dựa trên fractal**: Phát hiện mức giá thông minh bằng phân tích fractal
- **Phát hiện Fair Value Gap (FVG) cải tiến**: Phân tích khoảng trống giá tinh vi, có xác nhận động lượng
- **Phân tích đa khung thời gian**: Hỗ trợ khung thời gian cấu hình được, không chỉ biểu đồ 1 phút

### Quản lý rủi ro & bảo mật
- **Khối lượng vị thế động**: Tính lot thông minh, bảo vệ vốn tài khoản
- **Giới hạn lỗ trong ngày**: Tự động dừng giao dịch khi đạt ngưỡng lỗ ngày
- **Bảo vệ spread**: Giám sát spread theo thời gian thực với giới hạn tối đa cấu hình được
- **Quản lý hòa vốn**: Tự động đưa stop loss về điểm hòa vốn khi đạt tỷ lệ R:R 1:1
- **An toàn tài khoản**: Tối đa 5% rủi ro tài khoản mỗi lệnh, có kiểm tra hợp lệ

### Cải tiến kỹ thuật
- **Xử lý lỗi toàn diện**: Phát hiện và ghi log lỗi ổn định trong toàn bộ mã
- **Cú pháp MQL5 hiện đại**: Cập nhật dùng hàm và cấu trúc MetaTrader 5 mới nhất
- **Kiểm tra tham số đầu vào**: Mọi tham số được kiểm tra trước khi chạy
- **Quản lý bộ nhớ**: Quản lý và giải phóng handle chỉ báo đúng cách

## 📊 Chiến lược giao dịch

### Tạo tín hiệu
- **Phát hiện đảo chiều giảm**: Nhận dạng mẫu hình nâng cao, xác định vùng giảm mạnh sau động lượng tăng
- **Hỗ trợ / kháng cự fractal**: Xác thực mức nhiều lần chạm bằng fractal trong khoảng nhìn lại cấu hình được
- **Phân tích Fair Value Gap**: Phát hiện khoảng trống tinh vi, có xác nhận khối lượng và động lượng
- **Hội tụ MACD**: Đối chiếu bằng histogram MACD và giao cắt đường tín hiệu

### Logic thực thi
- **Lệnh Sell Limit**: Đặt lệnh chiến lược tại vùng cung đã xác định
- **Rủi ro – lợi nhuận động**: Tỷ lệ R:R tối thiểu cấu hình được (mặc định 1:2)
- **Kiểm tra spread**: Kiểm tra spread theo thời gian thực trước khi vào lệnh
- **Chống trùng lệnh**: Logic nâng cao tránh nhiều lệnh trên cùng một tín hiệu

### Quản lý vị thế
- **Hòa vốn tự động**: Điều chỉnh stop loss khi lệnh đạt R:R 1:1
- **Trailing stop**: Tùy chọn trailing stop (cấu hình được)
- **Giám sát vị thế**: Theo dõi và quản lý vị thế theo thời gian thực

## 🛠️ Yêu cầu

### Phần mềm
- **MetaTrader 5** (khuyến nghị Build 3340 trở lên)
- **Python 3.8+** (cho script phụ và phân tích)
- **Gói Python MetaTrader5** (`pip install MetaTrader5`)

### Tài khoản
- Tài khoản giao dịch MetaTrader 5 đang hoạt động
- Bật giao dịch thuật toán (algorithmic trading)
- Ký quỹ đủ cho khối lượng vị thế
- Cho phép import DLL (cho chức năng mở rộng)

### Hệ thống
- Windows 10/11 (khuyến nghị 64-bit)
- Kết nối internet ổn định
- Tối thiểu 4GB RAM
- 1GB dung lượng đĩa trống

## 📦 Cài đặt

### 1. Clone repository
```bash
git clone https://github.com/Astralchemist/Expert-Advisor-trading-bot.git
cd Expert-Advisor-trading-bot
```

### 2. Cài dependency Python
```bash
pip install MetaTrader5
```

### 3. Thiết lập Expert Advisor trên MetaTrader 5
1. Sao chép `bot.mq5` vào thư mục Experts của MetaTrader 5:
   - Đường mặc định: `C:/Users/{Username}/AppData/Roaming/MetaQuotes/Terminal/{TerminalID}/MQL5/Experts/`
   - Hoặc: `C:/Program Files/MetaTrader 5/MQL5/Experts/`

2. Biên dịch Expert Advisor trong MetaEditor (F7)

3. Gắn lên biểu đồ:
   - Mở MetaTrader 5
   - Vào Navigator → Expert Advisors
   - Kéo `bot` vào biểu đồ mong muốn
   - Cấu hình tham số đầu vào
   - Bật AutoTrading (Ctrl+E)

### 4. Cấu hình
1. Chỉnh `config.json` để tùy chỉnh tham số giao dịch
2. Chạy `python config_manager.py` để kiểm tra cấu hình
3. Thử kết nối bằng `python init-test.py`

## 🎯 Sử dụng

### Bắt đầu nhanh
1. **Khởi tạo kết nối**: Chạy `python mt5-init.py` để kết nối MT5
2. **Xác minh tài khoản**: Chạy `python account-info.py` để kiểm tra trạng thái tài khoản
3. **Thử chức năng**: Chạy `python test-function.py` để thử đặt lệnh
4. **Gắn EA**: Thêm Expert Advisor lên biểu đồ giao dịch

### Tham số Expert Advisor
| Tham số | Mặc định | Mô tả |
|-----------|---------|-------------|
| RiskAmount | 50.0 | Rủi ro mỗi lệnh (đơn vị tiền tài khoản) |
| MaxDailyLoss | 200.0 | Giới hạn lỗ tối đa trong ngày |
| LookbackPeriod | 20 | Số nến phân tích S/R |
| MinRiskReward | 2.0 | Tỷ lệ rủi ro:lợi nhuận tối thiểu |
| MagicNumber | 234567 | Mã định danh EA |
| EnableLogging | true | Bật ghi log chi tiết |

### Điều kiện giao dịch
Bot quét tìm:
1. **Động lượng tăng** rồi **đảo chiều giảm**
2. Mức **hỗ trợ / kháng cự fractal** với nhiều lần chạm
3. **Fair value gap** khớp với mức giá quan trọng
4. **Xác nhận MACD** với động lượng và giao cắt tín hiệu
5. **Spread** trong ngưỡng chấp nhận được

### Thực thi lệnh
- Đặt **lệnh sell limit** tại vùng cung đã xác định
- Áp dụng **stop loss** và **take profit** động
- Tự động đưa SL về **hòa vốn** khi đạt R:R 1:1
- Giám sát và quản lý vị thế đến khi đóng

## ⚠️ Quản lý rủi ro

### Khối lượng vị thế
- **Tính lot động**: Dựa trên vốn tài khoản và phần trăm rủi ro
- **Rủi ro tối đa**: 5% vốn tài khoản mỗi lệnh (cấu hình được)
- **Lot tối thiểu / tối đa**: Tuân theo giới hạn sàn
- **Bảo vệ tài khoản**: Kiểm tra điều kiện ký quỹ

### Bảo vệ thua lỗ
- **Giới hạn lỗ ngày**: Tự dừng giao dịch khi đạt ngưỡng
- **Giám sát spread**: Kiểm tra spread theo thời gian thực trước khi vào lệnh
- **Bảo vệ vốn**: Theo dõi equity liên tục
- **Xử lý lỗi**: Phát hiện và phản hồi lỗi toàn diện

### Quản lý lệnh
- **Hòa vốn tự động**: SL chuyển về giá vào lệnh khi đạt R:R 1:1
- **Giám sát vị thế**: Theo dõi vị thế theo thời gian thực
- **Kiểm tra R:R**: Đảm bảo đạt R:R tối thiểu trước khi vào lệnh
- **Chống trùng**: Tránh nhiều lệnh trên cùng tín hiệu

## ⚙️ Tùy chỉnh

### File cấu hình (`config.json`)
```json
{
  "trading": {
    "risk_amount": 50.0,
    "max_daily_loss": 200.0,
    "min_risk_reward": 2.0,
    "max_spread_pips": 3.0
  },
  "analysis": {
    "lookback_period": 20,
    "macd_fast": 12,
    "macd_slow": 26,
    "macd_signal": 9
  },
  "symbols": [
    {
      "name": "EURUSD",
      "enabled": true,
      "max_spread": 0.0003
    }
  ]
}
```

### Trình quản lý cấu hình Python
```python
from config_manager import ConfigManager

config = ConfigManager()
config.set('trading.risk_amount', 75.0)
config.save_config()
```

### Các hướng tùy chỉnh được hỗ trợ
- **Tham số rủi ro**: Mức rủi ro, giới hạn ngày, tỷ lệ R:R
- **Chỉ báo kỹ thuật**: Chu kỳ MACD, khoảng nhìn lại
- **Cấu hình symbol**: Thêm / bỏ cặp giao dịch
- **Khung thời gian**: Đổi cho các chu kỳ biểu đồ khác
- **Logging**: Mức và tùy chọn ghi log chi tiết

## 📈 Kiểm thử & xác minh

### Strategy Tester (MT5)
1. Mở Strategy Tester trong MetaTrader 5 (Ctrl+R)
2. Chọn Expert Advisor: `bot`
3. Cấu hình tham số test:
   - Symbol: EURUSD hoặc GBPUSD
   - Khung thời gian: M1 (hoặc khung đã cấu hình)
   - Khoảng ngày: Đủ dữ liệu lịch sử
   - Model: Every tick (chính xác nhất)
4. Đặt tham số đầu vào khớp cấu hình live
5. Chạy backtest và phân tích kết quả

### Script kiểm thử Python
```bash
# Kiểm tra kết nối MT5
python init-test.py

# Xác minh thông tin tài khoản
python account-info.py

# Thử chức năng đặt lệnh
python test-function.py

# Kiểm tra cấu hình
python config_manager.py
```

### Chỉ số hiệu suất
- **Hệ số lợi nhuận (Profit Factor)**: Mục tiêu > 1.3
- **Drawdown tối đa**: Giữ < 20%
- **Tỷ lệ thắng**: Hướng tới > 40%
- **Rủi ro – lợi nhuận**: Duy trì R:R tối thiểu đã cấu hình
- **Hệ số Sharpe**: Mục tiêu > 1.0

## 📁 Cấu trúc thư mục

```
Expert-Advisor-trading-bot/
├── bot.mq5                 # Expert Advisor chính (MQL5)
├── config.json             # Cài đặt cấu hình
├── config_manager.py       # Trình quản lý cấu hình Python
├── mt5-init.py            # Khởi tạo kết nối MT5
├── account-info.py        # Hiển thị thông tin tài khoản
├── test-function.py       # Tiện ích thử đặt lệnh
├── init-test.py           # Bộ kiểm tra kết nối
└── README.md              # Tài liệu
```

## 🐛 Xử lý sự cố

### Vấn đề thường gặp

**Lỗi kết nối**
- Đảm bảo MetaTrader 5 đang chạy và đã đăng nhập
- Kiểm tra đã bật giao dịch thuật toán
- Xác minh cho phép import DLL
- Chạy `python init-test.py` để chẩn đoán

**Vấn đề giao dịch**
- Kiểm tra quyền tài khoản và ký quỹ
- Xác minh điều kiện spread
- Xem log EA trong tab Experts của MT5
- Kiểm tra cấu hình bằng `config_manager.py`

**Vấn đề hiệu năng**
- Theo dõi tài nguyên máy
- Kiểm tra độ ổn định mạng
- Xem file log lỗi
- Điều chỉnh lookback nếu cần

## 🔒 Tính năng bảo mật

- **Kiểm tra đầu vào**: Mọi tham số được kiểm tra trước khi dùng
- **Xử lý lỗi**: Phát hiện và ghi log lỗi toàn diện
- **Bảo vệ tài khoản**: Nhiều cơ chế an toàn
- **Lập trình phòng thủ**: Thực hành bảo mật trong toàn bộ mã
- **Không hardcode bí mật**: Dữ liệu nhạy cảm qua cấu hình

## 📊 Giám sát & phân tích

### Giám sát thời gian thực
- Theo dõi equity và số dư tài khoản
- Giám sát và quản lý vị thế
- Phân tích spread và điều kiện thị trường
- Phát hiện lỗi và cảnh báo

### Phân tích hiệu suất
- Phân tích lịch sử lệnh
- Tính toán chỉ số rủi ro
- Giám sát drawdown
- Theo dõi lãi / lỗ

## 🤝 Đóng góp

Mọi đóng góp đều được chào đón. Vui lòng:

1. Fork repository
2. Tạo nhánh tính năng
3. Thực hiện thay đổi
4. Thêm test nếu phù hợp
5. Gửi pull request

### Hướng dẫn phát triển
- Tuân thủ thực hành bảo mật phòng thủ
- Bổ sung xử lý lỗi đầy đủ
- Có kiểm tra đầu vào
- Cập nhật tài liệu
- Test kỹ trước khi gửi

## ⚖️ Tuyên bố miễn trừ

**CẢNH BÁO RỦI RO**: Giao dịch forex có rủi ro lớn và có thể không phù hợp với mọi nhà đầu tư. Hiệu suất trong quá khứ không đảm bảo kết quả tương lai. Phần mềm này chỉ phục vụ mục đích giáo dục. Sử dụng trên trách nhiệm của bạn.

## 📄 Giấy phép

Dự án được cấp phép theo MIT License — xem file LICENSE để biết chi tiết.

## 👨‍💻 Tác giả

- **GitHub**: [Astralchemist](https://github.com/Astralchemist)
- **Dự án**: Expert Advisor Trading Bot
- **Phiên bản**: 2.0 (Enhanced)

---

*Hỗ trợ, báo lỗi hoặc đề xuất tính năng: vui lòng mở issue trên GitHub.*
