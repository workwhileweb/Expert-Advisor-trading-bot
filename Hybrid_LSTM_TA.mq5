//+------------------------------------------------------------------+
//| Hybrid_LSTM_TA.mq5 — LSTM chuỗi thời gian + mô hình nến TA-Lib   |
//| Chỉ log dự đoán xu hướng; không tự động gửi lệnh.                |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "1.00"
#property description "Hybrid: LSTM suy luận trên chuỗi OHLC + mô hình nến kiểu TA-Lib tại S/R."
#property description "Log xu hướng TĂNG/GIẢM/NEUTRAL khi có nến mới."

enum ENUM_HYBRID_LANG
  {
   HYBRID_LANG_VI = 0,
   HYBRID_LANG_EN = 1
  };

input ENUM_HYBRID_LANG InpLanguage = HYBRID_LANG_VI;
input int InpLookbackBars = 80;
input int InpLstmSequence = 48;
input int InpLstmHidden = 12;
input double InpSrTouchPips = 15.0;
input int InpSrMinTouches = 2;
input double InpSrZonePips = 8.0;
input bool InpLogEveryBar = true;
input int InpLogIntervalSeconds = 0;
input bool InpWriteCsv = false;
input string InpCsvFileName = "hybrid_lstm_ta_log.csv";
input string InpOnnxSettings = "=== ONNX LSTM ===";
input bool InpUseOnnxModel = true;
input string InpOnnxModelFile = "hybrid_lstm.onnx";

#define LSTM_FEAT 5

string L(const string textVi, const string textEn)
  {
   return (InpLanguage == HYBRID_LANG_VI) ? textVi : textEn;
  }

datetime g_lastBarTime = 0;
datetime g_lastLogTime = 0;
bool g_csvHeaderWritten = false;
bool g_hasPriorPrediction = false;
double g_prevLogPrice = 0.0;
int g_prevPredictionDirection = 0;
int g_forecastScored = 0;
int g_forecastCorrect = 0;
long g_onnxHandle = INVALID_HANDLE;
bool g_onnxReady = false;
string g_lstmBackend = "embedded";

double g_Wf[], g_Wi[], g_Wo[], g_Wg[];
double g_Uf[], g_Ui[], g_Uo[], g_Ug[];
double g_bf[], g_bi[], g_bo[], g_bg[];
double g_Wy[], g_by[];

double PipSize()
  {
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(digits == 3 || digits == 5)
      return point * 10.0;
   return point;
  }

double CurrentMarketPrice(const double closeFallback)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid > 0.0)
      return bid;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask > 0.0)
      return ask;

   double last = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   if(last > 0.0)
      return last;

   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick))
     {
      if(tick.bid > 0.0)
         return tick.bid;
      if(tick.ask > 0.0)
         return tick.ask;
      if(tick.last > 0.0)
         return tick.last;
     }

   if(closeFallback > 0.0)
      return closeFallback;

   return iClose(_Symbol, _Period, 0);
  }

double Sigmoid(const double x)
  {
   if(x > 20.0)
      return 1.0;
   if(x < -20.0)
      return 0.0;
   return 1.0 / (1.0 + MathExp(-x));
  }

double Tanh(const double x)
  {
   if(x > 20.0)
      return 1.0;
   if(x < -20.0)
      return -1.0;
   return MathTanh(x);
  }

int WeightIndex(const int row, const int col, const int cols)
  {
   return row * cols + col;
  }

