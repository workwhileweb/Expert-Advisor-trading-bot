//+------------------------------------------------------------------+
//| bot.mq5 — Expert Advisor (i18n: mặc định Tiếng Việt)              |
//+------------------------------------------------------------------+
enum ENUM_BOT_LANG
  {
   BOT_LANG_VI = 0,   // Tiếng Việt
   BOT_LANG_EN = 1    // English
  };

input ENUM_BOT_LANG InpLanguage = BOT_LANG_VI; // Ngôn ngữ log / Log language

input double RiskAmount = 50.0;        // Số tiền rủi ro mỗi lệnh (tiền tệ TK)
input double MaxDailyLoss = 200.0;     // Giới hạn lỗ tối đa trong ngày
input int LookbackPeriod = 20;         // Số nến phân tích vùng Hỗ trợ/Kháng cự
input double MinRiskReward = 2.0;      // Tỷ lệ rủi ro:lợi nhuận tối thiểu
input int MagicNumber = 234567;        // Mã định danh EA
input bool EnableLogging = true;       // Bật ghi log chi tiết
// Spread: SYMBOL_SPREAD của MT5 là đơn vị "points" của symbol (khác nhau giữa EURUSD và XAUUSD).
// 0 = không lọc theo spread (khuyến nghị thử trước với vàng/CFD). >0 = chỉ trade khi spread <= giá trị này.
input int MaxSpreadPoints = 0;         // Tối đa spread (points); 0 = tắt kiểm tra
input bool EnablePeriodicStatus = true; // Thông báo định kỳ: % đủ điều kiện vào lệnh
input int StatusIntervalSeconds = 60;  // Chu kỳ báo cáo (giây); tối thiểu 10

//+------------------------------------------------------------------+
//| Chuỗi đa ngôn ngữ (mặc định VI qua InpLanguage)                   |
//+------------------------------------------------------------------+
string L(const string textVi, const string textEn)
  {
   return (InpLanguage == BOT_LANG_VI) ? textVi : textEn;
  }

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
double dailyStartBalance;
bool tradingEnabled = true;
int macdHandle;
datetime lastTradeTime = 0;
datetime lastStatusLogTime = 0;

//+------------------------------------------------------------------+
//| Helper: ngắn gọn OK / chưa đạt cho log trạng thái                |
//+------------------------------------------------------------------+
string StatusOk(const bool ok)
  {
   return ok ? L("Đạt", "OK") : L("Chưa", "No");
  }

