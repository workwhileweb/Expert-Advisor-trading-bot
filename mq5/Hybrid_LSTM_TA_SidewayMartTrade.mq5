//+------------------------------------------------------------------+
//| Hybrid_LSTM_TA_SidewayMartTrade.mq5                              |
//| Hybrid LSTM+TA tín hiệu + lọc sideway (giây) + martingale lot   |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "1.00"
#property description "Dự báo Hybrid_LSTM_TA_Signal; chỉ vào lệnh khi không sideway; mồi lot cố định; nhồi 1.1×; quay đầu 5× mồi; TP/SL % giá trị lệnh mồi & tài khoản."

#include <Trade/Trade.mqh>
#include "Hybrid_LSTM_TA_Signal.mqh"

input group "=== Quét tín hiệu Hybrid (khi không có basket) ==="
input bool InpHybridOnNewBar = true;  // Bật: quét thêm khi có nến mới (ngoài quét theo giây)
input int  InpHybridScanSeconds = 1;  // Quét tối thiểu mỗi N giây (0 = chỉ nến mới nếu bật trên)

input group "=== Phát hiện thị trường sideway (theo giây) ==="
input int    InpSidewaySampleSec = 1;       // Lấy mẫu giá mỗi N giây (đo sideway theo thời gian thực)
input int    InpSidewayWindowSec = 60;      // Cửa sổ đo: số giây gần nhất dùng tính biên độ giá
input double InpSidewayMaxRangePips = 8.0;  // Nếu (max−min) trong cửa sổ ≤ X pip → coi là SIDEWAY (không vào lệnh mới)
input bool   InpBlockEntryWhenSideway = true; // Bật: cấm mở basket mới khi đang sideway

input group "=== Lot & chuỗi martingale ==="
input ulong  InpMagic = 910028;              // Magic number — chỉ quản lý lệnh của EA này
input int    InpSlippagePoints = 30;       // Trượt giá tối đa (point) khi khớp thị trường
input double InpFirstLot = 0.01;             // Lot lệnh đầu (mồi) theo tín hiệu Hybrid
input double InpMartingaleMult = 1.1;        // Hệ số nhồi cùng chiều: lot mới = lot leg trước × hệ số (mặc định 1.1)
input double InpReversalMult = 5.0;          // Hệ số quay đầu: lot ngược = lot mồi × hệ số (mặc định 5)

input group "=== Chốt lời / cắt lỗ basket (theo % giá trị lệnh mồi) ==="
input double InpBasketTakeProfitPct = 10.0;  // Chốt lời: đóng tất cả khi P+L ròng ≥ ref$ × %/100 (ref = |lot_mồi×contract×giá_mồi|)
input double InpBasketStopLossPct = 0.0;     // Cắt lỗ basket: đóng khi P+L ≤ −ref$ × %/100. 0 = không cắt theo luật này

input group "=== Chốt lời / cắt lỗ toàn tài khoản (khi đang có basket) ==="
input double InpAccountTakeProfitPct = 0.0;  // Chốt khi equity tăng ≥ balance_lúc_mở_basket × %/100. 0 = tắt
input double InpAccountStopLossPct = 0.0;    // Cắt khi equity giảm ≥ balance_lúc_mở_basket × %/100. 0 = tắt

input group "=== Panel đa dòng trên chart ==="
input bool InpShowPanel = true;            // Hiển thị bảng thông tin (OBJ_EDIT nhiều dòng)
input int  InpPanelCorner = 0;             // Góc: 0=trên-trái 1=trên-phải 2=dưới-trái 3=dưới-phải
input int  InpPanelX = 10;                 // Lệch X (pixel)
input int  InpPanelY = 25;                 // Lệch Y (pixel)
input int  InpPanelWidth = 400;            // Rộng nền panel
input int  InpPanelHeight = 340;           // Cao nền panel
input int  InpPanelFontSize = 9;           // Cỡ chữ panel

#define HSSW_UI_BG "HSSW_PANEL_BG"
#define HSSW_UI_TX "HSSW_PANEL_TX"
#define SIDEWAY_BUF_MAX 720

CTrade g_trade;

datetime g_lastHybridScanTime = 0;
datetime g_lastSidewaySampleTime = 0;

