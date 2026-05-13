//+------------------------------------------------------------------+
//| Hybrid_LSTM_TA_Signal.mqh - shared forecast (Hybrid_LSTM_TA)     |
//+------------------------------------------------------------------+
#ifndef HYBRID_LSTM_TA_SIGNAL_MQH
#define HYBRID_LSTM_TA_SIGNAL_MQH

enum ENUM_HYBRID_LANG {
    HYBRID_LANG_VI = 0,
    HYBRID_LANG_EN = 1
};

input ENUM_HYBRID_LANG InpLanguage = HYBRID_LANG_VI; //--- Ngôn ngữ thông báo log (VI/EN)

input int InpLookbackBars = 80; //--- Số nến OHLC tải về để quét hỗ trợ/kháng cự và mô hình nến

input int InpLstmSequence = 48; //--- Độ dài chuỗi đầu vào LSTM (số nến liên tiếp); phải khớp mô hình ONNX nếu bật ONNX

input int InpLstmHidden = 12; //--- Số neuron ẩn của LSTM nhúng (chỉ dùng khi không chạy ONNX)

input double InpSrTouchPips = 15.0; //--- Ngưỡng pip: giá cách mức S/R trong phạm vi này được coi là “gần” mức

input int InpSrMinTouches = 2; //--- Số lần chạm tối thiểu để chấp nhận một mức hỗ trợ hoặc kháng cự

input double InpSrZonePips = 8.0; //--- Bán kính vùng (pip) gom các đáy/đỉnh cùng một mức S/R

input bool InpLogEveryBar = true; //--- Bật log dự đoán mỗi khi hình thành nến mới

input int InpLogIntervalSeconds = 0; //--- Chu kỳ log theo giây (0 = không quét theo giây, chỉ theo nến mới nếu bật InpLogEveryBar)

input bool InpWriteCsv = false; //--- Ghi thêm dự đoán ra file CSV trong thư mục MQL5/Files

input string InpCsvFileName = "hybrid_lstm_ta_log.csv"; //--- Tên file CSV khi bật InpWriteCsv

input string InpOnnxSettings = "=== ONNX LSTM ==="; //--- Nhãn phân nhóm tham số ONNX (không ảnh hưởng logic)

input bool InpUseOnnxModel = false; //--- Bật suy luận LSTM từ file ONNX theo symbol/khung thời gian; tắt thì dùng LSTM nhúng

#define LSTM_FEAT 5
#define ONNX_MODEL_PREFIX "hybrid_lstm_"
#define ONNX_MODEL_SUFFIX ".onnx"

struct SOnnxProfile {
    string symbolKey;
    ENUM_TIMEFRAMES period;
    string fileName;
};

string L(const string textVi, const string textEn) {
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
string g_activeOnnxFile = "";
SOnnxProfile g_onnxProfiles[];

double g_Wf[], g_Wi[], g_Wo[], g_Wg[];
double g_Uf[], g_Ui[], g_Uo[], g_Ug[];
double g_bf[], g_bi[], g_bo[], g_bg[];
double g_Wy[], g_by[];

double PipSize() {
    const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if (digits == 3 || digits == 5)
        return point * 10.0;
    return point;
}

double CurrentMarketPrice(const double closeFallback) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (bid > 0.0)
        return bid;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if (ask > 0.0)
        return ask;

    double last = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
    if (last > 0.0)
        return last;

    MqlTick tick;
    if (SymbolInfoTick(_Symbol, tick)) {
        if (tick.bid > 0.0)
            return tick.bid;
        if (tick.ask > 0.0)
            return tick.ask;
        if (tick.last > 0.0)
            return tick.last;
    }

    if (closeFallback > 0.0)
        return closeFallback;

    return iClose(_Symbol, _Period, 0);
}

double Sigmoid(const double x) {
    if (x > 20.0)
        return 1.0;
    if (x < -20.0)
        return 0.0;
    return 1.0 / (1.0 + MathExp(-x));
}

double Tanh(const double x) {
    if (x > 20.0)
        return 1.0;
    if (x < -20.0)
        return -1.0;
    return MathTanh(x);
}

int WeightIndex(const int row, const int col, const int cols) {
    return row * cols + col;
}