//+------------------------------------------------------------------+
//| Báo cáo định kỳ: % điều kiện vào lệnh (đánh giá độc lập từng bước)|
//+------------------------------------------------------------------+
void LogEntryReadinessSummary()
  {
   const int total = 9;
   int passed = 0;

   bool cLoss = CheckDailyLossLimit(true);
   if(cLoss)
      passed++;

   bool cTrading = tradingEnabled;
   if(cTrading)
      passed++;

   bool cCooldown = (TimeCurrent() - lastTradeTime >= 60);
   if(cCooldown)
      passed++;

   bool cFlat = (PositionsTotal() == 0);
   if(cFlat)
      passed++;

   bool cSpread = IsSpreadAcceptable(true);
   if(cSpread)
      passed++;

   bool cMacd = CheckMACD(true);
   if(cMacd)
      passed++;

   bool cBear = DetectBearishZone(true);
   if(cBear)
      passed++;

   double sup = IdentifySupportZone(true);
   double res = IdentifyResistanceZone(true);
   bool cSR = (sup > 0 && res > 0 && sup < res);
   if(cSR)
      passed++;

   bool cFvg = false;
   if(cSR)
      cFvg = IsFVGAndResistanceAligned(sup, res);
   if(cFvg)
      passed++;

   int pct = (int)MathRound(100.0 * (double)passed / (double)total);
   long sprPts = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);

   Print(L("---------- EA — báo cáo trạng thái ----------",
           "---------- EA — status report ----------"));
   Print(StringFormat(L("Symbol: %s | Đủ điều kiện vào lệnh: %d%% (%d/%d)",
                         "Symbol: %s | Entry readiness: %d%% (%d/%d)"),
                      Symbol(), pct, passed, total));
   Print(StringFormat(L("Chi tiết: Lỗ ngày:%s | Cho phép GD:%s | Chờ 60s:%s | Không vị thế:%s | Spread:%s | MACD:%s | Vùng giảm:%s | Hỗ trợ/Kháng cự:%s | FVG+KC:%s",
                         "Detail: DailyLoss:%s | TradingOn:%s | Cooldown:%s | Flat:%s | Spread:%s | MACD:%s | BearZone:%s | S/R:%s | FVG:%s"),
                      StatusOk(cLoss), StatusOk(cTrading), StatusOk(cCooldown), StatusOk(cFlat),
                      StatusOk(cSpread), StatusOk(cMacd), StatusOk(cBear), StatusOk(cSR), StatusOk(cFvg)));
   Print(StringFormat(L("Spread hiện: %d points | MaxSpreadPoints: %d (%s)",
                         "Current spread: %d points | MaxSpreadPoints: %d (%s)"),
                      (int)sprPts, MaxSpreadPoints,
                      MaxSpreadPoints <= 0 ? L("tắt lọc", "filter off") : L("bật lọc", "filter on")));
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   macdHandle = iMACD(Symbol(), PERIOD_M1, 12, 26, 9, PRICE_CLOSE);
   if(macdHandle == INVALID_HANDLE)
     {
      Print(L("Không tạo được handle chỉ báo MACD.", "Failed to create MACD indicator handle"));
      return(INIT_FAILED);
     }

   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(RiskAmount <= 0 || MaxDailyLoss <= 0 || MinRiskReward <= 1.0)
     {
      Print(L("Tham số đầu vào không hợp lệ.", "Invalid input parameters"));
      return(INIT_FAILED);
     }

   if(EnablePeriodicStatus && StatusIntervalSeconds > 0 && StatusIntervalSeconds < 10)
     {
      Print(L("StatusIntervalSeconds < 10 — đặt lại tối thiểu 10 hoặc tắt báo cáo định kỳ.",
              "StatusIntervalSeconds < 10 — use at least 10 or disable periodic status."));
      return(INIT_FAILED);
     }

   lastStatusLogTime = TimeCurrent();

   Print(L("EA khởi tạo thành công.", "EA Trader initialized successfully"));
   if(EnablePeriodicStatus && StatusIntervalSeconds > 0)
      Print(StringFormat(L("Báo cáo trạng thái mỗi %d giây (%% điều kiện vào lệnh).",
                           "Periodic status every %d seconds (entry readiness %%)."),
                        StatusIntervalSeconds));
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(macdHandle != INVALID_HANDLE)
      IndicatorRelease(macdHandle);
   Print(StringFormat(L("EA đã dừng. Mã lý do: %d", "EA Trader deinitialized. Reason: %d"), reason));
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(EnablePeriodicStatus && StatusIntervalSeconds > 0)
     {
      if(TimeCurrent() - lastStatusLogTime >= StatusIntervalSeconds)
        {
         LogEntryReadinessSummary();
         lastStatusLogTime = TimeCurrent();
        }
     }

   if(!CheckDailyLossLimit())
     {
      tradingEnabled = false;
      return;
     }

   if(!tradingEnabled)
      return;

   if(TimeCurrent() - lastTradeTime < 60)
      return;

   if(PositionsTotal() > 0)
      return;

   if(!IsSpreadAcceptable())
      return;

   bool macdConfirmation = CheckMACD();
   if(!macdConfirmation)
      return;

   bool isBearishZone = DetectBearishZone();
   if(!isBearishZone)
      return;

   double supportLevel = IdentifySupportZone();
   double resistanceLevel = IdentifyResistanceZone();

   if(supportLevel <= 0 || resistanceLevel <= 0 || supportLevel >= resistanceLevel)
     {
      if(EnableLogging)
         Print(StringFormat(L("Mức Hỗ trợ/Kháng cự không hợp lệ: Hỗ trợ=%.5f, Kháng cự=%.5f",
                              "Invalid support/resistance levels: Support=%.5f, Resistance=%.5f"),
               supportLevel, resistanceLevel));
      return;
     }

   if (IsFVGAndResistanceAligned(supportLevel, resistanceLevel))
     {
      SetSellLimit(supportLevel, resistanceLevel);
     }

   ManagePositions();
  }