double   g_swPrices[SIDEWAY_BUF_MAX];
datetime g_swTimes[SIDEWAY_BUF_MAX];
int      g_swCount = 0;
bool     g_isSideway = false;
double   g_sidewayRangePips = 0.0;

double   g_firstLot = 0.0;
double   g_firstOpenPrice = 0.0;
bool     g_basketBuy = true;
double   g_basketRefMoney = 0.0;
double   g_basketTpMoney = 0.0;
double   g_basketSlMoney = 0.0;
double   g_balanceAtBasketOpen = 0.0;
int      g_addStage = 0; // 0=mới mồi; 1=đã nhồi lần1; 2=đã nhồi lần2; 3=đã quay đầu

int      g_panel_fd = 0;
double   g_panel_pu = 0.5;
double   g_panel_pd = 0.5;
string   g_panel_pat = "";
string   g_panel_note = "";
datetime g_panel_sig_time = 0;
bool     g_panel_have_signal = false;

//+------------------------------------------------------------------+
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

string UiTruncate(const string s, const int maxLen) {
    if (maxLen <= 0 || StringLen(s) <= maxLen)
        return s;
    return StringSubstr(s, 0, maxLen - 3) + "...";
}

void UiPanelDelete() {
    ObjectDelete(0, HSSW_UI_TX);
    ObjectDelete(0, HSSW_UI_BG);
    ChartRedraw(0);
}

void UiPanelCreate() {
    if (!InpShowPanel)
        return;
    UiPanelDelete();
    const int corner = MathMax(0, MathMin(3, InpPanelCorner));
    const int w = MathMax(120, InpPanelWidth);
    const int h = MathMax(80, InpPanelHeight);

    ObjectCreate(0, HSSW_UI_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_XDISTANCE, InpPanelX);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_YDISTANCE, InpPanelY);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_BGCOLOR, C'28,32,40');
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_COLOR, C'80,120,160');
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_BACK, false);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_HIDDEN, true);

    ObjectCreate(0, HSSW_UI_TX, OBJ_EDIT, 0, 0, 0);
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_XDISTANCE, InpPanelX + 6);
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_YDISTANCE, InpPanelY + 6);
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_XSIZE, w - 12);
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_YSIZE, h - 12);
    ObjectSetString(0, HSSW_UI_TX, OBJPROP_FONT, "Consolas");
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_FONTSIZE, MathMax(8, MathMin(16, InpPanelFontSize)));
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_COLOR, clrWhiteSmoke);
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_BGCOLOR, C'28,32,40');
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_BORDER_COLOR, C'50,60,75');
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_READONLY, true);
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, HSSW_UI_TX, OBJPROP_HIDDEN, true);
    ChartRedraw(0);
}