void InitLstmWeights()
  {
   const int hidden = InpLstmHidden;
   const int inputSize = LSTM_FEAT;
   const int gateInput = hidden + inputSize;
   const int gateCount = hidden * gateInput;
   const int outCount = hidden * 2;

   ArrayResize(g_Wf, gateCount);
   ArrayResize(g_Wi, gateCount);
   ArrayResize(g_Wo, gateCount);
   ArrayResize(g_Wg, gateCount);
   ArrayResize(g_Uf, gateCount);
   ArrayResize(g_Ui, gateCount);
   ArrayResize(g_Uo, gateCount);
   ArrayResize(g_Ug, gateCount);
   ArrayResize(g_bf, hidden);
   ArrayResize(g_bi, hidden);
   ArrayResize(g_bo, hidden);
   ArrayResize(g_bg, hidden);
   ArrayResize(g_Wy, outCount);
   ArrayResize(g_by, 2);

   for(int i = 0; i < gateCount; i++)
     {
      const double seed = 0.08 * MathSin((i + 1) * 0.137);
      g_Wf[i] = seed;
      g_Wi[i] = seed * 1.07;
      g_Wo[i] = seed * 0.93;
      g_Wg[i] = seed * 1.11;
      g_Uf[i] = seed * 0.61;
      g_Ui[i] = seed * 0.67;
      g_Uo[i] = seed * 0.59;
      g_Ug[i] = seed * 0.71;
     }

   for(int i = 0; i < hidden; i++)
     {
      g_bf[i] = 0.01;
      g_bi[i] = 0.01;
      g_bo[i] = 0.01;
      g_bg[i] = 0.01;
     }

   for(int i = 0; i < outCount; i++)
      g_Wy[i] = 0.05 * MathCos((i + 1) * 0.211);

   g_by[0] = 0.02;
   g_by[1] = -0.02;
  }

bool CopyOhlcSeries(const int count, double &open[], double &high[], double &low[], double &close[])
  {
   if(count <= 0)
      return false;

   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(CopyOpen(_Symbol, _Period, 0, count, open) < count)
      return false;
   if(CopyHigh(_Symbol, _Period, 0, count, high) < count)
      return false;
   if(CopyLow(_Symbol, _Period, 0, count, low) < count)
      return false;
   if(CopyClose(_Symbol, _Period, 0, count, close) < count)
      return false;

   return true;
  }

double AverageRange(const double &high[], const double &low[], const int start, const int length)
  {
   double sum = 0.0;
   for(int i = start; i < start + length; i++)
      sum += MathMax(high[i] - low[i], _Point);
   return sum / (double)length;
  }

bool BuildBarFeature(const double &open[], const double &high[], const double &low[], const double &close[],
                     const int shift, const double avgRange, double &feature[])
  {
   if(shift + 1 >= ArraySize(close))
      return false;

   ArrayResize(feature, LSTM_FEAT);
   const double range = MathMax(high[shift] - low[shift], _Point);
   const double body = close[shift] - open[shift];
   const double prevReturn = (close[shift] - close[shift + 1]) / MathMax(avgRange, _Point);
   const double upperWick = (high[shift] - MathMax(open[shift], close[shift])) / range;
   const double lowerWick = (MathMin(open[shift], close[shift]) - low[shift]) / range;

   feature[0] = body / range;
   feature[1] = prevReturn;
   feature[2] = upperWick;
   feature[3] = lowerWick;
   feature[4] = range / MathMax(avgRange, _Point);
   return true;
  }

void LstmGateVector(const double &gateW[], const double &gateU[], double &bias[],
                    const double &hiddenState[], const double &inputVec[],
                    double &gateOut[])
  {
   const int hidden = InpLstmHidden;
   const int inputSize = LSTM_FEAT;
   ArrayResize(gateOut, hidden);

   for(int j = 0; j < hidden; j++)
     {
      double sum = bias[j];
      for(int k = 0; k < hidden; k++)
         sum += gateW[WeightIndex(j, k, hidden + inputSize)] * hiddenState[k];
      for(int k = 0; k < inputSize; k++)
         sum += gateU[WeightIndex(j, k, hidden + inputSize)] * inputVec[k];
      gateOut[j] = sum;
     }
  }