//+------------------------------------------------------------------+
//| Function to check MACD confirmation                              |
//+------------------------------------------------------------------+
bool CheckMACD(const bool quiet = false)
  {
   double macdMain[], macdSignal[];

   if(CopyBuffer(macdHandle, 0, 0, 3, macdMain) < 0 ||
      CopyBuffer(macdHandle, 1, 0, 3, macdSignal) < 0)
     {
      if(EnableLogging && !quiet)
         Print(StringFormat(L("Lỗi lấy dữ liệu MACD: %d", "Error retrieving MACD values: %d"), GetLastError()));
      return false;
     }

   if(ArraySize(macdMain) < 3 || ArraySize(macdSignal) < 3)
     {
      if(EnableLogging && !quiet)
         Print(L("Không đủ dữ liệu MACD.", "Insufficient MACD data"));
      return false;
     }

   bool crossBelow = macdMain[0] < macdSignal[0] && macdMain[1] >= macdSignal[1];
   bool bearishMomentum = macdMain[0] < macdMain[1];

   return crossBelow && bearishMomentum;
  }
//+------------------------------------------------------------------+
//| Function to detect significant bearish zone after bullish push   |
//+------------------------------------------------------------------+
bool DetectBearishZone(const bool quiet = false)
  {
   double open[], close[], high[], low[];

   if(CopyOpen(Symbol(), PERIOD_M1, 0, 10, open) < 0 ||
      CopyClose(Symbol(), PERIOD_M1, 0, 10, close) < 0 ||
      CopyHigh(Symbol(), PERIOD_M1, 0, 10, high) < 0 ||
      CopyLow(Symbol(), PERIOD_M1, 0, 10, low) < 0)
     {
      if(EnableLogging && !quiet)
         Print(L("Lỗi lấy dữ liệu giá để phát hiện vùng giảm.", "Error getting price data for bearish zone detection"));
      return false;
     }

   int bullishCount = 0;
   for(int i = 5; i < 9; i++)
     {
      if(close[i] > open[i])
         bullishCount++;
     }

   bool hadBullishPush = bullishCount >= 3;

   bool currentBearish = close[0] < open[0];
   double currentBodySize = MathAbs(close[0] - open[0]);
   double avgBodySize = 0;

   for(int i = 1; i <= 5; i++)
      avgBodySize += MathAbs(close[i] - open[i]);
   avgBodySize /= 5;

   bool significantBearishCandle = currentBodySize > avgBodySize * 1.5;

   return hadBullishPush && currentBearish && significantBearishCandle;
  }
//+------------------------------------------------------------------+
//| Function to identify the support zone using fractal analysis    |
//+------------------------------------------------------------------+
double IdentifySupportZone(const bool quiet = false)
  {
   double low[];

   if(CopyLow(Symbol(), PERIOD_M1, 0, LookbackPeriod + 5, low) < 0)
     {
      if(EnableLogging && !quiet)
         Print(L("Lỗi lấy giá thấp cho vùng hỗ trợ.", "Error getting low prices for support zone"));
      return 0;
     }

   double supportLevel = 0;
   int touchCount = 0;

   for(int i = 2; i < ArraySize(low) - 2; i++)
     {
      if(low[i] <= low[i-1] && low[i] <= low[i-2] &&
         low[i] <= low[i+1] && low[i] <= low[i+2])
        {
         int currentTouches = 0;
         for(int j = 0; j < ArraySize(low); j++)
           {
            if(MathAbs(low[j] - low[i]) <= Point() * 5)
               currentTouches++;
           }

         if(currentTouches > touchCount)
           {
            touchCount = currentTouches;
            supportLevel = low[i];
           }
        }
     }

   return supportLevel;
  }
