//+------------------------------------------------------------------+
//| Hybrid_LSTM_TA_SignalTrade.mq5                                   |
//| Dự báo long/short từ Hybrid_LSTM_TA_Signal.mqh + chiến lược @1   |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version "1.00"
#property description "LSTM+TA dự báo; khi rỗi lệnh quét tín hiệu; khi có basket chỉ quản trị nhồi/hedge/chốt."

#include <Trade/Trade.mqh>
#include "Hybrid_LSTM_TA_Signal.mqh"

input group "=== Quét tín hiệu (khi không có basket) ==="
input bool InpHybridOnNewBar = true;           // Quét khi có nến mới
input int InpHybridScanSeconds = 1;            // Quét tối thiểu mỗi N giây (0 = tắt, chỉ nến mới nếu bật trên)

input group "=== Giao dịch ==="
input ulong InpMagic = 910027;
input int InpSlippagePoints = 30;
input double InpBaitEquityPct = 1.0;           // % vốn (ký quỹ mục tiêu) lệnh mồi
input int InpMaxMartingaleAdds = 2;          // Số lệnh nhồi thêm (tổng tối đa = 1 + giá trị này)
input double InpMartingaleStepPips = 20.0;     // Khoảng pip nhồi cùng chiều từ giá vào cuối
input double InpTakeProfitEquityPct = 5.0;     // Chốt tất cả khi tổng lời >= % equity
input double InpMaxLossEquityPct = 50.0;       // Đóng hết khi tổng lỗ <= -% equity
input double InpTrailDropFromPeakPct = 5.0;    // Từ đỉnh lời basket, giảm % thì chốt (vd đỉnh 100, còn 95 thì đóng)
input bool InpUseHedge = true;                 // Tới max nhồi + giá vượt thêm X pip: mở hedge ngược
input double InpHedgeBeyondPips = 10.0;        // Pip vượt qua giá vào cuối (ngược chiều lệnh chính)
input double InpHedgeEquityPct = 5.0;          // % equity cho lot hedge
input int InpBasketLogIntervalSec = 5;         // Mỗi N giây in trạng thái basket (0 = mỗi lần quét)

CTrade g_trade;

datetime g_lastHybridScanTime = 0;
double g_peakBasketProfit = 0.0;
bool g_hedgePlaced = false;
datetime g_lastBasketStatusLog = 0;

double PipSizeLocal() {
    const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if (digits == 3 || digits == 5)
        return point * 10.0;
    return point;
}

double NormalizeVolumeLocal(const double vol) {
    const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    const double minv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    const double maxv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double v = MathFloor(vol / step) * step;
    return MathMax(minv, MathMin(maxv, v));
}

double VolumeForTargetMargin(const ENUM_ORDER_TYPE t, const double targetMarginMoney) {
    const double price = (t == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    const double lo = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    const double hi = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    const double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double best = lo;
    for (double v = lo; v <= hi + 1e-12; v += st) {
        double margin = 0.0;
        if (!OrderCalcMargin(t, _Symbol, v, price, margin))
            break;
        if (margin <= targetMarginMoney && margin > 0.0)
            best = v;
        else
            break;
    }
    return NormalizeVolumeLocal(best);
}

int CountOurPositions() {
    int n = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        n++;
    }
    return n;
}

double BasketProfitMoney() {
    double sum = 0.0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        sum += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
    }
    return sum;
}

bool LatestOurPosition(ulong& ticket, double& openPrice, datetime& openTime, long& posType) {
    ticket = 0;
    openPrice = 0.0;
    openTime = 0;
    posType = -1;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong t = PositionGetTicket(i);
        if (t == 0 || !PositionSelectByTicket(t))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        const datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
        if (ot >= openTime) {
            openTime = ot;
            ticket = t;
            openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            posType = PositionGetInteger(POSITION_TYPE);
        }
    }
    return (ticket != 0);
}