void InitLstmWeights() {
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

    for (int i = 0; i < gateCount; i++) {
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

    for (int i = 0; i < hidden; i++) {
        g_bf[i] = 0.01;
        g_bi[i] = 0.01;
        g_bo[i] = 0.01;
        g_bg[i] = 0.01;
    }

    for (int i = 0; i < outCount; i++)
        g_Wy[i] = 0.05 * MathCos((i + 1) * 0.211);

    g_by[0] = 0.02;
    g_by[1] = -0.02;
}

int RequiredHistoryBars() {
    return MathMax(InpLookbackBars, InpLstmSequence) + 5;
}

bool HasEnoughHistory() {
    return (Bars(_Symbol, _Period) >= RequiredHistoryBars());
}

bool CopyOhlcSeries(const int count, double& open[], double& high[], double& low[], double& close[]) {
    if (count <= 0)
        return false;

    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);

    if (CopyOpen(_Symbol, _Period, 0, count, open) < count)
        return false;
    if (CopyHigh(_Symbol, _Period, 0, count, high) < count)
        return false;
    if (CopyLow(_Symbol, _Period, 0, count, low) < count)
        return false;
    if (CopyClose(_Symbol, _Period, 0, count, close) < count)
        return false;

    return true;
}

double AverageRange(const double& high[], const double& low[], const int start, const int length) {
    double sum = 0.0;
    for (int i = start; i < start + length; i++)
        sum += MathMax(high[i] - low[i], _Point);
    return sum / (double)length;
}

