//+------------------------------------------------------------------+
//| Hybrid_LSTM_TA_SignalBarStack.mq5                                |
//| Mỗi nến mới: đọc Hybrid_LSTM_TA_Signal → long/short theo hướng;   |
//| giữ nhiều lệnh; đóng từng lệnh khi lãi/lỗ đạt % trên giá trị vào. |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version "1.00"
#property description "Hybrid LSTM+TA: bar forecast log; TP/SL optional skip until bar after entry; scan on tick + new bar."

#include <Trade/Trade.mqh>
#include "Hybrid_LSTM_TA_Signal.mqh"

#define HST_CMT_PREFIX "HST|"

input group "=== EA ==="
input ulong InpMagic = 910029;
input int InpSlippagePoints = 30;
input bool InpCloseAllOurOnInit = true;

input group "=== Tiền vào mỗi lệnh ==="
input double InpEquityPctPerTrade = 1;

input group "=== Chốt theo % giá trị vào lệnh (tiền sizing tại mở) ==="
input double InpTakeProfitPctOfEntry = 20.0;
input double InpStopLossPctOfEntry = 20.0;
input bool InpSkipTpSlUntilNextBarAfterOpen = true;

input group "=== Log ==="
input bool InpPrintBarForecast = true;
input int InpLogMaxChunkChars = 900;
input bool InpQuietExpertsLog = false;

CTrade g_trade;

// Phải dùng biến cục bộ EA — không dùng g_lastBarTime trong Hybrid_LSTM_TA_Signal.mqh (indicator/EA khác
// cùng include có thể cập nhật trước → EA này không bao giờ thấy "nến mới" → chỉ mở lệnh khi tình cờ).
datetime g_eaLastBarTimeForStack = 0;

void PrintTextChunked(const string prefix, const string text) {
    const int maxC = InpLogMaxChunkChars;
    if (maxC <= 0 || StringLen(text) <= maxC) {
        Print(prefix, text);
        return;
    }
    string remainder = text;
    string pfx = prefix;
    while (StringLen(remainder) > 0) {
        const int total = (int)StringLen(remainder);
        int take = (total > maxC) ? maxC : total;
        if (take < total) {
            int breakAt = take;
            for (int k = take - 1; k > (take * 2) / 3 && k > 0; k--) {
                if (StringGetCharacter(remainder, k) == ' ') {
                    breakAt = k + 1;
                    break;
                }
            }
            take = breakAt;
        }
        Print(pfx, StringSubstr(remainder, 0, take));
        remainder = StringSubstr(remainder, take);
        pfx = " … ";
    }
}

double NormalizeVolumeLocal(const double vol) {
    const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    const double minv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    const double maxv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double v = MathFloor(vol / step) * step;
    return MathMax(minv, MathMin(maxv, v));
}