void CloseAllOurPositionsAndPendings() {
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

bool ShouldPullHybridNow(const bool isNewBar) {
    if (InpHybridOnNewBar && isNewBar)
        return true;
    if (InpHybridScanSeconds <= 0)
        return false;
    const datetime now = TimeCurrent();
    if (now - g_lastHybridScanTime >= InpHybridScanSeconds) {
        g_lastHybridScanTime = now;
        return true;
    }
    return false;
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
    const bool ok = (t == ORDER_TYPE_BUY) ? g_trade.Buy(volume, _Symbol, 0.0, 0.0, 0.0, comment) : g_trade.Sell(volume, _Symbol, 0.0, 0.0, 0.0, comment);
    if (!ok)
        Print("OpenMarket failed: ", g_trade.ResultRetcodeDescription());
    return ok;
}

void TryOpenBaitFromSignal() {
    int fd;
    double pu, pd;
    string pat, note, msg;
    if (!HybridSignal_FetchForecast(fd, pu, pd, pat, note, msg, true))
        return;

    if (fd == 0) {
        Print(L("Tín hiệu NEUTRAL — không vào lệnh mồi.", "NEUTRAL signal — no bait order."));
        return;
    }

    const ENUM_ORDER_TYPE t = (fd > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    const double targetMargin = eq * (InpBaitEquityPct / 100.0);
    const double vol = VolumeForTargetMargin(t, targetMargin);
    const string cmt = StringFormat("HYBRID_%s_%s", (fd > 0) ? "LONG" : "SHORT", pat);
    if (OpenMarket(t, vol, cmt)) {
        Print(L("Đã mở lệnh mồi theo dự báo ", "Opened bait per forecast "),
              (fd > 0) ? "LONG" : "SHORT", " vol=", vol);
        g_peakBasketProfit = 0.0;
        g_hedgePlaced = false;
    }
}

void ManageBasket() {
    const int n = CountOurPositions();
    if (n <= 0)
        return;

    const double eq = MathMax(AccountInfoDouble(ACCOUNT_EQUITY), 1.0);
    const double pnl = BasketProfitMoney();
    if (pnl > g_peakBasketProfit)
        g_peakBasketProfit = pnl;

    const double tpAbs = eq * (InpTakeProfitEquityPct / 100.0);
    const double lossCap = -eq * (InpMaxLossEquityPct / 100.0);

    if (pnl >= tpAbs) {
        Print(L("Chốt lời: tổng lời >= mốc % vốn — đóng hết.", "Take profit: total profit >= equity % — closing all."));
        CloseAllOurPositionsAndPendings();
        g_peakBasketProfit = 0.0;
        g_hedgePlaced = false;
        return;
    }

    if (pnl <= lossCap) {
        Print(L("Gồng lỗ: vượt mốc lỗ % vốn — đóng hết.", "Stop: loss beyond equity % — closing all."));
        CloseAllOurPositionsAndPendings();
        g_peakBasketProfit = 0.0;
        g_hedgePlaced = false;
        return;
    }

    if (g_peakBasketProfit > 0.0 && InpTrailDropFromPeakPct > 0.0) {
        const double trailFloor = g_peakBasketProfit * (1.0 - InpTrailDropFromPeakPct / 100.0);
        if (pnl < trailFloor) {
            Print(L("Chốt trail: lời giảm từ đỉnh basket — đóng hết.", "Trailing basket profit — closing all."));
            CloseAllOurPositionsAndPendings();
            g_peakBasketProfit = 0.0;
            g_hedgePlaced = false;
            return;
        }
    }

    if (pnl >= 0.0) {
        if (InpBasketLogIntervalSec <= 0 || TimeCurrent() - g_lastBasketStatusLog >= InpBasketLogIntervalSec) {
            g_lastBasketStatusLog = TimeCurrent();
            Print(L("Đang chờ chốt lời | P+L=", "Waiting take-profit | P+L="), DoubleToString(pnl, 2));
        }
    } else {
        if (InpBasketLogIntervalSec <= 0 || TimeCurrent() - g_lastBasketStatusLog >= InpBasketLogIntervalSec) {
            g_lastBasketStatusLog = TimeCurrent();
            Print(L("Đang gồng lỗ | P+L=", "Under water | P+L="), DoubleToString(pnl, 2));
        }
    }

    ulong lastTicket;
    double lastOpen;
    datetime lastOt;
    long lastType;
    if (!LatestOurPosition(lastTicket, lastOpen, lastOt, lastType))
        return;

    const double profitLast = PositionSelectByTicket(lastTicket) ? (PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP)) : 0.0;
    if (profitLast >= 0.0) {
        Print(L("Lệnh mở sau cùng đang lãi — không nhồi thêm (chờ chốt basket).",
                "Latest leg in profit — no martingale adds."));
        return;
    }

    const int maxTotal = 1 + InpMaxMartingaleAdds;
    if (n >= maxTotal) {
        if (InpUseHedge && !g_hedgePlaced) {
            const double pip = PipSizeLocal();
            const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            bool trigger = false;
            if (lastType == POSITION_TYPE_BUY && bid <= lastOpen - InpHedgeBeyondPips * pip)
                trigger = true;
            if (lastType == POSITION_TYPE_SELL && ask >= lastOpen + InpHedgeBeyondPips * pip)
                trigger = true;
            if (trigger) {
                const ENUM_ORDER_TYPE hedgeType = (lastType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
                const double targetMargin = eq * (InpHedgeEquityPct / 100.0);
                const double hv = VolumeForTargetMargin(hedgeType, targetMargin);
                if (OpenMarket(hedgeType, hv, "HYBRID_HEDGE")) {
                    g_hedgePlaced = true;
                    Print(L("Đã đặt hedge ngược chiều.", "Placed opposite hedge."));
                }
            }
        }
        return;
    }

    const double pip = PipSizeLocal();
    const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    bool stepHit = false;
    if (lastType == POSITION_TYPE_BUY && bid <= lastOpen - InpMartingaleStepPips * pip)
        stepHit = true;
    if (lastType == POSITION_TYPE_SELL && ask >= lastOpen + InpMartingaleStepPips * pip)
        stepHit = true;

    if (!stepHit)
        return;

    const ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)lastType;
    const double targetMargin = eq * (InpBaitEquityPct / 100.0);
    const double vol = VolumeForTargetMargin(t, targetMargin);
    if (OpenMarket(t, vol, "HYBRID_ADD"))
        Print(L("Nhồi thêm cùng chiều sau bước pip.", "Added same-direction leg after step."));
}

void ProcessScan() {
    const datetime barTime = iTime(_Symbol, _Period, 0);
    const bool isNewBar = (barTime != g_lastBarTime);
    if (isNewBar)
        g_lastBarTime = barTime;

    if (CountOurPositions() > 0) {
        ManageBasket();
        return;
    }

    g_peakBasketProfit = 0.0;
    g_hedgePlaced = false;

    if (!ShouldPullHybridNow(isNewBar))
        return;

    TryOpenBaitFromSignal();
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
    g_lastHybridScanTime = 0;
    g_peakBasketProfit = 0.0;
    g_hedgePlaced = false;

    CloseAllOurPositionsAndPendings();
    Print(L("Khởi tạo: đã hủy pending và đóng position của EA (magic).",
            "Init: removed pendings and closed EA positions (magic)."));

    EventSetTimer(1);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    EventKillTimer();
    if (g_onnxHandle != INVALID_HANDLE) {
        OnnxRelease(g_onnxHandle);
        g_onnxHandle = INVALID_HANDLE;
    }
}

void OnTimer() {
    ProcessScan();
}

void OnTick() {
}