bool RunLstmPredictorNative(const double &open[], const double &high[], const double &low[], const double &close[],
                            double &probUp, double &probDown, int &direction)
  {
   probUp = 0.5;
   probDown = 0.5;
   direction = 0;

   const int seqLen = InpLstmSequence;
   if(ArraySize(close) < seqLen + 2)
      return false;

   const double avgRange = AverageRange(high, low, 0, MathMin(20, ArraySize(close) - 1));
   double hiddenState[];
   double cellState[];
   ArrayResize(hiddenState, InpLstmHidden);
   ArrayResize(cellState, InpLstmHidden);
   ArrayInitialize(hiddenState, 0.0);
   ArrayInitialize(cellState, 0.0);

   for(int t = seqLen - 1; t >= 0; t--)
     {
      double feature[];
      if(!BuildBarFeature(open, high, low, close, t, avgRange, feature))
         return false;

      double gateF[], gateI[], gateO[], gateG[];
      LstmGateVector(g_Wf, g_Uf, g_bf, hiddenState, feature, gateF);
      LstmGateVector(g_Wi, g_Ui, g_bi, hiddenState, feature, gateI);
      LstmGateVector(g_Wo, g_Uo, g_bo, hiddenState, feature, gateO);
      LstmGateVector(g_Wg, g_Ug, g_bg, hiddenState, feature, gateG);

      for(int j = 0; j < InpLstmHidden; j++)
        {
         const double f = Sigmoid(gateF[j]);
         const double i = Sigmoid(gateI[j]);
         const double o = Sigmoid(gateO[j]);
         const double g = Tanh(gateG[j]);
         cellState[j] = f * cellState[j] + i * g;
         hiddenState[j] = o * Tanh(cellState[j]);
        }
     }

   double logits[];
   ArrayResize(logits, 2);
   logits[0] = g_by[0];
   logits[1] = g_by[1];
   for(int j = 0; j < InpLstmHidden; j++)
     {
      logits[0] += g_Wy[WeightIndex(0, j, InpLstmHidden)] * hiddenState[j];
      logits[1] += g_Wy[WeightIndex(1, j, InpLstmHidden)] * hiddenState[j];
     }

   const double maxLogit = MathMax(logits[0], logits[1]);
   const double expUp = MathExp(logits[0] - maxLogit);
   const double expDown = MathExp(logits[1] - maxLogit);
   const double denom = expUp + expDown;
   if(denom <= 0.0)
      return false;

   probUp = expUp / denom;
   probDown = expDown / denom;

   if(probUp - probDown > 0.03)
      direction = 1;
   else if(probDown - probUp > 0.03)
      direction = -1;
   else
      direction = 0;

   return true;
  }

bool FillLstmInputMatrix(const double &open[], const double &high[], const double &low[], const double &close[],
                         matrix &input)
  {
   const int seqLen = InpLstmSequence;
   if(ArraySize(close) < seqLen + 2)
      return false;

   if(!input.Resize(seqLen, LSTM_FEAT))
      return false;

   const double avgRange = AverageRange(high, low, 0, MathMin(20, ArraySize(close) - 1));
   for(int t = seqLen - 1; t >= 0; t--)
     {
      double feature[];
      if(!BuildBarFeature(open, high, low, close, t, avgRange, feature))
         return false;

      const int row = (seqLen - 1) - t;
      for(int f = 0; f < LSTM_FEAT; f++)
         input[row][f] = feature[f];
     }

   return true;
  }

void ApplyLstmProbabilities(const double logitUp, const double logitDown,
                            double &probUp, double &probDown, int &direction)
  {
   probUp = 0.5;
   probDown = 0.5;
   direction = 0;

   const double maxLogit = MathMax(logitUp, logitDown);
   const double expUp = MathExp(logitUp - maxLogit);
   const double expDown = MathExp(logitDown - maxLogit);
   const double denom = expUp + expDown;
   if(denom <= 0.0)
      return;

   probUp = expUp / denom;
   probDown = expDown / denom;

   if(probUp - probDown > 0.03)
      direction = 1;
   else if(probDown - probUp > 0.03)
      direction = -1;
  }

bool RunLstmPredictorOnnx(const double &open[], const double &high[], const double &low[], const double &close[],
                          double &probUp, double &probDown, int &direction)
  {
   probUp = 0.5;
   probDown = 0.5;
   direction = 0;

   if(!g_onnxReady || g_onnxHandle == INVALID_HANDLE)
      return false;

   matrix input;
   if(!FillLstmInputMatrix(open, high, low, close, input))
      return false;

   matrix output;
   ResetLastError();
   if(!OnnxRun(g_onnxHandle, ONNX_NO_CONVERSION, input, output))
     {
      Print(L("ONNX Run thất bại: ", "ONNX run failed: "), GetLastError());
      return false;
     }

   if(output.Rows() < 1 || output.Cols() < 2)
     {
      Print(L("ONNX output không hợp lệ.", "Invalid ONNX output shape."));
      return false;
     }

   ApplyLstmProbabilities(output[0][0], output[0][1], probUp, probDown, direction);
   return true;
  }