void UiPanelUpdate() {
    if (!InpShowPanel)
        return;
    if (ObjectFind(0, HSSW_UI_TX) < 0)
        UiPanelCreate();
    if (ObjectFind(0, HSSW_UI_TX) < 0)
        return;

    const string cur = AccountInfoString(ACCOUNT_CURRENCY);
    const int nPos = CountOurPositions();
    string t = "━━ Hybrid Sideway + Mart ━━\n";
    t += _Symbol + "  " + EnumToString(_Period) + "\n\n";

    t += L("Thị trường: ", "Market: ");
    if (g_isSideway)
        t += L("SIDEWAY ⏸ (không mở mới)\n", "SIDEWAY ⏸ (no new entry)\n");
    else
        t += L("XU HƯỚNG ✓ (cho phép vào)\n", "TRENDING ✓ (entry allowed)\n");
    t += L("Biên ", "Range ") + DoubleToString(g_sidewayRangePips, 2) + L(" pip / ngưỡng ", " pip / max ");
    t += DoubleToString(InpSidewayMaxRangePips, 2) + L(" pip\n", " pip\n");
    t += L("Cửa sổ ", "Window ") + IntegerToString(InpSidewayWindowSec) + L("s · mẫu ", "s · sample ");
    t += IntegerToString(InpSidewaySampleSec) + "s\n\n";

    if (nPos <= 0) {
        t += L("● Chờ tín hiệu (không basket)\n\n", "● Waiting signal (no basket)\n\n");
        if (g_panel_have_signal) {
            string dtxt = (g_panel_fd > 0) ? "LONG ⤴" : (g_panel_fd < 0 ? "SHORT ⤵" : "NEUTRAL ○");
            t += L("Dự báo: ", "Forecast: ") + dtxt + "\n";
            t += "P(up/down) " + DoubleToString(g_panel_pu * 100.0, 1) + " / " + DoubleToString(g_panel_pd * 100.0, 1) + " %\n";
            t += L("Pattern: ", "Pattern: ") + UiTruncate(g_panel_pat, 42) + "\n";
            if (StringLen(g_panel_note) > 0)
                t += L("Ghi chú: ", "Note: ") + UiTruncate(g_panel_note, 40) + "\n";
            t += L("Quét: ", "Scan: ") + TimeToString(g_panel_sig_time, TIME_DATE | TIME_SECONDS) + "\n";
        } else {
            t += L("(Chưa quét Hybrid)\n", "(No hybrid scan yet)\n");
        }
    } else {
        RecoverBasketGlobalsIfNeeded();
        const double pnl = BasketProfitMoney();
        const int nSame = CountSameDirectionLegs(g_basketBuy);
        const int nOpp = CountOppositeLegs(g_basketBuy);
        double sumWin = 0.0, sumLoss = 0.0;
        int legN = 0;
        BasketLegProfitSums(sumWin, sumLoss, legN);

        t += L("● Basket ", "● Basket ") + (g_basketBuy ? "LONG" : "SHORT");
        t += "  " + IntegerToString(nSame) + L(" leg cùng chiều", " same-dir");
        if (nOpp > 0)
            t += L(" + quay đầu", " + reversal");
        t += "\n";
        t += L("Mồi lot ", "Bait lot ") + DoubleToString(g_firstLot, 2);
        t += L("  stage ", "  stage ") + IntegerToString(g_addStage) + "/3\n";
        t += L("P+L ròng: ", "Net P+L: ") + DoubleToString(pnl, 2) + " " + cur;
        t += (pnl >= 0.0 ? L(" (lãi)\n", " (profit)\n") : L(" (lỗ)\n", " (loss)\n"));
        t += L("Leg +/−: ", "Leg +/−: ") + DoubleToString(sumWin, 2) + " / " + DoubleToString(sumLoss, 2) + "\n";
        if (g_basketTpMoney > 0.0)
            t += L("→ TP: ", "→ TP: ") + DoubleToString(MathMax(0.0, g_basketTpMoney - pnl), 2) + " " + cur + L(" cần thêm\n", " more\n");
        if (g_basketSlMoney > 0.0)
            t += L("→ SL: còn ", "→ SL: room ") + DoubleToString(MathMax(0.0, pnl + g_basketSlMoney), 2) + " " + cur + "\n";
        ulong lt = 0;
        double lop = 0.0;
        datetime lot = 0;
        long lty = -1;
        if (LatestOurPosition(lt, lop, lot, lty)) {
            double lp = 0.0;
            if (PositionSelectByTicket(lt))
                lp = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            t += L("Leg cuối P+L: ", "Latest leg P+L: ") + DoubleToString(lp, 2) + " " + cur + "\n";
        }
        t += L("Vị thế EA: ", "EA positions: ") + IntegerToString(nPos) + "\n";
    }

    StringReplace(t, "\n", "\r\n");
    ObjectSetString(0, HSSW_UI_TX, OBJPROP_TEXT, t);
    ChartRedraw(0);
}

void LogExitBanner(const string titleVi, const string titleEn, const double pnl, const string detailVi, const string detailEn) {
    const string cur = AccountInfoString(ACCOUNT_CURRENCY);
    const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
    Print("================================================================");
    Print(L("[ĐÓNG BASKET] ", "[CLOSE BASKET] "), L(titleVi, titleEn));
    Print(L("Equity: ", "Equity: "), DoubleToString(eq, 2), " ", cur);
    Print(L("P+L ròng (profit+swap): ", "Net P+L (profit+swap): "), DoubleToString(pnl, 2), " ", cur,
          (pnl >= 0.0 ? L(" → KẾT QUẢ: LÃI", " → RESULT: PROFIT") : L(" → KẾT QUẢ: LỖ", " → RESULT: LOSS")));
    Print(L(detailVi, detailEn));
    Print("================================================================");
}