bool VolumeFromMoney(const ENUM_ORDER_TYPE typ, const double money, double& outVol) {
    outVol = 0.0;
    if (money <= 0.0)
        return false;
    const double price =
        (typ == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (price <= 0.0)
        return false;

    double margin1 = 0.0;
    if (OrderCalcMargin(typ, _Symbol, 1.0, price, margin1) && margin1 > 0.0) {
        outVol = NormalizeVolumeLocal(money / margin1);
    } else {
        const double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        if (cs <= 0.0)
            return false;
        outVol = NormalizeVolumeLocal(money / (cs * price));
    }

    const double minv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    return (outVol >= minv);
}

bool ParseEntryMoneyFromComment(const string cmt, double& outMoney) {
    outMoney = 0.0;
    if (StringFind(cmt, HST_CMT_PREFIX) != 0)
        return false;
    const string rest = StringSubstr(cmt, StringLen(HST_CMT_PREFIX));
    outMoney = StringToDouble(rest);
    return (outMoney > 0.0);
}

void CloseAllOurPositionsAndPendings() {
    g_trade.SetExpertMagicNumber(InpMagic);
    g_trade.SetDeviationInPoints(InpSlippagePoints);
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        g_trade.PositionClose(ticket, InpSlippagePoints);
    }
    for (int j = OrdersTotal() - 1; j >= 0; j--) {
        const ulong oticket = OrderGetTicket(j);
        if (oticket == 0 || !OrderSelect(oticket))
            continue;
        if (OrderGetString(ORDER_SYMBOL) != _Symbol)
            continue;
        if ((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic)
            continue;
        g_trade.OrderDelete(oticket);
    }
}

bool OpenMarket(const ENUM_ORDER_TYPE t, const double volume, const string comment) {
    g_trade.SetExpertMagicNumber(InpMagic);
    g_trade.SetDeviationInPoints(InpSlippagePoints);
    const int fm = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if ((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
        g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    else if ((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
        g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    else
        g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
    const bool ok =
        (t == ORDER_TYPE_BUY) ? g_trade.Buy(volume, _Symbol, 0.0, 0.0, 0.0, comment)
                              : g_trade.Sell(volume, _Symbol, 0.0, 0.0, 0.0, comment);
    if (!ok && !InpQuietExpertsLog)
        Print("OpenMarket failed: ", g_trade.ResultRetcodeDescription());
    return ok;
}

bool ExitScanAllowedForPositionByBar(const datetime positionOpenTime) {
    if (!InpSkipTpSlUntilNextBarAfterOpen)
        return true;
    const int sh = iBarShift(_Symbol, _Period, positionOpenTime, false);
    if (sh < 0)
        return true;
    return (sh > 0);
}

void ManagePerPositionExits() {
    if (InpTakeProfitPctOfEntry <= 0.0 || InpStopLossPctOfEntry <= 0.0)
        return;

    const string cur = AccountInfoString(ACCOUNT_CURRENCY);

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;

        double entryMoney = 0.0;
        const string cmt = PositionGetString(POSITION_COMMENT);
        if (!ParseEntryMoneyFromComment(cmt, entryMoney))
            continue;

        const datetime posOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
        if (!ExitScanAllowedForPositionByBar(posOpenTime))
            continue;

        const double tpMoney = entryMoney * (InpTakeProfitPctOfEntry / 100.0);
        const double slMoney = entryMoney * (InpStopLossPctOfEntry / 100.0);
        const double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

        if (pnl >= tpMoney) {
            if (!InpQuietExpertsLog)
                Print(L("Chốt lời ticket ", "Take profit ticket "), (long)ticket, " P+L=", DoubleToString(pnl, 2), " ", cur,
                      L(" ≥ ", " ≥ "), DoubleToString(tpMoney, 2), L(" (", " ("),
                      DoubleToString(InpTakeProfitPctOfEntry, 1), L("% giá trị vào).", "% entry)."));
            g_trade.PositionClose(ticket, InpSlippagePoints);
            continue;
        }
        if (pnl <= -slMoney) {
            if (!InpQuietExpertsLog)
                Print(L("Cắt lỗ ticket ", "Stop loss ticket "), (long)ticket, " P+L=", DoubleToString(pnl, 2), " ", cur,
                      L(" ≤ −", " ≤ −"), DoubleToString(slMoney, 2), L(" (", " ("),
                      DoubleToString(InpStopLossPctOfEntry, 1), L("% giá trị vào).", "% entry)."));
            g_trade.PositionClose(ticket, InpSlippagePoints);
        }
    }
}

void TryOpenFromSignalDirection(const int fd, const string pat) {
    if (fd == 0)
        return;

    const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if (equity <= 0.0) {
        Print(L("Equity ≤ 0 — không vào lệnh.", "Equity ≤ 0 — skip order."));
        return;
    }

    const double money = equity * (InpEquityPctPerTrade / 100.0);
    const ENUM_ORDER_TYPE otype = (fd > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    double vol = 0.0;
    if (!VolumeFromMoney(otype, money, vol)) {
        Print(L("Không tính được lot từ % vốn — bỏ qua.", "Cannot compute volume from equity % — skip."));
        return;
    }

    const string cmt = HST_CMT_PREFIX + DoubleToString(money, 2);
    if (StringLen(cmt) > 31) {
        Print(L("Comment quá dài — giảm precision hoặc contact broker.", "Comment too long."));
        return;
    }

    double needMargin = 0.0;
    if (!OrderCalcMargin(otype, _Symbol, vol,
                         (otype == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID),
                         needMargin))
        needMargin = 0.0;
    const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if (needMargin > 0.0 && freeMargin > 0.0 && needMargin > freeMargin * 0.98) {
        Print(L("Bỏ qua mở lệnh: margin cần (~", "Skip open: required margin (~"), DoubleToString(needMargin, 2),
              L(") > margin khả dụng (~", ") > free margin (~"), DoubleToString(freeMargin, 2),
              L("). Giảm InpEquityPctPerTrade hoặc đóng bớt lệnh.", "). Lower InpEquityPctPerTrade or close some positions."));
        return;
    }

    const bool ok = OpenMarket(otype, vol, cmt);
    if (ok && !InpQuietExpertsLog)
        Print(L("Đã mở ", "Opened "), (fd > 0 ? "LONG " : "SHORT "), "vol=", DoubleToString(vol, 2),
              L(" — tiền sizing ", " — alloc "), DoubleToString(money, 2), " ", AccountInfoString(ACCOUNT_CURRENCY),
              L(" | ", " | "), pat);
    else if (!ok)
        Print(L("Không mở thêm lệnh (kiểm tra margin / log retcode phía trên). ",
                "No new order (check margin / retcode log above). "));
}

void OnNewBarHybridStack() {
    int fd = 0;
    double pu = 0.5, pd = 0.5;
    string pat = "", note = "", msg = "";
    if (!HybridSignal_FetchForecast(fd, pu, pd, pat, note, msg, false)) {
        if (!InpQuietExpertsLog)
            Print(L("[NẾN MỚI] Chưa lấy được dự báo Hybrid (lịch sử / ONNX?).",
                    "[NEW BAR] Hybrid forecast unavailable (history / ONNX?)."));
        return;
    }

    if (InpPrintBarForecast) {
        const string barLine = L("[NẾN MỚI ", "[NEW BAR ") +
            TimeToString(iTime(_Symbol, _Period, 0), TIME_DATE | TIME_MINUTES | TIME_SECONDS) +
            L("] ", "] ");
        Print(barLine, _Symbol, " ", EnumToString(_Period));
        PrintTextChunked(L("[HYBRID] ", "[HYBRID] "), msg);
        Print(L("Pattern: ", "Pattern: "), pat, " | ", L("Ghi chú: ", "Note: "), note);
        Print(L("Hướng cuối / xác suất: ", "Final / probs: "), fd,
              " | up ", DoubleToString(pu * 100.0, 1), "% down ", DoubleToString(pd * 100.0, 1), "%");
    }

    if (!InpQuietExpertsLog && InpPrintBarForecast)
        Print(L("→ Quét chốt lời / cắt lỗ sau dự báo nến mới …", "→ TP/SL scan after new bar forecast …"));

    ManagePerPositionExits();

    if (fd == 0) {
        if (!InpQuietExpertsLog)
            Print(L("NEUTRAL — không thêm lệnh.", "NEUTRAL — no new order."));
        return;
    }

    TryOpenFromSignalDirection(fd, pat);
}

void ProcessTickLogic() {
    const datetime barTime = iTime(_Symbol, _Period, 0);
    if (barTime != 0) {
        const bool isNewBar = (barTime != g_eaLastBarTimeForStack);
        if (isNewBar) {
            g_eaLastBarTimeForStack = barTime;
            if (HasEnoughHistory())
                OnNewBarHybridStack();
        }
    }

    ManagePerPositionExits();
}

int OnInit() {
    if (InpLstmSequence < 12) {
        Print(L("InpLstmSequence tối thiểu 12.", "InpLstmSequence must be at least 12."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpLstmHidden < 4) {
        Print(L("InpLstmHidden tối thiểu 4.", "InpLstmHidden must be at least 4."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpEquityPctPerTrade <= 0.0) {
        Print(L("InpEquityPctPerTrade phải > 0.", "InpEquityPctPerTrade must be > 0."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpTakeProfitPctOfEntry <= 0.0 || InpStopLossPctOfEntry <= 0.0) {
        Print(L("TP/SL % phải > 0.", "TP/SL %% must be > 0."));
        return INIT_PARAMETERS_INCORRECT;
    }

    InitLstmWeights();
    LoadOnnxModel();

    g_lastLogTime = 0;
    g_csvHeaderWritten = false;
    g_hasPriorPrediction = false;
    g_prevLogPrice = 0.0;
    g_prevPredictionDirection = 0;
    g_forecastScored = 0;
    g_forecastCorrect = 0;

    if (InpCloseAllOurOnInit) {
        CloseAllOurPositionsAndPendings();
        Print(L("Init: đã đóng/hủy lệnh EA (magic).", "Init: closed/cancelled EA orders (magic)."));
    }

    g_eaLastBarTimeForStack = iTime(_Symbol, _Period, 0);

    EventSetTimer(1);

    const long mm = (long)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    if (mm != (long)ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
        Print(L("CẢNH BÁO: tài khoản không phải hedging — MT5 có thể gộp nhiều lệnh cùng symbol thành MỘT vị thế; ",
                "WARNING: account is not hedging — MT5 may merge same-symbol trades into ONE net position; "));
        Print(L("TP/SL theo từng lệnh chỉ đúng khi mỗi lệnh là ticket riêng (hedging). ",
                "per-order TP/SL only applies when each trade is a separate ticket (hedging). "));
        Print(L("Margin mode=", "Margin mode="), mm,
              L(" (RETAIL_HEDGING=", " (RETAIL_HEDGING="), (long)ACCOUNT_MARGIN_MODE_RETAIL_HEDGING, ").");
    }

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    EventKillTimer();
    if (g_onnxHandle != INVALID_HANDLE) {
        OnnxRelease(g_onnxHandle);
        g_onnxHandle = INVALID_HANDLE;
    }
}

void OnTick() {
    ProcessTickLogic();
}

void OnTimer() {
    ProcessTickLogic();
}