bool RunLstmPredictor(const double &open[], const double &high[], const double &low[], const double &close[],
                      double &probUp, double &probDown, int &direction)
  {
   if(g_onnxReady && RunLstmPredictorOnnx(open, high, low, close, probUp, probDown, direction))
      return true;

   return RunLstmPredictorNative(open, high, low, close, probUp, probDown, direction);
  }

bool LoadOnnxModel()
  {
   g_onnxReady = false;
   g_lstmBackend = L("nhúng", "embedded");

   if(g_onnxHandle != INVALID_HANDLE)
     {
      OnnxRelease(g_onnxHandle);
      g_onnxHandle = INVALID_HANDLE;
     }

   if(!InpUseOnnxModel || StringLen(InpOnnxModelFile) == 0)
      return false;

   ResetLastError();
   g_onnxHandle = OnnxCreate(InpOnnxModelFile, ONNX_DEFAULT);
   if(g_onnxHandle == INVALID_HANDLE)
     {
      Print(L("Không mở được ONNX: ", "Cannot open ONNX: "), InpOnnxModelFile,
            L(" | lỗi ", " | error "), GetLastError());
      return false;
     }

   long shape[];
   ArrayResize(shape, 3);
   shape[0] = 1;
   shape[1] = InpLstmSequence;
   shape[2] = LSTM_FEAT;
   if(!OnnxSetInputShape(g_onnxHandle, 0, shape))
     {
      Print(L("OnnxSetInputShape thất bại: ", "OnnxSetInputShape failed: "), GetLastError());
      OnnxRelease(g_onnxHandle);
      g_onnxHandle = INVALID_HANDLE;
      return false;
     }

   g_onnxReady = true;
   g_lstmBackend = "ONNX";
   Print(L("Đã nạp ONNX LSTM: ", "Loaded ONNX LSTM: "), InpOnnxModelFile);
   return true;
  }

int DetectDoji(const double &open[], const double &high[], const double &low[], const double &close[], const int shift)
  {
   const double range = MathMax(high[shift] - low[shift], _Point);
   const double body = MathAbs(close[shift] - open[shift]);
   if(body / range <= 0.1)
      return 0;
   return 0;
  }

int DetectHammer(const double &open[], const double &high[], const double &low[], const double &close[], const int shift)
  {
   const double range = MathMax(high[shift] - low[shift], _Point);
   const double body = MathAbs(close[shift] - open[shift]);
   const double lower = MathMin(open[shift], close[shift]) - low[shift];
   const double upper = high[shift] - MathMax(open[shift], close[shift]);
   if(body / range <= 0.35 && lower >= body * 2.0 && upper <= body)
      return 100;
   return 0;
  }

int DetectInvertedHammer(const double &open[], const double &high[], const double &low[], const double &close[], const int shift)
  {
   const double range = MathMax(high[shift] - low[shift], _Point);
   const double body = MathAbs(close[shift] - open[shift]);
   const double lower = MathMin(open[shift], close[shift]) - low[shift];
   const double upper = high[shift] - MathMax(open[shift], close[shift]);
   if(body / range <= 0.35 && upper >= body * 2.0 && lower <= body)
      return 100;
   return 0;
  }

int DetectEngulfing(const double &open[], const double &high[], const double &low[], const double &close[], const int shift)
  {
   if(shift + 1 >= ArraySize(close))
      return 0;

   const double body0 = close[shift] - open[shift];
   const double body1 = close[shift + 1] - open[shift + 1];
   const double body0Abs = MathAbs(body0);
   const double body1Abs = MathAbs(body1);

   if(body0 > 0.0 && body1 < 0.0 &&
      open[shift] <= close[shift + 1] && close[shift] >= open[shift + 1] &&
      body0Abs > body1Abs)
      return 100;

   if(body0 < 0.0 && body1 > 0.0 &&
      open[shift] >= close[shift + 1] && close[shift] <= open[shift + 1] &&
      body0Abs > body1Abs)
      return -100;

   return 0;
  }