void LogLegOpen(const string legLabelVi, const string legLabelEn, const ENUM_ORDER_TYPE t, const double vol, const string reasonVi, const string reasonEn) {
    Print(L("── Mở ", "── Open "), L(legLabelVi, legLabelEn), " | ", (t == ORDER_TYPE_BUY ? "BUY" : "SELL"),
          " vol=", DoubleToString(vol, 2));
    Print(L("Lý do: ", "Reason: "), L(reasonVi, reasonEn));
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

int CountSameDirectionLegs(const bool basketBuy) {
    int c = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        const long typ = PositionGetInteger(POSITION_TYPE);
        if (basketBuy && typ == POSITION_TYPE_BUY)
            c++;
        if (!basketBuy && typ == POSITION_TYPE_SELL)
            c++;
    }
    return c;
}

int CountOppositeLegs(const bool basketBuy) {
    int c = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        const long typ = PositionGetInteger(POSITION_TYPE);
        if (basketBuy && typ == POSITION_TYPE_SELL)
            c++;
        if (!basketBuy && typ == POSITION_TYPE_BUY)
            c++;
    }
    return c;
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

bool LatestSameDirectionVolume(const bool basketBuy, double& outVol) {
    outVol = 0.0;
    datetime newest = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        const long typ = PositionGetInteger(POSITION_TYPE);
        const bool legBuy = (typ == POSITION_TYPE_BUY);
        if (basketBuy != legBuy)
            continue;
        const datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
        if (newest == 0 || ot >= newest) {
            newest = ot;
            outVol = PositionGetDouble(POSITION_VOLUME);
        }
    }
    return (outVol > 0.0);
}

bool OldestOurPosition(ulong& ticket, double& openPrice, datetime& openTime, long& posType) {
    ticket = 0;
    openPrice = 0.0;
    openTime = D'2099.12.31';
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
        if (ticket == 0 || ot < openTime) {
            openTime = ot;
            ticket = t;
            openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            posType = PositionGetInteger(POSITION_TYPE);
        }
    }
    return (ticket != 0);
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

void BasketLegProfitSums(double& sumWinningLegs, double& sumLosingLegs, int& legCount) {
    sumWinningLegs = 0.0;
    sumLosingLegs = 0.0;
    legCount = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        const double leg = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        legCount++;
        if (leg > 0.0)
            sumWinningLegs += leg;
        else if (leg < 0.0)
            sumLosingLegs += leg;
    }
}

bool FirstLegNotionalMoney(double& outRefMoney) {
    outRefMoney = 0.0;
    double vol = g_firstLot;
    double px = g_firstOpenPrice;
    if (vol <= 0.0 || px <= 0.0)
        return false;
    const double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    const double nominal = MathAbs(vol * cs * px);
    if (nominal > 0.0 && MathIsValidNumber(nominal)) {
        outRefMoney = nominal;
        return true;
    }
    const ENUM_ORDER_TYPE ot = g_basketBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    double margin = 0.0;
    if (OrderCalcMargin(ot, _Symbol, vol, px, margin) && margin > 0.0) {
        outRefMoney = margin;
        return true;
    }
    return false;
}

void LockBasketTpSlFromFirstLeg() {
    double refMoney = 0.0;
    if (!FirstLegNotionalMoney(refMoney) || refMoney <= 0.0)
        refMoney = 1.0;
    g_basketRefMoney = refMoney;
    g_basketTpMoney = (InpBasketTakeProfitPct > 0.0) ? refMoney * (InpBasketTakeProfitPct / 100.0) : 0.0;
    g_basketSlMoney = (InpBasketStopLossPct > 0.0) ? refMoney * (InpBasketStopLossPct / 100.0) : 0.0;
}

void ResetBasketState() {
    g_firstLot = 0.0;
    g_firstOpenPrice = 0.0;
    g_basketBuy = true;
    g_basketRefMoney = 0.0;
    g_basketTpMoney = 0.0;
    g_basketSlMoney = 0.0;
    g_balanceAtBasketOpen = 0.0;
    g_addStage = 0;
}