bool BuildBarFeature(const double& open[], const double& high[], const double& low[], const double& close[],
                     const int shift, const double avgRange, double& feature[]) {
    if (shift + 1 >= ArraySize(close))
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

void LstmGateVector(const double& gateW[], const double& gateU[], double& bias[],
                    const double& hiddenState[], const double& inputVec[],
                    double& gateOut[]) {
    const int hidden = InpLstmHidden;
    const int inputSize = LSTM_FEAT;
    ArrayResize(gateOut, hidden);

    for (int j = 0; j < hidden; j++) {
        double sum = bias[j];
        for (int k = 0; k < hidden; k++)
            sum += gateW[WeightIndex(j, k, hidden + inputSize)] * hiddenState[k];
        for (int k = 0; k < inputSize; k++)
            sum += gateU[WeightIndex(j, k, hidden + inputSize)] * inputVec[k];
        gateOut[j] = sum;
    }
}

bool RunLstmPredictorNative(const double& open[], const double& high[], const double& low[], const double& close[],
                            double& probUp, double& probDown, int& direction) {
    probUp = 0.5;
    probDown = 0.5;
    direction = 0;

    const int seqLen = InpLstmSequence;
    if (ArraySize(close) < seqLen + 2)
        return false;

    const double avgRange = AverageRange(high, low, 0, MathMin(20, ArraySize(close) - 1));
    double hiddenState[];
    double cellState[];
    ArrayResize(hiddenState, InpLstmHidden);
    ArrayResize(cellState, InpLstmHidden);
    ArrayInitialize(hiddenState, 0.0);
    ArrayInitialize(cellState, 0.0);

    for (int t = seqLen - 1; t >= 0; t--) {
        double feature[];
        if (!BuildBarFeature(open, high, low, close, t, avgRange, feature))
            return false;

        double gateF[], gateI[], gateO[], gateG[];
        LstmGateVector(g_Wf, g_Uf, g_bf, hiddenState, feature, gateF);
        LstmGateVector(g_Wi, g_Ui, g_bi, hiddenState, feature, gateI);
        LstmGateVector(g_Wo, g_Uo, g_bo, hiddenState, feature, gateO);
        LstmGateVector(g_Wg, g_Ug, g_bg, hiddenState, feature, gateG);

        for (int j = 0; j < InpLstmHidden; j++) {
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
    for (int j = 0; j < InpLstmHidden; j++) {
        logits[0] += g_Wy[WeightIndex(0, j, InpLstmHidden)] * hiddenState[j];
        logits[1] += g_Wy[WeightIndex(1, j, InpLstmHidden)] * hiddenState[j];
    }

    const double maxLogit = MathMax(logits[0], logits[1]);
    const double expUp = MathExp(logits[0] - maxLogit);
    const double expDown = MathExp(logits[1] - maxLogit);
    const double denom = expUp + expDown;
    if (denom <= 0.0)
        return false;

    probUp = expUp / denom;
    probDown = expDown / denom;

    if (probUp - probDown > 0.03)
        direction = 1;
    else if (probDown - probUp > 0.03)
        direction = -1;
    else
        direction = 0;

    return true;
}

bool FillLstmInputMatrix(const double& open[], const double& high[], const double& low[], const double& close[],
                         matrixf& inputMatrix) {
    const int seqLen = InpLstmSequence;
    if (ArraySize(close) < seqLen + 2)
        return false;

    if (!inputMatrix.Resize(seqLen, LSTM_FEAT))
        return false;

    const double avgRange = AverageRange(high, low, 0, MathMin(20, ArraySize(close) - 1));
    for (int t = seqLen - 1; t >= 0; t--) {
        double feature[];
        if (!BuildBarFeature(open, high, low, close, t, avgRange, feature))
            return false;

        const int row = (seqLen - 1) - t;
        for (int f = 0; f < LSTM_FEAT; f++)
            inputMatrix[row][f] = (float)feature[f];
    }

    return true;
}

void ApplyLstmProbabilities(const double logitUp, const double logitDown,
                            double& probUp, double& probDown, int& direction) {
    probUp = 0.5;
    probDown = 0.5;
    direction = 0;

    const double maxLogit = MathMax(logitUp, logitDown);
    const double expUp = MathExp(logitUp - maxLogit);
    const double expDown = MathExp(logitDown - maxLogit);
    const double denom = expUp + expDown;
    if (denom <= 0.0)
        return;

    probUp = expUp / denom;
    probDown = expDown / denom;

    if (probUp - probDown > 0.03)
        direction = 1;
    else if (probDown - probUp > 0.03)
        direction = -1;
}

bool RunLstmPredictorOnnx(const double& open[], const double& high[], const double& low[], const double& close[],
                          double& probUp, double& probDown, int& direction) {
    probUp = 0.5;
    probDown = 0.5;
    direction = 0;

    if (!g_onnxReady || g_onnxHandle == INVALID_HANDLE)
        return false;

    matrixf inputMatrix(InpLstmSequence, LSTM_FEAT);
    if (!FillLstmInputMatrix(open, high, low, close, inputMatrix))
        return false;

    vectorf outputData(2);
    ResetLastError();
    if (!OnnxRun(g_onnxHandle, ONNX_NO_CONVERSION, inputMatrix, outputData)) {
        Print(L("ONNX Run thất bại: ", "ONNX run failed: "), GetLastError());
        return false;
    }

    if (outputData.Size() < 2) {
        Print(L("ONNX output không hợp lệ.", "Invalid ONNX output shape."));
        return false;
    }

    ApplyLstmProbabilities(outputData[0], outputData[1], probUp, probDown, direction);
    return true;
}

bool RunLstmPredictor(const double& open[], const double& high[], const double& low[], const double& close[],
                      double& probUp, double& probDown, int& direction) {
    if (InpUseOnnxModel) {
        if (!g_onnxReady)
            return false;
        return RunLstmPredictorOnnx(open, high, low, close, probUp, probDown, direction);
    }

    return RunLstmPredictorNative(open, high, low, close, probUp, probDown, direction);
}

string NormalizeSymbolKey(const string symbol) {
    string key = symbol;
    StringReplace(key, ".", "");
    StringToUpper(key);

    while (StringLen(key) > 0) {
        const ushort lastChar = StringGetCharacter(key, StringLen(key) - 1);
        if (lastChar >= 'A' && lastChar <= 'Z')
            break;
        key = StringSubstr(key, 0, StringLen(key) - 1);
    }

    return key;
}

bool ParseOnnxTimeframeTag(const string tfTag, ENUM_TIMEFRAMES& period) {
    string tag = tfTag;
    StringToLower(tag);

    if (tag == "m1") {
        period = PERIOD_M1;
        return true;
    }
    if (tag == "m5") {
        period = PERIOD_M5;
        return true;
    }
    if (tag == "m15") {
        period = PERIOD_M15;
        return true;
    }
    if (tag == "m30") {
        period = PERIOD_M30;
        return true;
    }
    if (tag == "h1") {
        period = PERIOD_H1;
        return true;
    }
    if (tag == "h4") {
        period = PERIOD_H4;
        return true;
    }
    if (tag == "d1") {
        period = PERIOD_D1;
        return true;
    }

    return false;
}

int LastUnderscorePos(const string text) {
    int pos = -1;
    for (int i = 0; i < StringLen(text); i++) {
        if (StringGetCharacter(text, i) == '_')
            pos = i;
    }
    return pos;
}

bool ParseOnnxModelFileName(const string fileName, string& symbolKey, ENUM_TIMEFRAMES& period) {
    const int prefixLen = StringLen(ONNX_MODEL_PREFIX);
    const int suffixLen = StringLen(ONNX_MODEL_SUFFIX);
    if (StringFind(fileName, ONNX_MODEL_PREFIX) != 0)
        return false;
    if (StringLen(fileName) <= prefixLen + suffixLen + 2)
        return false;
    if (StringFind(fileName, ONNX_MODEL_SUFFIX, StringLen(fileName) - suffixLen) < 0)
        return false;

    const string core = StringSubstr(fileName, prefixLen, StringLen(fileName) - prefixLen - suffixLen);
    const int lastUnderscore = LastUnderscorePos(core);
    if (lastUnderscore <= 0 || lastUnderscore >= StringLen(core) - 1)
        return false;

    symbolKey = StringSubstr(core, 0, lastUnderscore);
    const string tfTag = StringSubstr(core, lastUnderscore + 1);
    StringToUpper(symbolKey);
    return ParseOnnxTimeframeTag(tfTag, period);
}

int FindOnnxProfileIndex(const string symbolKey, const ENUM_TIMEFRAMES period) {
    for (int i = 0; i < ArraySize(g_onnxProfiles); i++) {
        if (g_onnxProfiles[i].period == period && g_onnxProfiles[i].symbolKey == symbolKey)
            return i;
    }
    return -1;
}

void UpsertOnnxProfile(const string symbolKey, const ENUM_TIMEFRAMES period, const string fileName) {
    const int existing = FindOnnxProfileIndex(symbolKey, period);
    if (existing >= 0) {
        g_onnxProfiles[existing].fileName = fileName;
        return;
    }

    const int index = ArraySize(g_onnxProfiles);
    ArrayResize(g_onnxProfiles, index + 1);
    g_onnxProfiles[index].symbolKey = symbolKey;
    g_onnxProfiles[index].period = period;
    g_onnxProfiles[index].fileName = fileName;
}

void InitOnnxProfileCatalog() {
    ArrayResize(g_onnxProfiles, 0);
    UpsertOnnxProfile("XAUUSD", PERIOD_M1, "hybrid_lstm_xauusd_m1.onnx");

    string fileName;
    long searchHandle = FileFindFirst(ONNX_MODEL_PREFIX + "*" + ONNX_MODEL_SUFFIX, fileName);
    if (searchHandle != INVALID_HANDLE) {
        do {
            string symbolKey;
            ENUM_TIMEFRAMES period;
            if (ParseOnnxModelFileName(fileName, symbolKey, period))
                UpsertOnnxProfile(symbolKey, period, fileName);
        } while (FileFindNext(searchHandle, fileName));
        FileFindClose(searchHandle);
    }
}

bool ResolveOnnxProfileForChart(string& modelFile, string& symbolKey, ENUM_TIMEFRAMES& period) {
    symbolKey = NormalizeSymbolKey(_Symbol);
    period = _Period;
    modelFile = "";

    int profileIndex = FindOnnxProfileIndex(symbolKey, period);

    // Chart symbol often has broker suffix (e.g. XAUUSDm → XAUUSDM) while ONNX files use base (XAUUSD).
    // NormalizeSymbolKey keeps trailing letters, so XAUUSDM no longer matches catalog key XAUUSD.
    if (profileIndex < 0) {
        int bestLen = 0;
        int bestIdx = -1;
        for (int i = 0; i < ArraySize(g_onnxProfiles); i++) {
            if (g_onnxProfiles[i].period != period)
                continue;
            const string pk = g_onnxProfiles[i].symbolKey;
            if (StringLen(pk) < 4)
                continue;
            if (StringLen(symbolKey) <= StringLen(pk))
                continue;
            if (StringFind(symbolKey, pk) != 0)
                continue;
            const string rest = StringSubstr(symbolKey, StringLen(pk));
            const int restLen = StringLen(rest);
            if (restLen < 1 || restLen > 5)
                continue;
            if (StringLen(pk) > bestLen) {
                bestLen = StringLen(pk);
                bestIdx = i;
            }
        }
        profileIndex = bestIdx;
    }

    if (profileIndex < 0)
        return false;

    modelFile = g_onnxProfiles[profileIndex].fileName;
    symbolKey = g_onnxProfiles[profileIndex].symbolKey;
    return (StringLen(modelFile) > 0);
}

void ReportOnnxCheckError(const string reasonVi, const string reasonEn) {
    Print(L("CHECK ONNX SAI: ", "ONNX CHECK FAILED: "),
          L(reasonVi, reasonEn),
          L(" | symbol=", " | symbol="), _Symbol,
          L(" | khung=", " | timeframe="), EnumToString(_Period));
}

bool LoadOnnxModel() {
    g_onnxReady = false;
    g_activeOnnxFile = "";
    g_lstmBackend = L("nhúng", "embedded");

    if (g_onnxHandle != INVALID_HANDLE) {
        OnnxRelease(g_onnxHandle);
        g_onnxHandle = INVALID_HANDLE;
    }

    if (!InpUseOnnxModel)
        return false;

    InitOnnxProfileCatalog();

    string modelFile;
    string symbolKey;
    ENUM_TIMEFRAMES modelPeriod;
    if (!ResolveOnnxProfileForChart(modelFile, symbolKey, modelPeriod)) {
        ReportOnnxCheckError(
            "không có mô hình ONNX cho cặp/khung hiện tại trong danh sách hybrid_lstm_*.onnx.",
            "no ONNX model in hybrid_lstm_*.onnx catalog for the current symbol/timeframe.");
        return false;
    }

    if (!FileIsExist(modelFile)) {
        ReportOnnxCheckError(
            "không tìm thấy file ONNX trong MQL5/Files.",
            "ONNX file was not found in MQL5/Files.");
        Print(L("File ONNX cần: ", "Expected ONNX file: "), modelFile);
        return false;
    }

    ResetLastError();
    g_onnxHandle = OnnxCreate(modelFile, ONNX_DEFAULT);
    if (g_onnxHandle == INVALID_HANDLE) {
        ReportOnnxCheckError(
            "không mở được file ONNX.",
            "cannot open the ONNX file.");
        Print(L("File ONNX: ", "ONNX file: "), modelFile,
              L(" | lỗi ", " | error "), GetLastError(),
              L(" | Nếu log báo thiếu .onnx.data, train lại để gộp 1 file .onnx hoặc copy cả .onnx.data vào MQL5\\Files.",
                " | If log mentions missing .onnx.data, retrain to a single .onnx or copy .onnx.data into MQL5\\Files."));
        return false;
    }

    long shape[];
    ArrayResize(shape, 3);
    shape[0] = 1;
    shape[1] = InpLstmSequence;
    shape[2] = LSTM_FEAT;
    if (!OnnxSetInputShape(g_onnxHandle, 0, shape)) {
        ReportOnnxCheckError(
            "OnnxSetInputShape thất bại.",
            "OnnxSetInputShape failed.");
        Print(L("File ONNX: ", "ONNX file: "), modelFile, L(" | lỗi ", " | error "), GetLastError());
        OnnxRelease(g_onnxHandle);
        g_onnxHandle = INVALID_HANDLE;
        return false;
    }

    long outputShape[];
    ArrayResize(outputShape, 2);
    outputShape[0] = 1;
    outputShape[1] = 2;
    if (!OnnxSetOutputShape(g_onnxHandle, 0, outputShape)) {
        ReportOnnxCheckError(
            "OnnxSetOutputShape thất bại.",
            "OnnxSetOutputShape failed.");
        Print(L("File ONNX: ", "ONNX file: "), modelFile, L(" | lỗi ", " | error "), GetLastError());
        OnnxRelease(g_onnxHandle);
        g_onnxHandle = INVALID_HANDLE;
        return false;
    }

    g_onnxReady = true;
    g_activeOnnxFile = modelFile;
    g_lstmBackend = "ONNX";
    Print(L("Đã nạp ONNX LSTM: ", "Loaded ONNX LSTM: "), modelFile,
          L(" | symbol=", " | symbol="), symbolKey,
          L(" | khung=", " | timeframe="), EnumToString(modelPeriod));
    return true;
}

int DetectDoji(const double& open[], const double& high[], const double& low[], const double& close[], const int shift) {
    const double range = MathMax(high[shift] - low[shift], _Point);
    const double body = MathAbs(close[shift] - open[shift]);
    if (body / range <= 0.1)
        return 0;
    return 0;
}

int DetectHammer(const double& open[], const double& high[], const double& low[], const double& close[], const int shift) {
    const double range = MathMax(high[shift] - low[shift], _Point);
    const double body = MathAbs(close[shift] - open[shift]);
    const double lower = MathMin(open[shift], close[shift]) - low[shift];
    const double upper = high[shift] - MathMax(open[shift], close[shift]);
    if (body / range <= 0.35 && lower >= body * 2.0 && upper <= body)
        return 100;
    return 0;
}

int DetectInvertedHammer(const double& open[], const double& high[], const double& low[], const double& close[], const int shift) {
    const double range = MathMax(high[shift] - low[shift], _Point);
    const double body = MathAbs(close[shift] - open[shift]);
    const double lower = MathMin(open[shift], close[shift]) - low[shift];
    const double upper = high[shift] - MathMax(open[shift], close[shift]);
    if (body / range <= 0.35 && upper >= body * 2.0 && lower <= body)
        return 100;
    return 0;
}

int DetectEngulfing(const double& open[], const double& high[], const double& low[], const double& close[], const int shift) {
    if (shift + 1 >= ArraySize(close))
        return 0;

    const double body0 = close[shift] - open[shift];
    const double body1 = close[shift + 1] - open[shift + 1];
    const double body0Abs = MathAbs(body0);
    const double body1Abs = MathAbs(body1);

    if (body0 > 0.0 && body1 < 0.0 &&
        open[shift] <= close[shift + 1] && close[shift] >= open[shift + 1] &&
        body0Abs > body1Abs)
        return 100;

    if (body0 < 0.0 && body1 > 0.0 &&
        open[shift] >= close[shift + 1] && close[shift] <= open[shift + 1] &&
        body0Abs > body1Abs)
        return -100;

    return 0;
}

int DetectMorningStar(const double& open[], const double& high[], const double& low[], const double& close[], const int shift) {
    if (shift + 2 >= ArraySize(close))
        return 0;

    const double range1 = MathMax(high[shift + 2] - low[shift + 2], _Point);
    const double body1 = close[shift + 2] - open[shift + 2];
    const double range2 = MathMax(high[shift + 1] - low[shift + 1], _Point);
    const double body2 = close[shift + 1] - open[shift + 1];
    const double body3 = close[shift] - open[shift];

    if (body1 < 0.0 && MathAbs(body1) / range1 >= 0.5 &&
        MathAbs(body2) / range2 <= 0.35 &&
        body3 > 0.0 && close[shift] > (open[shift + 2] + close[shift + 2]) * 0.5)
        return 100;

    return 0;
}

int DetectEveningStar(const double& open[], const double& high[], const double& low[], const double& close[], const int shift) {
    if (shift + 2 >= ArraySize(close))
        return 0;

    const double range1 = MathMax(high[shift + 2] - low[shift + 2], _Point);
    const double body1 = close[shift + 2] - open[shift + 2];
    const double range2 = MathMax(high[shift + 1] - low[shift + 1], _Point);
    const double body2 = close[shift + 1] - open[shift + 1];
    const double body3 = close[shift] - open[shift];

    if (body1 > 0.0 && body1 / range1 >= 0.5 &&
        MathAbs(body2) / range2 <= 0.35 &&
        body3 < 0.0 && close[shift] < (open[shift + 2] + close[shift + 2]) * 0.5)
        return -100;

    return 0;
}

int DetectShootingStar(const double& open[], const double& high[], const double& low[], const double& close[], const int shift) {
    const double range = MathMax(high[shift] - low[shift], _Point);
    const double body = MathAbs(close[shift] - open[shift]);
    const double lower = MathMin(open[shift], close[shift]) - low[shift];
    const double upper = high[shift] - MathMax(open[shift], close[shift]);
    if (body / range <= 0.35 && upper >= body * 2.0 && lower <= body * 0.5)
        return -100;
    return 0;
}

int DetectHangingMan(const double& open[], const double& high[], const double& low[], const double& close[], const int shift) {
    const double range = MathMax(high[shift] - low[shift], _Point);
    const double body = MathAbs(close[shift] - open[shift]);
    const double lower = MathMin(open[shift], close[shift]) - low[shift];
    const double upper = high[shift] - MathMax(open[shift], close[shift]);
    if (close[shift] < open[shift] && body / range <= 0.35 && lower >= body * 2.0 && upper <= body)
        return -100;
    return 0;
}

int ScanTaLibPatterns(const double& open[], const double& high[], const double& low[], const double& close[],
                      string& patternName, int& patternSignal) {
    patternName = "";
    patternSignal = 0;

    struct PatternRule {
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
    for (int i = 0; i < ArraySize(rules); i++) {
        const int absSignal = MathAbs(rules[i].signal);
        if (absSignal > bestAbs) {
            bestAbs = absSignal;
            patternName = rules[i].name;
            patternSignal = rules[i].signal;
        }
    }

    if (bestAbs == 0) {
        patternName = "NONE";
        patternSignal = 0;
    }

    return patternSignal;
}

double FindSupportLevel(const double& low[]) {
    const double zone = InpSrZonePips * PipSize();
    double bestLevel = 0.0;
    int bestTouches = 0;

    for (int i = 2; i < ArraySize(low) - 2; i++) {
        if (low[i] > low[i - 1] || low[i] > low[i - 2] || low[i] > low[i + 1] || low[i] > low[i + 2])
            continue;

        int touches = 0;
        for (int j = 0; j < ArraySize(low); j++) {
            if (MathAbs(low[j] - low[i]) <= zone)
                touches++;
        }

        if (touches > bestTouches) {
            bestTouches = touches;
            bestLevel = low[i];
        }
    }

    if (bestTouches < InpSrMinTouches)
        return 0.0;

    return bestLevel;
}

double FindResistanceLevel(const double& high[]) {
    const double zone = InpSrZonePips * PipSize();
    double bestLevel = 0.0;
    int bestTouches = 0;

    for (int i = 2; i < ArraySize(high) - 2; i++) {
        if (high[i] < high[i - 1] || high[i] < high[i - 2] || high[i] < high[i + 1] || high[i] < high[i + 2])
            continue;

        int touches = 0;
        for (int j = 0; j < ArraySize(high); j++) {
            if (MathAbs(high[j] - high[i]) <= zone)
                touches++;
        }

        if (touches > bestTouches) {
            bestTouches = touches;
            bestLevel = high[i];
        }
    }

    if (bestTouches < InpSrMinTouches)
        return 0.0;

    return bestLevel;
}

bool NearLevel(const double price, const double level) {
    if (level <= 0.0)
        return false;
    return (MathAbs(price - level) <= InpSrTouchPips * PipSize());
}

string TrendLabel(const int direction) {
    if (direction > 0)
        return L("⤴️", "⤴️");
    if (direction < 0)
        return L("⤵️", "⤵️");
    return L("🔃", "🔃");
}

string PatternBiasLabel(const int patternSignal) {
    if (patternSignal > 0)
        return L("đảo chiều tăng", "bullish reversal");
    if (patternSignal < 0)
        return L("đảo chiều giảm", "bearish reversal");
    return L("không rõ", "unclear");
}

int DirectionFromDelta(const double delta) {
    const double flatThreshold = _Point * 2.0;
    if (delta > flatThreshold)
        return 1;
    if (delta < -flatThreshold)
        return -1;
    return 0;
}

string SignedDeltaText(const double delta) {
    return StringFormat("%+.5f", delta);
}

bool IsForecastCorrect(const int priorDirection, const int actualDirection) {
    if (priorDirection == 0 || actualDirection == 0)
        return false;
    return (priorDirection == actualDirection);
}

string ForecastAccuracyText() {
    if (g_forecastScored <= 0)
        return L("% đúng: chưa có", "Accuracy: n/a");

    const double accuracyPct = 100.0 * (double)g_forecastCorrect / (double)g_forecastScored;
    return StringFormat(L("%.1f%%~%d/%d", "%.1f%%~%d/%d="),
                        accuracyPct, g_forecastCorrect, g_forecastScored);
}

string PriorForecastAccuracyLabel(const bool hasPrior, const int priorDirection, const int actualDirection,
                                  const bool hasValidPrices) {
    if (!hasPrior || !hasValidPrices || priorDirection == 0)
        return L("●", "●");

    return IsForecastCorrect(priorDirection, actualDirection) ? L("✅", "✅") : L("❌", "❌");
}

void AppendCsvLine(const string line) {
    if (!InpWriteCsv)
        return;

    int flags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ;
    int handle = FileOpen(InpCsvFileName, flags, ',');
    if (handle == INVALID_HANDLE) {
        Print(L("Không ghi được CSV: ", "Cannot write CSV: "), InpCsvFileName);
        return;
    }

    if (!g_csvHeaderWritten && FileSize(handle) == 0) {
        FileWrite(handle, "time", "symbol", "period", "current_price", "prev_price", "actual_move", "prior_forecast",
                  "prior_result", "accuracy_pct", "accuracy_correct", "accuracy_total", "lstm_up", "lstm_down",
                  "lstm_trend", "pattern", "pattern_signal", "support", "resistance", "sr_context", "final_trend", "note");
        g_csvHeaderWritten = true;
    }

    FileSeek(handle, 0, SEEK_END);
    FileWriteString(handle, line + "\r\n");
    FileClose(handle);
}

// out_final_direction: 1 = xu hướng tăng (long), -1 = giảm (short), 0 = trung lập
bool HybridSignal_FetchForecast(int& out_final_direction, double& out_prob_up, double& out_prob_down,
                                string& out_pattern_name, string& out_note, string& out_msg, const bool print_to_log) {
    out_final_direction = 0;
    out_prob_up = 0.5;
    out_prob_down = 0.5;
    out_pattern_name = "";
    out_note = "";
    out_msg = "";

    const int barsNeeded = RequiredHistoryBars();
    if (!HasEnoughHistory())
        return false;

    double open[], high[], low[], close[];
    if (!CopyOhlcSeries(barsNeeded, open, high, low, close)) {
        Print(L("Lỗi copy OHLC.", "Failed to copy OHLC."));
        return false;
    }

    double probUp = 0.5;
    double probDown = 0.5;
    int lstmDirection = 0;
    if (!RunLstmPredictor(open, high, low, close, probUp, probDown, lstmDirection)) {
        if (InpUseOnnxModel && !g_onnxReady)
            Print(L("Bỏ qua dự đoán vì ONNX chưa hợp lệ (CHECK ONNX SAI).",
                    "Skipping prediction because ONNX is invalid (ONNX CHECK FAILED)."));
        else
            Print(L("LSTM chưa đủ dữ liệu.", "LSTM needs more bars."));
        return false;
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

    if (g_hasPriorPrediction && hasValidPrices && g_prevPredictionDirection != 0) {
        g_forecastScored++;
        if (IsForecastCorrect(g_prevPredictionDirection, actualDirection))
            g_forecastCorrect++;
    }

    const string accuracyText = ForecastAccuracyText();

    bool atSupport = NearLevel(price, support) || NearLevel(low[0], support);
    bool atResistance = NearLevel(price, resistance) || NearLevel(high[0], resistance);

    string srContext = L("giữa vùng", "mid-range");
    int taConfirm = 0;

    if (atSupport && patternSignal > 0) {
        taConfirm = 1;
        srContext = L("mô hình tăng tại hỗ trợ", "bullish pattern at support");
    } else if (atResistance && patternSignal < 0) {
        taConfirm = -1;
        srContext = L("mô hình giảm tại kháng cự", "bearish pattern at resistance");
    } else if (atSupport)
        srContext = L("gần hỗ trợ", "near support");
    else if (atResistance)
        srContext = L("gần kháng cự", "near resistance");

    int finalDirection = lstmDirection;
    string note = L("LSTM dẫn xu hướng", "LSTM-led trend");

    if (taConfirm != 0) {
        if (lstmDirection == 0 || lstmDirection == taConfirm) {
            finalDirection = taConfirm;
            note = L("LSTM + TA-Lib đồng thuận tại S/R", "LSTM + TA-Lib agree at S/R");
        } else {
            finalDirection = taConfirm;
            note = L("TA-Lib tại S/R ghi đè khi LSTM mâu thuẫn", "TA-Lib at S/R overrides conflicting LSTM");
        }
    } else if (patternSignal != 0 && lstmDirection == 0) {
        finalDirection = (patternSignal > 0) ? 1 : -1;
        note = L("Chỉ tín hiệu nến", "Candle pattern only");
    }

    string priceMoveText;
    if (g_hasPriorPrediction && priorPrice > 0.0)
        priceMoveText = StringFormat(L("%s ⇢ %s", "%s ⇢ %s"),
                                     SignedDeltaText(priceDelta), TrendLabel(actualDirection));
    else
        priceMoveText = L("chưa có giá tham chiếu", "no reference price yet");

    const string msg =
        StringFormat(L("Giá: %.5f (%s) | ", "Price: %.5f (%s) | "),
                     currentPrice, TrendLabel(actualDirection)) +
        StringFormat(L("Δ: %s | ", "Δ: %s | "), priceMoveText) +
        StringFormat(L("Dự đoán: %s | ", "Forecast: %s | "), TrendLabel(finalDirection)) +
        StringFormat(L("trước đó: %s (%s) / (%s) | ", "Prior forecast: %s (%s) / (%s) | "),
                     priorForecastLabel, priorResultLabel, accuracyText) +
        StringFormat(L("TA-Lib: %s (%s) | ", "TA-Lib: %s (%s) | "),
                     patternName, PatternBiasLabel(patternSignal)) +
        StringFormat(L("S: %.5f R: %.5f | ", "S: %.5f R: %.5f | "), support, resistance) +
        srContext + " | " +
        StringFormat(L("LSTM[%s]: %s (%.1f%% tăng / %.1f%% giảm) | ", "LSTM[%s]: %s (%.1f%% up / %.1f%% down) | "),
                     g_lstmBackend, TrendLabel(lstmDirection), probUp * 100.0, probDown * 100.0) +
        note;

    out_final_direction = finalDirection;
    out_prob_up = probUp;
    out_prob_down = probDown;
    out_pattern_name = patternName;
    out_note = note;
    out_msg = msg;

    if (print_to_log)
        Print(msg);

    if (InpWriteCsv) {
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
    return true;
}

void LogHybridPrediction() {
    int fd;
    double pu, pd;
    string pn, note, msg;
    HybridSignal_FetchForecast(fd, pu, pd, pn, note, msg, true);
}

bool ShouldLogNow(const bool isNewBar) {
    if (InpLogEveryBar && isNewBar)
        return true;

    if (InpLogIntervalSeconds <= 0)
        return false;

    const datetime now = TimeCurrent();
    if (now - g_lastLogTime >= InpLogIntervalSeconds) {
        g_lastLogTime = now;
        return true;
    }

    return false;
}

#endif // HYBRID_LSTM_TA_SIGNAL_MQH