int DetectMorningStar(const double &open[], const double &high[], const double &low[], const double &close[], const int shift)
  {
   if(shift + 2 >= ArraySize(close))
      return 0;

   const double range1 = MathMax(high[shift + 2] - low[shift + 2], _Point);
   const double body1 = close[shift + 2] - open[shift + 2];
   const double range2 = MathMax(high[shift + 1] - low[shift + 1], _Point);
   const double body2 = close[shift + 1] - open[shift + 1];
   const double body3 = close[shift] - open[shift];

   if(body1 < 0.0 && MathAbs(body1) / range1 >= 0.5 &&
      MathAbs(body2) / range2 <= 0.35 &&
      body3 > 0.0 && close[shift] > (open[shift + 2] + close[shift + 2]) * 0.5)
      return 100;

   return 0;
  }

int DetectEveningStar(const double &open[], const double &high[], const double &low[], const double &close[], const int shift)
  {
   if(shift + 2 >= ArraySize(close))
      return 0;

   const double range1 = MathMax(high[shift + 2] - low[shift + 2], _Point);
   const double body1 = close[shift + 2] - open[shift + 2];
   const double range2 = MathMax(high[shift + 1] - low[shift + 1], _Point);
   const double body2 = close[shift + 1] - open[shift + 1];
   const double body3 = close[shift] - open[shift];

   if(body1 > 0.0 && body1 / range1 >= 0.5 &&
      MathAbs(body2) / range2 <= 0.35 &&
      body3 < 0.0 && close[shift] < (open[shift + 2] + close[shift + 2]) * 0.5)
      return -100;

   return 0;
  }

int DetectShootingStar(const double &open[], const double &high[], const double &low[], const double &close[], const int shift)
  {
   const double range = MathMax(high[shift] - low[shift], _Point);
   const double body = MathAbs(close[shift] - open[shift]);
   const double lower = MathMin(open[shift], close[shift]) - low[shift];
   const double upper = high[shift] - MathMax(open[shift], close[shift]);
   if(body / range <= 0.35 && upper >= body * 2.0 && lower <= body * 0.5)
      return -100;
   return 0;
  }

int DetectHangingMan(const double &open[], const double &high[], const double &low[], const double &close[], const int shift)
  {
   const double range = MathMax(high[shift] - low[shift], _Point);
   const double body = MathAbs(close[shift] - open[shift]);
   const double lower = MathMin(open[shift], close[shift]) - low[shift];
   const double upper = high[shift] - MathMax(open[shift], close[shift]);
   if(close[shift] < open[shift] && body / range <= 0.35 && lower >= body * 2.0 && upper <= body)
      return -100;
   return 0;
  }

int ScanTaLibPatterns(const double &open[], const double &high[], const double &low[], const double &close[],
                      string &patternName, int &patternSignal)
  {
   patternName = "";
   patternSignal = 0;

   struct PatternRule
     {
      string name;
      int signal;
     };

   PatternRule rules[];
   ArrayResize(rules, 8);

   rules[0].name = "CDLDOJI";
   rules[0].signal = DetectDoji(open, high, low, close, 0);
   rules[1].name = "CDLHAMMER";
   rules[1].signal = DetectHammer(open, high, low, close, 0);
   rules[2].name = "CDLINVERTEDHAMMER";
   rules[2].signal = DetectInvertedHammer(open, high, low, close, 0);
   rules[3].name = "CDLENGULFING";
   rules[3].signal = DetectEngulfing(open, high, low, close, 0);
   rules[4].name = "CDLMORNINGSTAR";
   rules[4].signal = DetectMorningStar(open, high, low, close, 0);
   rules[5].name = "CDLEVENINGSTAR";
   rules[5].signal = DetectEveningStar(open, high, low, close, 0);
   rules[6].name = "CDLSHOOTINGSTAR";
   rules[6].signal = DetectShootingStar(open, high, low, close, 0);
   rules[7].name = "CDLHANGINGMAN";
   rules[7].signal = DetectHangingMan(open, high, low, close, 0);

   int bestAbs = 0;
   for(int i = 0; i < ArraySize(rules); i++)
     {
      const int absSignal = MathAbs(rules[i].signal);
      if(absSignal > bestAbs)
        {
         bestAbs = absSignal;
         patternName = rules[i].name;
         patternSignal = rules[i].signal;
        }
     }

   if(bestAbs == 0)
     {
      patternName = "NONE";
      patternSignal = 0;
     }

   return patternSignal;
  }