void RecoverBasketGlobalsIfNeeded() {
    if (g_firstOpenPrice > 0.0)
        return;
    ulong tk;
    double op;
    datetime ot;
    long typ;
    if (!OldestOurPosition(tk, op, ot, typ))
        return;
    g_firstOpenPrice = op;
    g_basketBuy = (typ == POSITION_TYPE_BUY);
    if (PositionSelectByTicket(tk))
        g_firstLot = PositionGetDouble(POSITION_VOLUME);
    LockBasketTpSlFromFirstLeg();
}

void CloseAllOurPositions() {
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
    const bool ok = (t == ORDER_TYPE_BUY) ? g_trade.Buy(volume, _Symbol, 0.0, 0.0, 0.0, comment)
                                          : g_trade.Sell(volume, _Symbol, 0.0, 0.0, 0.0, comment);
    if (!ok)
        Print(L("Mở lệnh thất bại: ", "Open failed: "), g_trade.ResultRetcodeDescription());
    return ok;
}

void SidewayPushSample() {
    const int sampleSec = MathMax(1, InpSidewaySampleSec);
    const datetime now = TimeCurrent();
    if (g_lastSidewaySampleTime > 0 && now - g_lastSidewaySampleTime < sampleSec)
        return;
    g_lastSidewaySampleTime = now;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (bid <= 0.0)
        bid = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
    if (bid <= 0.0)
        return;

    if (g_swCount >= SIDEWAY_BUF_MAX) {
        for (int i = 1; i < g_swCount; i++) {
            g_swPrices[i - 1] = g_swPrices[i];
            g_swTimes[i - 1] = g_swTimes[i];
        }
        g_swCount = SIDEWAY_BUF_MAX - 1;
    }
    g_swPrices[g_swCount] = bid;
    g_swTimes[g_swCount] = now;
    g_swCount++;

    const int windowSec = MathMax(5, InpSidewayWindowSec);
    int w = 0;
    while (w < g_swCount && now - g_swTimes[w] > windowSec) {
        for (int j = w + 1; j < g_swCount; j++) {
            g_swPrices[j - 1] = g_swPrices[j];
            g_swTimes[j - 1] = g_swTimes[j];
        }
        g_swCount--;
    }
}

void SidewayUpdateState() {
    SidewayPushSample();
    g_isSideway = false;
    g_sidewayRangePips = 0.0;
    if (g_swCount < 2)
        return;

    double hi = g_swPrices[0];
    double lo = g_swPrices[0];
    for (int i = 1; i < g_swCount; i++) {
        if (g_swPrices[i] > hi)
            hi = g_swPrices[i];
        if (g_swPrices[i] < lo)
            lo = g_swPrices[i];
    }
    const double pip = PipSizeLocal();
    if (pip <= 0.0)
        return;
    g_sidewayRangePips = (hi - lo) / pip;
    g_isSideway = (g_sidewayRangePips <= InpSidewayMaxRangePips);
}