//+------------------------------------------------------------------+
//| Function to identify the resistance zone using fractal analysis |
//+------------------------------------------------------------------+
double IdentifyResistanceZone(const bool quiet = false)
  {
   double high[];

   if(CopyHigh(Symbol(), PERIOD_M1, 0, LookbackPeriod + 5, high) < 0)
     {
      if(EnableLogging && !quiet)
         Print(L("Lỗi lấy giá cao cho vùng kháng cự.", "Error getting high prices for resistance zone"));
      return 0;
     }

   double resistanceLevel = 0;
   int touchCount = 0;

   for(int i = 2; i < ArraySize(high) - 2; i++)
     {
      if(high[i] >= high[i-1] && high[i] >= high[i-2] &&
         high[i] >= high[i+1] && high[i] >= high[i+2])
        {
         int currentTouches = 0;
         for(int j = 0; j < ArraySize(high); j++)
           {
            if(MathAbs(high[j] - high[i]) <= Point() * 5)
               currentTouches++;
           }

         if(currentTouches > touchCount)
           {
            touchCount = currentTouches;
            resistanceLevel = high[i];
           }
        }
     }

   return resistanceLevel;
  }
//+------------------------------------------------------------------+
//| Function to check if FVG and resistance are aligned              |
//+------------------------------------------------------------------+
bool IsFVGAndResistanceAligned(double support, double resistance)
  {
   double fvgStart = iLow(Symbol(), PERIOD_M1, 2);
   double fvgEnd = iHigh(Symbol(), PERIOD_M1, 0);

   return (fvgStart < resistance && fvgEnd > resistance);
  }
//+------------------------------------------------------------------+
//| Function to set a sell limit order at the supply zone            |
//+------------------------------------------------------------------+
void SetSellLimit(double support, double resistance)
  {
   double entryPrice = resistance;
   double stopLoss = resistance + (resistance - support) * 0.5;
   double riskRewardDistance = entryPrice - support;
   double takeProfit = entryPrice - (riskRewardDistance * MinRiskReward);

   if(stopLoss <= entryPrice || takeProfit >= entryPrice)
     {
      if(EnableLogging)
         Print(StringFormat(L("Mức SL/TP không hợp lệ. Vào: %.5f, SL: %.5f, TP: %.5f",
                              "Invalid SL/TP levels. Entry: %.5f, SL: %.5f, TP: %.5f"),
               entryPrice, stopLoss, takeProfit));
      return;
     }

   double lotSize = CalculateLotSize(RiskAmount, stopLoss, entryPrice);
   if(lotSize <= 0)
     {
      if(EnableLogging)
         Print(StringFormat(L("Khối lượng tính được không hợp lệ: %.2f", "Invalid lot size calculated: %.2f"), lotSize));
      return;
     }

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_PENDING;
   request.symbol = Symbol();
   request.volume = lotSize;
   request.type = ORDER_TYPE_SELL_LIMIT;
   request.price = entryPrice;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.magic = MagicNumber;
   request.comment = L("EA Giới hạn bán", "EA Sell Limit");
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request, result))
     {
      if(EnableLogging)
         Print(StringFormat(L("Đặt lệnh thất bại. Lỗi: %d, Mã trả về: %d",
                              "Order failed. Error: %d, Retcode: %d"),
               GetLastError(), (int)result.retcode));
     }
   else
     {
      lastTradeTime = TimeCurrent();
      if(EnableLogging)
         Print(StringFormat(L("Đã đặt lệnh sell limit. Ticket: %I64u, Vào: %.5f, SL: %.5f, TP: %.5f",
                              "Sell limit order placed. Ticket: %I64u, Entry: %.5f, SL: %.5f, TP: %.5f"),
               result.order, entryPrice, stopLoss, takeProfit));
     }
  }
