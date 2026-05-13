//+------------------------------------------------------------------+
//| Hybrid_LSTM_TA.mq5 — LSTM chuỗi thời gian + mô hình nến TA-Lib   |
//| Chỉ log dự đoán xu hướng; không tự động gửi lệnh.                |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version "1.00"
#property description "Hybrid: LSTM suy luận trên chuỗi OHLC + mô hình nến kiểu TA-Lib tại S/R."
#property description "Log xu hướng TĂNG/GIẢM/NEUTRAL khi có nến mới."

#include "Hybrid_LSTM_TA_Signal.mqh"

int OnInit() {
    if (InpLstmSequence < 12) {
        Print(L("InpLstmSequence tối thiểu 12.", "InpLstmSequence must be at least 12."));
        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpLstmHidden < 4) {
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
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    if (g_onnxHandle != INVALID_HANDLE) {
        OnnxRelease(g_onnxHandle);
        g_onnxHandle = INVALID_HANDLE;
    }

    Print(L("Hybrid LSTM + TA-Lib dừng.", "Hybrid LSTM + TA-Lib stopped."));
}

void OnTick() {
    const datetime barTime = iTime(_Symbol, _Period, 0);
    const bool isNewBar = (barTime != g_lastBarTime);
    if (isNewBar)
        g_lastBarTime = barTime;

    if (!ShouldLogNow(isNewBar))
        return;

    LogHybridPrediction();
}