bool TradingAllowedBySideway() {
    if (!InpBlockEntryWhenSideway)
        return true;
    return !g_isSideway;
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

bool CheckCloseRules(const double pnl, bool& closed) {
    closed = false;
    const string cur = AccountInfoString(ACCOUNT_CURRENCY);
    RecoverBasketGlobalsIfNeeded();
    if (g_basketTpMoney <= 0.0 && g_basketSlMoney <= 0.0)
        LockBasketTpSlFromFirstLeg();

    if (g_basketTpMoney > 0.0 && pnl >= g_basketTpMoney) {
        string dVi = "Luật: P+L ròng ≥ mốc chốt lời khóa theo % giá trị lệnh mồi.\n";
        dVi += "Ref (lot×contract×giá mồi) = " + DoubleToString(g_basketRefMoney, 2) + " " + cur + " × " +
               DoubleToString(InpBasketTakeProfitPct, 2) + "% = " + DoubleToString(g_basketTpMoney, 2) + ".\n";
        dVi += "Kiểm tra: P+L " + DoubleToString(pnl, 2) + " ≥ " + DoubleToString(g_basketTpMoney, 2) + " → chốt lãi.";
        string dEn = "Rule: net P+L >= locked TP from first-leg notional %.\n";
        dEn += "Ref = " + DoubleToString(g_basketRefMoney, 2) + " × " + DoubleToString(InpBasketTakeProfitPct, 2) +
               "% → TP " + DoubleToString(g_basketTpMoney, 2) + ". P+L " + DoubleToString(pnl, 2) + " → take profit.";
        LogExitBanner("Chốt lời basket (% lệnh mồi)", "Basket take profit (bait %)", pnl, dVi, dEn);
        CloseAllOurPositions();
        closed = true;
        return true;
    }

    if (g_basketSlMoney > 0.0 && pnl <= -g_basketSlMoney) {
        string dVi = "Luật: P+L ròng ≤ −mốc cắt lỗ khóa theo % giá trị lệnh mồi.\n";
        dVi += "Ref = " + DoubleToString(g_basketRefMoney, 2) + " × " + DoubleToString(InpBasketStopLossPct, 2) +
               "% → cắt tại " + DoubleToString(-g_basketSlMoney, 2) + ".\n";
        dVi += "P+L hiện " + DoubleToString(pnl, 2) + " → cắt lỗ.";
        string dEn = "Rule: net P+L <= −locked SL from bait %. Current " + DoubleToString(pnl, 2) + " → stop loss.";
        LogExitBanner("Cắt lỗ basket (% lệnh mồi)", "Basket stop loss (bait %)", pnl, dVi, dEn);
        CloseAllOurPositions();
        closed = true;
        return true;
    }

    if (g_balanceAtBasketOpen > 0.0) {
        const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
        const double delta = eq - g_balanceAtBasketOpen;
        if (InpAccountTakeProfitPct > 0.0) {
            const double tpAcc = g_balanceAtBasketOpen * (InpAccountTakeProfitPct / 100.0);
            if (delta >= tpAcc) {
                string dVi = "Luật: equity − balance_lúc_mở ≥ balance × " + DoubleToString(InpAccountTakeProfitPct, 2) + "%.\n";
                dVi += "Balance mở: " + DoubleToString(g_balanceAtBasketOpen, 2) + " → ngưỡng +" + DoubleToString(tpAcc, 2) +
                       "; delta equity " + DoubleToString(delta, 2) + " → chốt (lãi tài khoản).";
                string dEn = "Account TP: equity gain vs balance at basket open >= " + DoubleToString(InpAccountTakeProfitPct, 2) + "%.";
                LogExitBanner("Chốt lời tài khoản", "Account take profit", pnl, dVi, dEn);
                CloseAllOurPositions();
                closed = true;
                return true;
            }
        }
        if (InpAccountStopLossPct > 0.0) {
            const double slAcc = g_balanceAtBasketOpen * (InpAccountStopLossPct / 100.0);
            if (delta <= -slAcc) {
                string dVi = "Luật: equity giảm ≥ balance × " + DoubleToString(InpAccountStopLossPct, 2) + "%.\n";
                dVi += "Delta " + DoubleToString(delta, 2) + " ≤ −" + DoubleToString(slAcc, 2) + " → cắt (lỗ tài khoản).";
                string dEn = "Account SL: equity drop >= " + DoubleToString(InpAccountStopLossPct, 2) + "% of balance at open.";
                LogExitBanner("Cắt lỗ tài khoản", "Account stop loss", pnl, dVi, dEn);
                CloseAllOurPositions();
                closed = true;
                return true;
            }
        }
    }
    return false;
}

void ManageMartingaleSequence() {
    const int nPos = CountOurPositions();
    if (nPos <= 0)
        return;

    RecoverBasketGlobalsIfNeeded();
    const double pnl = BasketProfitMoney();
    bool closed = false;
    if (CheckCloseRules(pnl, closed)) {
        ResetBasketState();
        return;
    }

    ulong lastTk = 0;
    double lastOp = 0.0;
    datetime lastOt = 0;
    long lastTyp = -1;
    if (!LatestOurPosition(lastTk, lastOp, lastOt, lastTyp))
        return;

    double lastLegPnl = 0.0;
    if (PositionSelectByTicket(lastTk))
        lastLegPnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

    // Leg cuối đang lãi → chờ mốc chốt basket (không nhồi / không quay đầu thêm)
    if (lastLegPnl >= 0.0) {
        return;
    }

    const int nSame = CountSameDirectionLegs(g_basketBuy);
    const int nOpp = CountOppositeLegs(g_basketBuy);
    const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    if (nOpp > 0)
        return; // đã quay đầu — không thêm theo spec

    if (g_addStage == 0 && nSame == 1) {
        double prevVol = 0.0;
        if (!LatestSameDirectionVolume(g_basketBuy, prevVol))
            prevVol = g_firstLot;
        const double vol = NormalizeVolumeLocal(prevVol * InpMartingaleMult);
        const ENUM_ORDER_TYPE t = g_basketBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        if (vol >= vmin && OpenMarket(t, vol, "HSSW_ADD1")) {
            g_addStage = 1;
            LogLegOpen("lệnh nhồi #2", "martingale leg #2", t, vol,
                       "Lệnh mồi đang lỗ — nhồi cùng chiều lot = lot leg trước × " + DoubleToString(InpMartingaleMult, 2),
                       "Bait leg losing — same-dir add = prev lot × " + DoubleToString(InpMartingaleMult, 2));
        }
        return;
    }

    if (g_addStage == 1 && nSame == 2) {
        double prevVol = 0.0;
        if (!LatestSameDirectionVolume(g_basketBuy, prevVol))
            return;
        const double vol = NormalizeVolumeLocal(prevVol * InpMartingaleMult);
        const ENUM_ORDER_TYPE t = g_basketBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        if (vol >= vmin && OpenMarket(t, vol, "HSSW_ADD2")) {
            g_addStage = 2;
            LogLegOpen("lệnh nhồi #3", "martingale leg #3", t, vol,
                       "Lệnh #2 vẫn lỗ — nhồi tiếp cùng chiều lot = lot #2 × " + DoubleToString(InpMartingaleMult, 2),
                       "Leg #2 still losing — add lot = leg#2 lot × " + DoubleToString(InpMartingaleMult, 2));
        }
        return;
    }

    if (g_addStage == 2 && nSame >= 3) {
        const double vol = NormalizeVolumeLocal(g_firstLot * InpReversalMult);
        const ENUM_ORDER_TYPE t = g_basketBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        if (vol >= vmin && OpenMarket(t, vol, "HSSW_REV")) {
            g_addStage = 3;
            LogLegOpen("lệnh quay đầu", "reversal leg", t, vol,
                       "Sau 3 leg cùng chiều vẫn lỗ — mở ngược chiều lot = lot mồi × " + DoubleToString(InpReversalMult, 2),
                       "After 3 same-dir legs still losing — opposite = bait lot × " + DoubleToString(InpReversalMult, 2));
        }
    }
}

void TryOpenFirstFromSignal() {
    if (!TradingAllowedBySideway()) {
        Print(L("[SIDEWAY] Biên ", "[SIDEWAY] Range "), DoubleToString(g_sidewayRangePips, 2),
              L(" pip ≤ ngưỡng ", " pip <= max "), DoubleToString(InpSidewayMaxRangePips, 2),
              L(" — không mở lệnh mới.", " — skip new entry."));
        return;
    }

    int fd;
    double pu, pd;
    string pat, note, msg;
    if (!HybridSignal_FetchForecast(fd, pu, pd, pat, note, msg, false))
        return;

    g_panel_have_signal = true;
    g_panel_fd = fd;
    g_panel_pu = pu;
    g_panel_pd = pd;
    g_panel_pat = pat;
    g_panel_note = note;
    g_panel_sig_time = TimeCurrent();

    Print(L("[HYBRID] ", "[HYBRID] "), msg);
    Print(L("Pattern: ", "Pattern: "), pat, " | ", L("Ghi chú: ", "Note: "), note);
    Print(L("Hướng: ", "Direction: "), fd, " | up ", DoubleToString(pu * 100.0, 1), "% down ", DoubleToString(pd * 100.0, 1), "%");

    if (fd == 0) {
        Print(L("NEUTRAL — không vào lệnh.", "NEUTRAL — no entry."));
        return;
    }

    const ENUM_ORDER_TYPE t = (fd > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    const double vol = NormalizeVolumeLocal(InpFirstLot);
    const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if (vol < vmin) {
        Print(L("InpFirstLot nhỏ hơn SYMBOL_VOLUME_MIN.", "InpFirstLot below SYMBOL_VOLUME_MIN."));
        return;
    }

    const string cmt = StringFormat("HSSW_%s_%s", (fd > 0) ? "LONG" : "SHORT", pat);
    if (!OpenMarket(t, vol, cmt))
        return;

    g_firstLot = vol;
    g_firstOpenPrice = g_trade.ResultPrice();
    if (g_firstOpenPrice <= 0.0) {
        ulong rtk;
        double rop;
        datetime rot;
        long rty;
        if (LatestOurPosition(rtk, rop, rot, rty))
            g_firstOpenPrice = rop;
    }
    g_basketBuy = (fd > 0);
    g_balanceAtBasketOpen = AccountInfoDouble(ACCOUNT_BALANCE);
    g_addStage = 0;
    LockBasketTpSlFromFirstLeg();

    LogLegOpen("lệnh mồi", "bait leg", t, vol,
               "Tín hiệu Hybrid " + ((fd > 0) ? "LONG" : "SHORT") + " + thị trường không sideway",
               "Hybrid signal " + ((fd > 0) ? "LONG" : "SHORT") + " + not sideway");

    const string cur = AccountInfoString(ACCOUNT_CURRENCY);
    Print(L("Khóa TP basket: ", "Locked basket TP: "), DoubleToString(g_basketTpMoney, 2), " ", cur,
          L(" (", " ("), DoubleToString(InpBasketTakeProfitPct, 1), "% ref ", DoubleToString(g_basketRefMoney, 2), ")");
    if (g_basketSlMoney > 0.0)
        Print(L("Khóa SL basket: ", "Locked basket SL: "), DoubleToString(g_basketSlMoney, 2), " ", cur);
    else
        Print(L("SL basket: tắt (InpBasketStopLossPct=0).", "Basket SL: off (InpBasketStopLossPct=0)."));
}

void ProcessScan() {
    const datetime barTime = iTime(_Symbol, _Period, 0);
    const bool isNewBar = (barTime != g_lastBarTime);
    if (isNewBar)
        g_lastBarTime = barTime;

    SidewayUpdateState();

    if (CountOurPositions() > 0) {
        ManageMartingaleSequence();
        return;
    }

    ResetBasketState();

    if (!ShouldPullHybridNow(isNewBar))
        return;

    TryOpenFirstFromSignal();
}

int OnInit() {
    if (InpLstmSequence < 12) {
        Print(L("InpLstmSequence tối thiểu 12.", "InpLstmSequence must be >= 12."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpLstmHidden < 4) {
        Print(L("InpLstmHidden tối thiểu 4.", "InpLstmHidden must be >= 4."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpFirstLot <= 0.0) {
        Print(L("InpFirstLot phải > 0.", "InpFirstLot must be > 0."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpMartingaleMult <= 1.0) {
        Print(L("InpMartingaleMult phải > 1.", "InpMartingaleMult must be > 1."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpReversalMult <= 0.0) {
        Print(L("InpReversalMult phải > 0.", "InpReversalMult must be > 0."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpBasketTakeProfitPct <= 0.0) {
        Print(L("InpBasketTakeProfitPct phải > 0.", "InpBasketTakeProfitPct must be > 0."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpSidewayWindowSec < 5) {
        Print(L("InpSidewayWindowSec tối thiểu 5.", "InpSidewayWindowSec min 5."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpSidewaySampleSec < 1) {
        Print(L("InpSidewaySampleSec tối thiểu 1.", "InpSidewaySampleSec min 1."));
        return INIT_PARAMETERS_INCORRECT;
    }

    InitLstmWeights();
    LoadOnnxModel();
    g_lastBarTime = iTime(_Symbol, _Period, 0);
    g_lastHybridScanTime = 0;
    g_lastSidewaySampleTime = 0;
    g_swCount = 0;
    g_isSideway = false;
    g_panel_have_signal = false;
    ResetBasketState();

    if (InpShowPanel)
        UiPanelCreate();

    EventSetTimer(1);
    UiPanelUpdate();
    Print(L("Khởi tạo Hybrid SidewayMartTrade — timer 1s.", "Init Hybrid SidewayMartTrade — 1s timer."));
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    EventKillTimer();
    UiPanelDelete();
    if (g_onnxHandle != INVALID_HANDLE) {
        OnnxRelease(g_onnxHandle);
        g_onnxHandle = INVALID_HANDLE;
    }
}

void OnTimer() {
    ProcessScan();
    UiPanelUpdate();
}

void OnTick() {
}