//+------------------------------------------------------------------+
//| Function to calculate lot size based on risk with validation     |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double stopLoss, double entryPrice)
  {
   if(riskAmount <= 0 || stopLoss <= 0 || entryPrice <= 0)
     {
      if(EnableLogging)
         Print(L("Tham số tính khối lượng không hợp lệ.", "Invalid parameters for lot size calculation"));
      return 0;
     }

   double riskDistance = MathAbs(stopLoss - entryPrice);
   if(riskDistance <= 0)
     {
      if(EnableLogging)
         Print(StringFormat(L("Khoảng cách rủi ro không hợp lệ: %.5f", "Invalid risk distance: %.5f"), riskDistance));
      return 0;
     }

   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   if(tickValue <= 0 || tickSize <= 0)
     {
      if(EnableLogging)
         Print(L("Thông tin tick của symbol không hợp lệ.", "Invalid symbol tick information"));
      return 0;
     }

   double riskInTicks = riskDistance / tickSize;
   double lotSize = riskAmount / (riskInTicks * tickValue);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;

   if(lotSize < minLot)
      lotSize = minLot;
   if(lotSize > maxLot)
      lotSize = maxLot;

   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double maxRiskPercent = 0.05;
   double maxAllowedLot = (accountEquity * maxRiskPercent) / (riskInTicks * tickValue);

   if(lotSize > maxAllowedLot)
     {
      if(EnableLogging)
         Print(StringFormat(L("Khối lượng vượt quá 5%% rủi ro tài khoản. Điều chỉnh từ %.2f xuống %.2f",
                              "Lot size exceeds 5% account risk. Adjusted from %.2f to %.2f"),
               lotSize, maxAllowedLot));
      lotSize = maxAllowedLot;
     }

   return NormalizeDouble(lotSize, 2);
  }
//+------------------------------------------------------------------+
//| Function to check daily loss limit                              |
//+------------------------------------------------------------------+
bool CheckDailyLossLimit(const bool quiet = false)
  {
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyLoss = dailyStartBalance - currentBalance;

   if(dailyLoss >= MaxDailyLoss)
     {
      if(EnableLogging && !quiet)
         Print(StringFormat(L("Đã đạt giới hạn lỗ ngày: %.2f >= %.2f",
                              "Daily loss limit reached: %.2f >= %.2f"),
               dailyLoss, MaxDailyLoss));
      return false;
     }

   return true;
  }
//+------------------------------------------------------------------+
//| Function to check if spread is acceptable                       |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(const bool quiet = false)
  {
   if(MaxSpreadPoints <= 0)
      return true;

   long spreadPts = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   if(spreadPts > MaxSpreadPoints)
     {
      if(EnableLogging && !quiet)
         Print(StringFormat(L("Spread quá cao: %d points > %d (gia %.5f)",
                              "Spread too high: %d points > %d (price %.5f)"),
               (int)spreadPts, MaxSpreadPoints, spreadPts * Point()));
      return false;
     }

   return true;
  }
//+------------------------------------------------------------------+
//| Function to manage existing positions (move SL to breakeven)    |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
           {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double stopLoss = PositionGetDouble(POSITION_SL);
            double takeProfit = PositionGetDouble(POSITION_TP);

            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
              {
               double riskDistance = openPrice - stopLoss;
               double currentProfit = openPrice - currentPrice;

               if(currentProfit >= riskDistance && stopLoss != openPrice)
                 {
                  MqlTradeRequest request = {};
                  MqlTradeResult result = {};

                  request.action = TRADE_ACTION_SLTP;
                  request.symbol = Symbol();
                  request.sl = openPrice;
                  request.tp = takeProfit;
                  request.position = PositionGetTicket(i);

                  if(OrderSend(request, result) && EnableLogging)
                     Print(StringFormat(L("Đã đưa SL về hòa vốn cho vị thế: %I64u",
                                          "Stop loss moved to breakeven for position: %I64u"),
                           PositionGetTicket(i)));
                 }
              }
           }
        }
     }
  }