double FindSupportLevel(const double &low[])
  {
   const double zone = InpSrZonePips * PipSize();
   double bestLevel = 0.0;
   int bestTouches = 0;

   for(int i = 2; i < ArraySize(low) - 2; i++)
     {
      if(low[i] > low[i - 1] || low[i] > low[i - 2] || low[i] > low[i + 1] || low[i] > low[i + 2])
         continue;

      int touches = 0;
      for(int j = 0; j < ArraySize(low); j++)
        {
         if(MathAbs(low[j] - low[i]) <= zone)
            touches++;
        }

      if(touches > bestTouches)
        {
         bestTouches = touches;
         bestLevel = low[i];
        }
     }

   if(bestTouches < InpSrMinTouches)
      return 0.0;

   return bestLevel;
  }

double FindResistanceLevel(const double &high[])
  {
   const double zone = InpSrZonePips * PipSize();
   double bestLevel = 0.0;
   int bestTouches = 0;

   for(int i = 2; i < ArraySize(high) - 2; i++)
     {
      if(high[i] < high[i - 1] || high[i] < high[i - 2] || high[i] < high[i + 1] || high[i] < high[i + 2])
         continue;

      int touches = 0;
      for(int j = 0; j < ArraySize(high); j++)
        {
         if(MathAbs(high[j] - high[i]) <= zone)
            touches++;
        }

      if(touches > bestTouches)
        {
         bestTouches = touches;
         bestLevel = high[i];
        }
     }

   if(bestTouches < InpSrMinTouches)
      return 0.0;

   return bestLevel;
  }

bool NearLevel(const double price, const double level)
  {
   if(level <= 0.0)
      return false;
   return (MathAbs(price - level) <= InpSrTouchPips * PipSize());
  }

string TrendLabel(const int direction)
  {
   if(direction > 0)
      return L("⬆️", "⬆️");
   if(direction < 0)
      return L("⬇️", "⬇️");
   return L("=", "=");
  }

string PatternBiasLabel(const int patternSignal)
  {
   if(patternSignal > 0)
      return L("đảo chiều tăng", "bullish reversal");
   if(patternSignal < 0)
      return L("đảo chiều giảm", "bearish reversal");
   return L("không rõ", "unclear");
  }

int DirectionFromDelta(const double delta)
  {
   const double flatThreshold = _Point * 2.0;
   if(delta > flatThreshold)
      return 1;
   if(delta < -flatThreshold)
      return -1;
   return 0;
  }

string SignedDeltaText(const double delta)
  {
   return StringFormat("%+.5f", delta);
  }

bool IsForecastCorrect(const int priorDirection, const int actualDirection)
  {
   if(priorDirection == 0)
      return (actualDirection == 0);
   if(actualDirection == 0)
      return false;
   return (priorDirection == actualDirection);
  }

string ForecastAccuracyText()
  {
   if(g_forecastScored <= 0)
      return L("% đúng: chưa có", "Accuracy: n/a");

   const double accuracyPct = 100.0 * (double)g_forecastCorrect / (double)g_forecastScored;
   return StringFormat(L("% đúng: %.1f%% (%d/%d)", "Accuracy: %.1f%% (%d/%d)"),
                       accuracyPct, g_forecastCorrect, g_forecastScored);
  }

string PriorForecastAccuracyLabel(const bool hasPrior, const int priorDirection, const int actualDirection,
                                  const bool hasValidPrices)
  {
   if(!hasPrior || !hasValidPrices)
      return L("chưa có", "n/a");

   return IsForecastCorrect(priorDirection, actualDirection) ? L("đúng", "correct") : L("sai", "wrong");
  }

void AppendCsvLine(const string line)
  {
   if(!InpWriteCsv)
      return;

   int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ;
   int handle = FileOpen(InpCsvFileName, flags, ',');
   if(handle == INVALID_HANDLE)
     {
      Print(L("Không ghi được CSV: ", "Cannot write CSV: "), InpCsvFileName);
      return;
     }

   if(!g_csvHeaderWritten && FileSize(handle) == 0)
     {
      FileWrite(handle, "time", "symbol", "period", "current_price", "prev_price", "actual_move", "prior_forecast",
                "prior_result", "accuracy_pct", "accuracy_correct", "accuracy_total", "lstm_up", "lstm_down",
                "lstm_trend", "pattern", "pattern_signal", "support", "resistance", "sr_context", "final_trend", "note");
      g_csvHeaderWritten = true;
     }

   FileSeek(handle, 0, SEEK_END);
   FileWriteString(handle, line + "\r\n");
   FileClose(handle);
  }

void LogHybridPrediction()
  {
   const int barsNeeded = MathMax(InpLookbackBars, InpLstmSequence) + 5;
   double open[], high[], low[], close[];
   if(!CopyOhlcSeries(barsNeeded, open, high, low, close))
     {
      Print(L("Lỗi copy OHLC.", "Failed to copy OHLC."));
      return;
     }

   double probUp = 0.5;
   double probDown = 0.5;
   int lstmDirection = 0;
   if(!RunLstmPredictor(open, high, low, close, probUp, probDown, lstmDirection))
     {
      Print(L("LSTM chưa đủ dữ liệu.", "LSTM needs more bars."));
      return;
     }

   string patternName;
   int patternSignal;
   ScanTaLibPatterns(open, high, low, close, patternName, patternSignal);

   const double support = FindSupportLevel(low);
   const double resistance = FindResistanceLevel(high);
   const double price = close[0];
   const double currentPrice = CurrentMarketPrice(close[0]);
   const double priorPrice = g_prevLogPrice;
   const double priceDelta = (g_hasPriorPrediction && priorPrice > 0.0) ? (currentPrice - priorPrice) : 0.0;
   const int actualDirection = (g_hasPriorPrediction && priorPrice > 0.0) ? DirectionFromDelta(priceDelta) : 0;
   const string priorForecastLabel = g_hasPriorPrediction ? TrendLabel(g_prevPredictionDirection) : L("chưa có", "n/a");
   const bool hasValidPrices = (currentPrice > 0.0 && (!g_hasPriorPrediction || priorPrice > 0.0));
   const string priorResultLabel = PriorForecastAccuracyLabel(g_hasPriorPrediction, g_prevPredictionDirection,
                                                               actualDirection, hasValidPrices);

   if(g_hasPriorPrediction && hasValidPrices)
     {
      g_forecastScored++;
      if(IsForecastCorrect(g_prevPredictionDirection, actualDirection))
         g_forecastCorrect++;
     }

   const string accuracyText = ForecastAccuracyText();

   bool atSupport = NearLevel(price, support) || NearLevel(low[0], support);
   bool atResistance = NearLevel(price, resistance) || NearLevel(high[0], resistance);

   string srContext = L("giữa vùng", "mid-range");
   int taConfirm = 0;

   if(atSupport && patternSignal > 0)
     {
      taConfirm = 1;
      srContext = L("mô hình tăng tại hỗ trợ", "bullish pattern at support");
     }
   else if(atResistance && patternSignal < 0)
     {
      taConfirm = -1;
      srContext = L("mô hình giảm tại kháng cự", "bearish pattern at resistance");
     }
   else if(atSupport)
      srContext = L("gần hỗ trợ", "near support");
   else if(atResistance)
      srContext = L("gần kháng cự", "near resistance");

   int finalDirection = lstmDirection;
   string note = L("LSTM dẫn xu hướng", "LSTM-led trend");

   if(taConfirm != 0)
     {
      if(lstmDirection == 0 || lstmDirection == taConfirm)
        {
         finalDirection = taConfirm;
         note = L("LSTM + TA-Lib đồng thuận tại S/R", "LSTM + TA-Lib agree at S/R");
        }
      else
        {
         finalDirection = taConfirm;
         note = L("TA-Lib tại S/R ghi đè khi LSTM mâu thuẫn", "TA-Lib at S/R overrides conflicting LSTM");
        }
     }
   else if(patternSignal != 0 && lstmDirection == 0)
     {
      finalDirection = (patternSignal > 0) ? 1 : -1;
      note = L("Chỉ tín hiệu nến", "Candle pattern only");
     }

   string priceMoveText;
   if(g_hasPriorPrediction && priorPrice > 0.0)
      priceMoveText = StringFormat(L("Δ %s ⇢ %s", "Δ %s ⇢ %s"),
                                   SignedDeltaText(priceDelta), TrendLabel(actualDirection));
   else
      priceMoveText = L("chưa có giá tham chiếu", "no reference price yet");

   const string msg =
      StringFormat(L("Giá: %.5f (%s) | ", "Price: %.5f (%s) | "),
                   currentPrice, TrendLabel(actualDirection)) +
      StringFormat(L("Δ: %s | ", "Δ: %s | "), priceMoveText) +
      StringFormat(L("Dự đoán: %s | ", "Forecast: %s | "), TrendLabel(finalDirection)) +
      StringFormat(L("Dự đoán trước: %s (%s) | ", "Prior forecast: %s (%s) | "),
                   priorForecastLabel, priorResultLabel) +
      accuracyText + " | " +
      StringFormat(L("TA-Lib: %s (%s) | ", "TA-Lib: %s (%s) | "),
                   patternName, PatternBiasLabel(patternSignal)) +
      StringFormat(L("S: %.5f R: %.5f | ", "S: %.5f R: %.5f | "), support, resistance) +
      srContext + " | " +
      StringFormat(L("LSTM[%s]: %s (%.1f%% tăng / %.1f%% giảm) | ", "LSTM[%s]: %s (%.1f%% up / %.1f%% down) | "),
                   g_lstmBackend, TrendLabel(lstmDirection), probUp * 100.0, probDown * 100.0) +
      note;

   Print(msg);

   if(InpWriteCsv)
     {
      const double accuracyPct = (g_forecastScored > 0)
                                 ? (100.0 * (double)g_forecastCorrect / (double)g_forecastScored)
                                 : 0.0;
      const string csv = StringFormat("%s,%s,%s,%.5f,%.5f,%s,%s,%s,%.2f,%d,%d,%.6f,%.6f,%s,%s,%d,%.5f,%.5f,%s,%s,%s",
                                      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                                      _Symbol,
                                      EnumToString(_Period),
                                      currentPrice,
                                      priorPrice,
                                      TrendLabel(actualDirection),
                                      priorForecastLabel,
                                      priorResultLabel,
                                      accuracyPct,
                                      g_forecastCorrect,
                                      g_forecastScored,
                                      probUp,
                                      probDown,
                                      TrendLabel(lstmDirection),
                                      patternName,
                                      patternSignal,
                                      support,
                                      resistance,
                                      srContext,
                                      TrendLabel(finalDirection),
                                      note);
      AppendCsvLine(csv);
     }

   g_prevLogPrice = currentPrice;
   g_prevPredictionDirection = finalDirection;
   g_hasPriorPrediction = (currentPrice > 0.0);
  }

bool ShouldLogNow(const bool isNewBar)
  {
   if(InpLogEveryBar && isNewBar)
      return true;

   if(InpLogIntervalSeconds <= 0)
      return false;

   const datetime now = TimeCurrent();
   if(now - g_lastLogTime >= InpLogIntervalSeconds)
     {
      g_lastLogTime = now;
      return true;
     }

   return false;
  }

int OnInit()
  {
   if(InpLstmSequence < 12)
     {
      Print(L("InpLstmSequence tối thiểu 12.", "InpLstmSequence must be at least 12."));
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpLstmHidden < 4)
     {
      Print(L("InpLstmHidden tối thiểu 4.", "InpLstmHidden must be at least 4."));
      return INIT_PARAMETERS_INCORRECT;
     }

   InitLstmWeights();
   LoadOnnxModel();
   g_lastBarTime = iTime(_Symbol, _Period, 0);
   g_lastLogTime = 0;
   g_csvHeaderWritten = false;
   g_hasPriorPrediction = false;
   g_prevLogPrice = 0.0;
   g_prevPredictionDirection = 0;
   g_forecastScored = 0;
   g_forecastCorrect = 0;

   Print(L("Hybrid LSTM + TA-Lib khởi động. Chỉ log dự đoán, không giao dịch.",
           "Hybrid LSTM + TA-Lib started. Prediction logging only, no trading."));
   LogHybridPrediction();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_onnxHandle != INVALID_HANDLE)
     {
      OnnxRelease(g_onnxHandle);
      g_onnxHandle = INVALID_HANDLE;
     }

   Print(L("Hybrid LSTM + TA-Lib dừng.", "Hybrid LSTM + TA-Lib stopped."));
  }

void OnTick()
  {
   const datetime barTime = iTime(_Symbol, _Period, 0);
   const bool isNewBar = (barTime != g_lastBarTime);
   if(isNewBar)
      g_lastBarTime = barTime;

   if(!ShouldLogNow(isNewBar))
      return;

   LogHybridPrediction();
  }
