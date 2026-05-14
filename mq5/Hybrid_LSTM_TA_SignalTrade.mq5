//+------------------------------------------------------------------+
//| Hybrid_LSTM_TA_SignalTrade.mq5                                   |
//| Dự báo long/short từ Hybrid_LSTM_TA_Signal.mqh + chiến lược @1   |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version "1.00"
#property description "LSTM+TA; lot mồi/nhồi = % của 1.00 lot; TP/SL basket = % giá trị vị thế lệnh mồi (lot×contract×giá); hedge = % lot so với lot mồi."

#include <Trade/Trade.mqh>
#include "Hybrid_LSTM_TA_Signal.mqh"

input group "=== Quét tín hiệu (khi không có basket) ===" input bool InpHybridOnNewBar = true; // Quét khi có nến mới
input int InpHybridScanSeconds = 1;                                                            // Quét tối thiểu mỗi N giây (0 = tắt, chỉ nến mới nếu bật trên)

input group "=== Giao dịch ==="
input ulong InpMagic = 910027;
input int InpSlippagePoints = 30;
input double InpBaitLotPct = 10.0;               // % của 1.00 lot (10 = 0.10 lot) — lệnh mồi & nhồi
input int InpMaxMartingaleAdds = 2;              // Số lệnh nhồi thêm (tổng tối đa = 1 + giá trị này)
input double InpMartingaleStepPips = 20.0;       // Khi FromPrevLegPips=0: giá_mồi ± n×pip (n=số leg cùng chiều; BUY −, SELL +)
input double InpMartingaleFromPrevLegPips = 0.0; // 0=tắt. >0: nhồi khi giá đi thêm X pip bất lợi so với giá vào leg cùng chiều mới nhất (mồi hoặc nhồi trước)
input double InpTakeProfitBaitPct = 20.0;        // Chốt lời basket: mốc $ = giá trị lệnh mồi × %/100 (giá trị = |lot×SYMBOL_TRADE_CONTRACT_SIZE×giá mở mồi|)
input double InpMaxLossBaitPct = 20.0;           // Cắt lỗ: |lỗ| tối đa $ = cùng công thức giá trị lệnh mồi × %/100
input bool InpUseHedge = true;                   // Tới max nhồi + giá vượt thêm X pip: mở hedge ngược
input double InpHedgeBeyondPips = 10.0;          // Pip vượt qua giá vào cuối (ngược chiều lệnh chính)
input double InpHedgeLotPctOfBait = 500.0;       // % lot so với lot lệnh mồi (500 = 5×) — tiền vào hedge quay đầu
input bool InpUseReversalOppositeOnBaitPips = true; // Bật: (1) mồi đủ pip bất lợi → 1 lệnh quay đầu ngược basket (2) theo dõi lệnh đó, đủ pip bất lợi → thêm 1 lệnh ngược basket
input double InpReversalOppositeTriggerPips = 50.0; // 0=tắt. Dùng cho cả: pip bất lợi so mồi (mở lệnh quay đầu) và pip bất lợi so lệnh quay đầu (mở thêm 1 lệnh)
input double InpReversalOppositeLotPctOfBait = 300.0; // % lot so với lot mồi (300 = 3×) cho mỗi lệnh ngược basket (quay đầu + bổ sung)
input int InpBasketLogIntervalSec = 5;           // Mỗi N giây in trạng thái basket (0 = mỗi lần quét)

input group "=== bỏ qua ===" input double InpTrailDropFromPeakPct = 0; // Chốt trail: P+L≥0 và P+L < đỉnh×(1−%/100). Độc lập với InpReversalClosePctOfTp. 0=tắt trail. Dễ nhầm với quay đầu — xem dòng dưới
input double InpReversalClosePctOfTp = 0;                              // Chốt quay đầu (giveback so với mốc TP$): chỉ khi >0. 0=tắt hoàn toàn luật này (KHÔNG tắt trail ở dòng trên)
input int InpLogMaxChunkChars = 900;                                   // Chia dòng log dài (0 = một dòng)

input group "=== Panel trên chart ===" input bool InpShowPanel = false; // Bảng thông tin thay cho log dài
input int InpPanelCorner = 0;                                           // 0=trên-trái 1=trên-phải 2=dưới-trái 3=dưới-phải (CORNER_*)
input int InpPanelX = 10;                                               // Lệch X (pixel)
input int InpPanelY = 25;                                               // Lệch Y
input int InpPanelWidth = 360;                                          // Rộng nền
input int InpPanelHeight = 320;                                         // Cao nền
input int InpPanelFontSize = 9;                                         // Cỡ chữ
input bool InpQuietExpertsLog = false;                                  // Bật: bớt Print Experts; xem chính trên panel

#define HST_UI_BG "HST_LSTM_PANEL_BG"
#define HST_UI_TX "HST_LSTM_PANEL_TX"

CTrade g_trade;

datetime g_lastHybridScanTime = 0;
double g_peakBasketProfit = 0.0;
bool g_hedgePlaced = false;
bool g_reversalOppositePlaced = false;       // đã mở lệnh quay đầu (ngược basket) theo pip mồi
bool g_reversalOppositeFollowUpPlaced = false; // đã mở thêm 1 lệnh ngược basket sau khi lệnh quay đầu đi bất lợi đủ pip
double g_reversalFirstLegOpenPrice = 0.0;    // giá mở lệnh quay đầu — mốc pip bước (2)
datetime g_lastBasketStatusLog = 0;
double g_baitLotVolume = 0.0;        // lot lệnh mồi vừa mở (cho tỉ lệ hedge)
double g_baitOpenPrice = 0.0;        // giá vào mồi — mốc nhồi theo n×pip
bool g_basketBuy = true;             // chiều basket (khớp lệnh mồi)
double g_basketTpMoney = 0.0;        // mốc TP $ khóa theo basket (P+L ròng >= giá trị này)
double g_basketLossMoney = 0.0;      // mốc |lỗ| $ khóa (P+L <= −giá trị này); luôn dương
double g_basketBaitValueMoney = 0.0; // ref $ = giá trị vị thế lệnh mồi lúc khóa (notional; log/panel)

int g_panel_fd = 0;
double g_panel_pu = 0.5;
double g_panel_pd = 0.5;
string g_panel_pat = "";
string g_panel_note = "";
datetime g_panel_sig_time = 0;
bool g_panel_have_signal = false;

string UiTruncate(const string s, const int maxLen) {
    if (maxLen <= 0 || StringLen(s) <= maxLen)
        return s;
    return StringSubstr(s, 0, maxLen - 3) + "...";
}

void UiPanelDelete() {
    ObjectDelete(0, HST_UI_TX);
    ObjectDelete(0, HST_UI_BG);
    ChartRedraw(0);
}

void UiPanelCreate() {
    if (!InpShowPanel)
        return;
    UiPanelDelete();
    const int corner = MathMax(0, MathMin(3, InpPanelCorner));
    const int w = MathMax(120, InpPanelWidth);
    const int h = MathMax(80, InpPanelHeight);

    ObjectCreate(0, HST_UI_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_XDISTANCE, InpPanelX);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_YDISTANCE, InpPanelY);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_BGCOLOR, C'32,32,36');
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_COLOR, C'90,90,95');
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_BACK, false);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, HST_UI_BG, OBJPROP_HIDDEN, true);

    // OBJ_LABEL thường chỉ hiện 1 dòng trên nhiều bản build — dùng OBJ_EDIT read-only cho multi-line.
    ObjectCreate(0, HST_UI_TX, OBJ_EDIT, 0, 0, 0);
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_XDISTANCE, InpPanelX + 6);
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_YDISTANCE, InpPanelY + 6);
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_XSIZE, w - 12);
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_YSIZE, h - 12);
    ObjectSetString(0, HST_UI_TX, OBJPROP_FONT, "Consolas");
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_FONTSIZE, MathMax(8, MathMin(16, InpPanelFontSize)));
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_COLOR, clrWhiteSmoke);
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_BGCOLOR, C'32,32,36');
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_BORDER_COLOR, C'50,50,55');
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_READONLY, true);
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, HST_UI_TX, OBJPROP_HIDDEN, true);
    ChartRedraw(0);
}

void UiPanelUpdate() {
    if (!InpShowPanel)
        return;
    if (ObjectFind(0, HST_UI_TX) < 0)
        UiPanelCreate();
    if (ObjectFind(0, HST_UI_TX) < 0)
        return;

    const string cur = AccountInfoString(ACCOUNT_CURRENCY);
    const double eq = MathMax(AccountInfoDouble(ACCOUNT_EQUITY), 1.0);
    const int nAll = CountOurPositions();
    string t = "━━ Hybrid LSTM · SignalTrade ━━\n";
    t += _Symbol + "  " + EnumToString(_Period) + "\n\n";

    if (nAll <= 0) {
        t += L("● Chờ tín hiệu (không basket)\n\n", "● Scanning (no basket)\n\n");
        if (g_panel_have_signal) {
            string dtxt = (g_panel_fd > 0) ? "LONG ⤴" : (g_panel_fd < 0 ? "SHORT ⤵" : "NEUTRAL ○");
            t += L("Dự báo: ", "Forecast: ") + dtxt + "\n";
            t += "P(up/down) " + DoubleToString(g_panel_pu * 100.0, 1) + " / " + DoubleToString(g_panel_pd * 100.0, 1) + " %\n";
            t += L("Pattern: ", "Pattern: ") + UiTruncate(g_panel_pat, 40) + "\n";
            if (StringLen(g_panel_note) > 0)
                t += L("Note: ", "Note: ") + UiTruncate(g_panel_note, 38) + "\n";
            t += L("Quét: ", "Scan: ") + TimeToString(g_panel_sig_time, TIME_DATE | TIME_SECONDS) + "\n";
        } else {
            t += L("(Chưa có lần quét hybrid)\n", "(No hybrid scan yet)\n");
        }
    } else {
        RecoverBasketGlobalsIfNeeded();
        EnsureBasketTpLossLocked(eq);
        const int nSame = CountOurSameDirectionBasketLegs(g_basketBuy);
        const double pnl = BasketProfitMoney();
        const double tpAbs = g_basketTpMoney;
        const double lossCap = -g_basketLossMoney;
        const double needTp = MathMax(0.0, tpAbs - pnl);
        const double roomLoss = MathMax(0.0, pnl - lossCap);

        double sumWin = 0.0, sumLoss = 0.0;
        int legN = 0;
        BasketLegProfitSums(sumWin, sumLoss, legN);

        t += L("● Basket ", "● Basket ") + (g_basketBuy ? "LONG" : "SHORT");
        t += "  " + IntegerToString(nSame) + "/" + IntegerToString(1 + InpMaxMartingaleAdds);
        t += L(" leg cùng chiều\n", " same-dir legs\n");
        t += L("Tổng P+L: ", "Net P+L: ") + DoubleToString(pnl, 2) + " " + cur + "\n";
        t += L("Leg + / − : ", "Sum + / − : ") + DoubleToString(sumWin, 2) + " / " + DoubleToString(sumLoss, 2) + "\n";
        t += L("→ TP: cần +", "→ TP: need +") + DoubleToString(needTp, 2) + "  ";
        t += L("| Room SL: ", "| Room SL: ") + DoubleToString(roomLoss, 2) + "\n";

        if (g_peakBasketProfit > 0.0 && InpTrailDropFromPeakPct > 0.0) {
            const double tfloor = g_peakBasketProfit * (1.0 - InpTrailDropFromPeakPct / 100.0);
            t += L("Trail: đỉnh ", "Trail: peak ") + DoubleToString(g_peakBasketProfit, 1);
            t += L("  sàn ", "  fl ") + DoubleToString(tfloor, 1) + "\n";
        }
        if (InpReversalClosePctOfTp > 0.0 && g_peakBasketProfit > 0.0) {
            const double gb = tpAbs * (InpReversalClosePctOfTp / 100.0);
            const double rfl = g_peakBasketProfit - gb;
            t += L("Quay đầu ≤ ", "Reversal ≤ ") + DoubleToString(rfl, 1) + "\n";
        }
        t += L("Mồi @ ", "Bait @ ") + DoubleToString(g_baitOpenPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
        t += "  hedge " + (g_hedgePlaced ? "OK" : "--");
        t += L("  quay đầu ", "  rev ") + (g_reversalOppositePlaced ? "1" : "-");
        t += "/" + (g_reversalOppositeFollowUpPlaced ? "2" : "-") + "\n";
        t += L("Vị thế EA: ", "EA pos: ") + IntegerToString(nAll) + "\n";
    }

    StringReplace(t, "\n", "\r\n");
    ObjectSetString(0, HST_UI_TX, OBJPROP_TEXT, t);
    ChartRedraw(0);
}

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

double VolumeFromLotPercentOfOneLot(const double lotPct) {
    return NormalizeVolumeLocal(lotPct / 100.0);
}

double HedgeVolumeFromBaitLot() {
    const double baitRef = (g_baitLotVolume > 0.0) ? g_baitLotVolume : VolumeFromLotPercentOfOneLot(InpBaitLotPct);
    return NormalizeVolumeLocal(baitRef * (InpHedgeLotPctOfBait / 100.0));
}

double ReversalOppositeVolumeFromBaitLot() {
    const double baitRef = (g_baitLotVolume > 0.0) ? g_baitLotVolume : VolumeFromLotPercentOfOneLot(InpBaitLotPct);
    return NormalizeVolumeLocal(baitRef * (InpReversalOppositeLotPctOfBait / 100.0));
}

// Giá trị vị thế lệnh mồi (notional): |lot × SYMBOL_TRADE_CONTRACT_SIZE × giá mở|. Fallback: OrderCalcMargin nếu không tính được.
bool BaitOrderNotionalMoneyAccount(double& outRefMoney) {
    outRefMoney = 0.0;
    double vol = g_baitLotVolume;
    if (vol <= 0.0)
        vol = VolumeFromLotPercentOfOneLot(InpBaitLotPct);
    double px = g_baitOpenPrice;
    if (px <= 0.0) {
        px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        if (px <= 0.0)
            px = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
    }
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
    if (OrderCalcMargin(ot, _Symbol, vol, px, margin) && margin > 0.0 && MathIsValidNumber(margin)) {
        outRefMoney = margin;
        return true;
    }
    return false;
}

int CountOurSameDirectionBasketLegs(const bool basketBuy) {
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

bool LatestSameDirectionOpenPrice(const bool basketBuy, double& outOpen) {
    outOpen = 0.0;
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
            outOpen = PositionGetDouble(POSITION_PRICE_OPEN);
        }
    }
    return (outOpen > 0.0);
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

void LockBasketTpLossFromBait() {
    double refMoney = 0.0;
    if (!BaitOrderNotionalMoneyAccount(refMoney) || refMoney <= 0.0)
        refMoney = 1.0;
    g_basketBaitValueMoney = refMoney;
    g_basketTpMoney = refMoney * (InpTakeProfitBaitPct / 100.0);
    g_basketLossMoney = refMoney * (InpMaxLossBaitPct / 100.0);
}

void EnsureBasketTpLossLocked(const double /*eqHintIgnored*/) {
    if (g_basketTpMoney > 0.0 && g_basketLossMoney > 0.0)
        return;
    LockBasketTpLossFromBait();
}

void ResetBasketMoneyRules() {
    g_basketTpMoney = 0.0;
    g_basketLossMoney = 0.0;
    g_basketBaitValueMoney = 0.0;
}

void ResetReversalOppositeState() {
    g_reversalOppositePlaced = false;
    g_reversalOppositeFollowUpPlaced = false;
    g_reversalFirstLegOpenPrice = 0.0;
}

void RecoverBasketGlobalsIfNeeded() {
    if (g_baitOpenPrice > 0.0)
        return;
    ulong tk;
    double op;
    datetime ot;
    long typ;
    if (!OldestOurPosition(tk, op, ot, typ))
        return;
    g_baitOpenPrice = op;
    g_basketBuy = (typ == POSITION_TYPE_BUY);
    if (PositionSelectByTicket(tk))
        g_baitLotVolume = PositionGetDouble(POSITION_VOLUME);
    EnsureBasketTpLossLocked(0.0);
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

// Luôn gọi khi đóng basket — không ẩn bởi InpQuietExpertsLog để user biết lý do.
void LogBasketExitBanner(const string titleVi, const string titleEn, const double eq, const double pnl, const string cur,
                         const string detailVi, const string detailEn) {
    Print("================================================================");
    Print(L("[ĐÓNG BASKET] ", "[CLOSE BASKET] "), L(titleVi, titleEn));
    Print(L("Equity (ACCOUNT_EQUITY): ", "Equity (ACCOUNT_EQUITY): "), DoubleToString(eq, 2), " ", cur);
    Print(L("P+L ròng (profit+swap, không hoa hồng/vị thế): ", "Net P+L (profit+swap): "), DoubleToString(pnl, 2), " ", cur);
    Print(L(detailVi, detailEn));
    Print("================================================================");
}

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
        const string line = StringSubstr(remainder, 0, take);
        Print(pfx, line);
        remainder = StringSubstr(remainder, take);
        pfx = "    ";
    }
}

void LogBasketSnapshot(const int nPositions, const double pnl, const double eq,
                       const double tpAbsDollar, const double lossCapDollar,
                       const double lastLegPnl, const long lastLegType, const int maxTotalPositions) {
    if (InpQuietExpertsLog)
        return;

    const string cur = AccountInfoString(ACCOUNT_CURRENCY);
    double sumWin, sumLoss;
    int legs;
    BasketLegProfitSums(sumWin, sumLoss, legs);

    const double needMoreForTp = tpAbsDollar - pnl;
    const double roomToHardLoss = pnl - lossCapDollar;

    Print(L("──────── Basket ────────", "──────── Basket ────────"));
    Print(L("Biểu tượng: ", "Symbol: "), _Symbol, " | ", L("Số lệnh EA: ", "EA positions: "), nPositions,
          L(" | leg để tách lãi/lỗ: ", " | legs (split): "), legs);
    Print(L("Equity: ~", "Equity: ~"), DoubleToString(eq, 2), " ", cur);
    Print(L("Tổng P+L ròng basket: ", "Basket net P+L: "), DoubleToString(pnl, 2), " ", cur,
          (pnl >= 0.0 ? L(" (lãi ròng)", " (net profit)") : L(" (lỗ ròng)", " (net loss)")));
    Print(L("Cộng P+L các lệnh đang lãi: ", "Sum profitable legs: "), DoubleToString(sumWin, 2), " ", cur);
    Print(L("Cộng P+L các lệnh đang lỗ: ", "Sum losing legs: "), DoubleToString(sumLoss, 2), " ", cur);
    Print("---");
    Print(L("Mốc chốt lời ($ cố định theo basket): ", "Take-profit (basket-locked $): "),
          DoubleToString(tpAbsDollar, 2), " ", cur,
          L(" — ref mồi ", " — bait ref "), DoubleToString(g_basketBaitValueMoney, 2), " ", cur,
          L(" × ", " × "), DoubleToString(InpTakeProfitBaitPct, 1), L("% TP", "% TP"));
    Print(L("Cần thêm ~", "Need ~"), DoubleToString(MathMax(0.0, needMoreForTp), 2), " ", cur,
          L(" P+L ròng để đạt mốc chốt lời.", " net P+L to reach take-profit."));
    Print(L("Mốc đóng khi lỗ ($ cố định theo basket): ", "Hard loss cut (basket-locked $): "),
          DoubleToString(lossCapDollar, 2), " ", cur,
          L(" — |lỗ| = ref × ", " — |loss| = ref × "), DoubleToString(InpMaxLossBaitPct, 1), L("% SL", "% SL"));
    Print(L("Còn ~", "Headroom ~"), DoubleToString(MathMax(0.0, roomToHardLoss), 2), " ", cur,
          L(" trước khi chạm mốc lỗ (từ P+L hiện tại).", " before hitting loss cut (from current net P+L)."));

    if (g_peakBasketProfit > 0.0 && InpTrailDropFromPeakPct > 0.0) {
        const double trailFloor = g_peakBasketProfit * (1.0 - InpTrailDropFromPeakPct / 100.0);
        const double aboveTrail = pnl - trailFloor;
        Print(L("Trail: đỉnh lời ", "Trail: peak "), DoubleToString(g_peakBasketProfit, 2), " ", cur,
              L(" → sàn ", " → floor "), DoubleToString(trailFloor, 2), " ", cur,
              L(" (-", " (-"), DoubleToString(InpTrailDropFromPeakPct, 1), L("% từ đỉnh)", "% from peak)"));
        Print(L("P+L cách sàn trail: ", "P+L minus trail floor: "), DoubleToString(aboveTrail, 2), " ", cur,
              L(" (≤0 là chốt theo trail).", " (≤0 triggers trail exit)."));
    } else {
        Print(L("Trail: chưa có đỉnh dương hoặc % trail = 0.", "Trail: no positive peak or trail % is 0."));
    }

    if (InpReversalClosePctOfTp > 0.0 && g_peakBasketProfit > 0.0) {
        const double givebackUsd = tpAbsDollar * (InpReversalClosePctOfTp / 100.0);
        const double reversalFloor = g_peakBasketProfit - givebackUsd;
        Print(L("Quay đầu: đóng nếu P+L dương và ≤ ", "Reversal: close if net profit >0 and ≤ "),
              DoubleToString(reversalFloor, 2), " ", cur,
              L(" (đỉnh ", " (peak "), DoubleToString(g_peakBasketProfit, 2),
              L(" − ", " − "), DoubleToString(givebackUsd, 2),
              L(" = ", " = "), DoubleToString(InpReversalClosePctOfTp, 1),
              L("%×mốc TP$).", "%×TP$)."));
    } else {
        Print(L("Quay đầu (vs mốc TP$): TẮT — InpReversalClosePctOfTp≤0 hoặc chưa có đỉnh lãi.",
                "Reversal (vs TP$ target): OFF — InpReversalClosePctOfTp≤0 or no profit peak yet."));
    }

    Print(L("Nhồi tối đa ", "Max stack "), maxTotalPositions, L(" lệnh | hedge: ", " legs | hedge: "),
          (g_hedgePlaced ? L("đã đặt", "placed") : L("chưa", "not yet")));

    if (lastLegType == POSITION_TYPE_BUY || lastLegType == POSITION_TYPE_SELL) {
        Print(L("Leg mở sau cùng: P+L ", "Latest leg P+L: "), DoubleToString(lastLegPnl, 2), " ", cur);
        if (lastLegPnl >= 0.0)
            Print(L("  → Không nhồi thêm (leg cuối đang lãi).", "  → No martingale (latest leg in profit)."));
        else
            Print(L("  → Có thể nhồi nếu giá đủ bước pip và chưa đủ tối đa lệnh.",
                    "  → Martingale if price step hit and stack not full."));
    }
    Print(L("────────────────────────", "────────────────────────"));
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
    if (!HybridSignal_FetchForecast(fd, pu, pd, pat, note, msg, false))
        return;

    g_panel_have_signal = true;
    g_panel_fd = fd;
    g_panel_pu = pu;
    g_panel_pd = pd;
    g_panel_pat = pat;
    g_panel_note = note;
    g_panel_sig_time = TimeCurrent();

    if (!InpQuietExpertsLog) {
        PrintTextChunked(L("[HYBRID] ", "[HYBRID] "), msg);
        Print(L("Pattern: ", "Pattern: "), pat, " | ", L("Ghi chú: ", "Note: "), note);
        Print(L("Hướng cuối / xác suất: ", "Final / probs: "), fd,
              " | up ", DoubleToString(pu * 100.0, 1), "% down ", DoubleToString(pd * 100.0, 1), "%");
    }

    if (fd == 0) {
        if (!InpQuietExpertsLog)
            Print(L("Tín hiệu NEUTRAL — không vào lệnh mồi.", "NEUTRAL signal — no bait order."));
        return;
    }

    const ENUM_ORDER_TYPE t = (fd > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    const double vol = VolumeFromLotPercentOfOneLot(InpBaitLotPct);
    const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if (vol < vmin) {
        Print(L("InpBaitLotPct quá nhỏ — lot < SYMBOL_VOLUME_MIN.", "InpBaitLotPct too small — lot below SYMBOL_VOLUME_MIN."));
        return;
    }
    const string cmt = StringFormat("HYBRID_%s_%s", (fd > 0) ? "LONG" : "SHORT", pat);
    if (OpenMarket(t, vol, cmt)) {
        if (!InpQuietExpertsLog)
            Print(L("Đã mở lệnh mồi theo dự báo ", "Opened bait per forecast "),
                  (fd > 0) ? "LONG" : "SHORT", " vol=", vol);
        g_peakBasketProfit = 0.0;
        g_hedgePlaced = false;
        ResetReversalOppositeState();
        g_baitLotVolume = vol;
        g_baitOpenPrice = g_trade.ResultPrice();
        g_basketBuy = (fd > 0);
        if (g_baitOpenPrice <= 0.0) {
            ulong rtk;
            double rop;
            datetime rot;
            long rty;
            if (LatestOurPosition(rtk, rop, rot, rty))
                g_baitOpenPrice = rop;
        }
        LockBasketTpLossFromBait();
    }
}

void ManageBasket() {
    const int n = CountOurPositions();
    if (n <= 0)
        return;

    RecoverBasketGlobalsIfNeeded();
    const double eq = MathMax(AccountInfoDouble(ACCOUNT_EQUITY), 1.0);
    EnsureBasketTpLossLocked(eq);
    const int nSame = CountOurSameDirectionBasketLegs(g_basketBuy);

    const double pnl = BasketProfitMoney();
    const double tpAbs = g_basketTpMoney;
    const double lossCap = -g_basketLossMoney;

    // Chỉ ghi nhận đỉnh khi lãi đủ lớn so với nhiễu (tránh đỉnh ~0 làm trailFloor cực nhỏ).
    const double minPeakProfitMoney = MathMax(tpAbs * 0.0001, eq * 1e-6);
    if (pnl > g_peakBasketProfit && pnl >= minPeakProfitMoney)
        g_peakBasketProfit = pnl;

    if (pnl >= tpAbs) {
        const string cur = AccountInfoString(ACCOUNT_CURRENCY);
        string dVi = "Luật: đóng khi P+L ròng >= mốc TP $ đã khóa khi mở basket.\n";
        dVi += "Khóa: ref lệnh mồi " + DoubleToString(g_basketBaitValueMoney, 2) + " " + cur + " × " + DoubleToString(InpTakeProfitBaitPct, 2) + "% → TP = " + DoubleToString(tpAbs, 2) + " " + cur + ".\n";
        dVi += "Kiểm tra: P+L " + DoubleToString(pnl, 2) + " >= " + DoubleToString(tpAbs, 2) + ".\n";
        dVi += "Ref = giá trị vị thế lệnh mồi (lot×contract×giá mở); muốn đổi mốc: chỉnh % trước basket mới.";
        string dEn = "Rule: close when net P+L >= basket-locked TP $.\n";
        dEn += "Locked: bait ref " + DoubleToString(g_basketBaitValueMoney, 2) + " " + cur + " × " + DoubleToString(InpTakeProfitBaitPct, 2) + "% → TP = " + DoubleToString(tpAbs, 2) + " " + cur + ".\n";
        dEn += "Check: P+L " + DoubleToString(pnl, 2) + " >= " + DoubleToString(tpAbs, 2) + ".\n";
        dEn += "Ref = bait notional (lot×contract×open); change % before a new basket.";
        LogBasketExitBanner("Chốt lời (TP $ từ % lệnh mồi)", "Take profit (locked $ from bait %)", eq, pnl, cur, dVi, dEn);
        CloseAllOurPositionsAndPendings();
        g_peakBasketProfit = 0.0;
        g_hedgePlaced = false;
        ResetReversalOppositeState();
        return;
    }

    if (pnl <= lossCap) {
        const string cur = AccountInfoString(ACCOUNT_CURRENCY);
        string dVi = "Luật: đóng khi P+L ròng <= −mốc |lỗ| $ đã khóa khi mở basket.\n";
        dVi += "Khóa: ref lệnh mồi " + DoubleToString(g_basketBaitValueMoney, 2) + " " + cur + " × " + DoubleToString(InpMaxLossBaitPct, 2) + "% → cắt tại P+L = " + DoubleToString(lossCap, 2) + " " + cur + ".\n";
        dVi += "Kiểm tra: P+L " + DoubleToString(pnl, 2) + " <= " + DoubleToString(lossCap, 2) + ".\n";
        dVi += "Giảm InpMaxLossBaitPct để cắt sớm hơn (mốc $ thu hẹp).";
        string dEn = "Rule: close when net P+L <= −basket-locked loss magnitude $.\n";
        dEn += "Locked: bait ref " + DoubleToString(g_basketBaitValueMoney, 2) + " " + cur + " × " + DoubleToString(InpMaxLossBaitPct, 2) + "% → cut at " + DoubleToString(lossCap, 2) + " " + cur + ".\n";
        dEn += "Check: P+L " + DoubleToString(pnl, 2) + " <= " + DoubleToString(lossCap, 2) + ".\n";
        dEn += "Lower InpMaxLossBaitPct for a tighter $ stop.";
        LogBasketExitBanner("Cắt lỗ cứng ($ từ % lệnh mồi)", "Hard stop (locked $ from bait %)", eq, pnl, cur, dVi, dEn);
        CloseAllOurPositionsAndPendings();
        g_peakBasketProfit = 0.0;
        g_hedgePlaced = false;
        ResetReversalOppositeState();
        return;
    }

    // Trail chỉ áp dụng khi basket còn lãi ròng: nếu P+L âm thì không đóng bằng trail (tránh bug: đỉnh ~ vài cent
    // do nhiễu spread → sàn trail cực nhỏ → P+L âm vẫn thỏa pnl < sàn → đóng nhầm ngay sau mồi).
    if (g_peakBasketProfit > 0.0 && InpTrailDropFromPeakPct > 0.0) {
        const double trailFloor = g_peakBasketProfit * (1.0 - InpTrailDropFromPeakPct / 100.0);
        if (pnl >= 0.0 && pnl < trailFloor) {
            const string cur = AccountInfoString(ACCOUNT_CURRENCY);
            string dVi = "Luật (chỉ khi P+L ròng >= 0): P+L < đỉnh × (1 − InpTrailDropFromPeakPct/100).\n";
            dVi += "Input InpTrailDropFromPeakPct = " + DoubleToString(InpTrailDropFromPeakPct, 2) + "%.\n";
            dVi += "Đỉnh đã ghi nhận g_peakBasketProfit = " + DoubleToString(g_peakBasketProfit, 2) + " → sàn trail = " + DoubleToString(trailFloor, 2) + " " + cur + ".\n";
            dVi += "Kiểm tra: P+L " + DoubleToString(pnl, 2) + " < " + DoubleToString(trailFloor, 2) + ".\n";
            dVi += "% nhỏ (vd 5%) → chỉ hồi nhẹ từ đỉnh đã chốt; có thể thấy 'nhanh' khi giá quay đầu.";
            string dEn = "Rule (only if net P+L >= 0): P+L < peak × (1 − InpTrailDropFromPeakPct/100).\n";
            dEn += "Input InpTrailDropFromPeakPct = " + DoubleToString(InpTrailDropFromPeakPct, 2) + "%.\n";
            dEn += "Tracked peak g_peakBasketProfit = " + DoubleToString(g_peakBasketProfit, 2) + " → trail floor = " + DoubleToString(trailFloor, 2) + " " + cur + ".\n";
            dEn += "Small % exits soon after small pullback from peak.";
            LogBasketExitBanner("Chốt trail (lùi từ đỉnh lãi)", "Trailing profit exit", eq, pnl, cur, dVi, dEn);
            CloseAllOurPositionsAndPendings();
            g_peakBasketProfit = 0.0;
            g_hedgePlaced = false;
            ResetReversalOppositeState();
            return;
        }
    }

    if (InpReversalClosePctOfTp > 0.0 && pnl > 0.0 && g_peakBasketProfit > 0.0) {
        const double givebackUsd = tpAbs * (InpReversalClosePctOfTp / 100.0);
        const double reversalFloor = g_peakBasketProfit - givebackUsd;
        if (pnl <= reversalFloor) {
            const string cur = AccountInfoString(ACCOUNT_CURRENCY);
            string dVi = "Luật: P+L > 0 và P+L <= đỉnh − (mốc TP $ × InpReversalClosePctOfTp/100).\n";
            dVi += "Mốc TP $ (tpAbs) = " + DoubleToString(tpAbs, 2) + "; Input InpReversalClosePctOfTp = " + DoubleToString(InpReversalClosePctOfTp, 2) + "% → ngưỡng hồi $ = " + DoubleToString(givebackUsd, 2) + ".\n";
            dVi += "Đỉnh " + DoubleToString(g_peakBasketProfit, 2) + " → sàn quay đầu " + DoubleToString(reversalFloor, 2) + " " + cur + "; P+L hiện " + DoubleToString(pnl, 2) + ".\n";
            dVi += "Chốt khi P+L hồi đủ so với đỉnh; mốc TP $ là giá trị khóa theo basket (không trôi theo equity). Tắt: InpReversalClosePctOfTp=0.";
            string dEn = "Rule: net profit > 0 and P+L <= peak − (tpAbs × InpReversalClosePctOfTp/100).\n";
            dEn += "tpAbs = " + DoubleToString(tpAbs, 2) + "; InpReversalClosePctOfTp = " + DoubleToString(InpReversalClosePctOfTp, 2) + "% → giveback $ = " + DoubleToString(givebackUsd, 2) + ".\n";
            dEn += "Peak / reversal floor / current P+L as above. Set InpReversalClosePctOfTp=0 to disable.";
            LogBasketExitBanner("Chốt quay đầu (hồi lãi từ đỉnh)", "Reversal exit (giveback vs TP$)", eq, pnl, cur, dVi, dEn);
            CloseAllOurPositionsAndPendings();
            g_peakBasketProfit = 0.0;
            g_hedgePlaced = false;
            ResetReversalOppositeState();
            return;
        }
    }

    ulong lastTicket = 0;
    double lastOpen = 0.0;
    datetime lastOt = 0;
    long lastType = -1;
    LatestOurPosition(lastTicket, lastOpen, lastOt, lastType);
    double profitLast = 0.0;
    if (lastTicket != 0 && PositionSelectByTicket(lastTicket))
        profitLast = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

    const int maxTotal = 1 + InpMaxMartingaleAdds;

    if (InpBasketLogIntervalSec <= 0 || TimeCurrent() - g_lastBasketStatusLog >= InpBasketLogIntervalSec) {
        g_lastBasketStatusLog = TimeCurrent();
        LogBasketSnapshot(n, pnl, eq, tpAbs, lossCap, profitLast, lastType, maxTotal);
    }

    // (1) Pip bất lợi so mồi → 1 lệnh quay đầu (ngược basket). (2) Theo dõi giá mở lệnh đó; pip bất lợi so lệnh đó → thêm 1 lệnh ngược basket.
    if (InpUseReversalOppositeOnBaitPips && InpReversalOppositeTriggerPips > 0.0 && InpReversalOppositeLotPctOfBait > 0.0) {
        const double pipRv = PipSizeLocal();
        const double bidRv = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        const double askRv = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        const double dRv = InpReversalOppositeTriggerPips * pipRv;
        const ENUM_ORDER_TYPE oppBasket = g_basketBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        const double volRv = ReversalOppositeVolumeFromBaitLot();
        const double vminRv = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

        if (!g_reversalOppositePlaced && g_baitOpenPrice > 0.0) {
            bool adverseFromBait = false;
            if (g_basketBuy)
                adverseFromBait = (bidRv <= g_baitOpenPrice - dRv);
            else
                adverseFromBait = (askRv >= g_baitOpenPrice + dRv);
            if (adverseFromBait && volRv >= vminRv) {
                if (OpenMarket(oppBasket, volRv, "HYBRID_REV_OPP")) {
                    g_reversalOppositePlaced = true;
                    g_reversalFirstLegOpenPrice = g_trade.ResultPrice();
                    if (g_reversalFirstLegOpenPrice <= 0.0) {
                        ulong t2;
                        double o2;
                        datetime tm2;
                        long ty2;
                        if (LatestOurPosition(t2, o2, tm2, ty2)) {
                            const bool revLeg = (g_basketBuy && ty2 == POSITION_TYPE_SELL) || (!g_basketBuy && ty2 == POSITION_TYPE_BUY);
                            if (revLeg)
                                g_reversalFirstLegOpenPrice = o2;
                        }
                    }
                    Print(L("Lệnh quay đầu (pip so mồi): ngược ≥ ", "First reversal (vs bait): adverse ≥ "),
                          DoubleToString(InpReversalOppositeTriggerPips, 1),
                          L(" pip | lot ", " pip | lot "),
                          DoubleToString(InpReversalOppositeLotPctOfBait, 1), L("% lot mồi.", "% of bait lot."));
                }
            } else if (adverseFromBait && volRv < vminRv && !InpQuietExpertsLog) {
                Print(L("HYBRID_REV_OPP: lot sau chuẩn hóa < SYMBOL_VOLUME_MIN — không mở.", "HYBRID_REV_OPP: normalized lot < min — skip."));
            }
        } else if (g_reversalOppositePlaced && !g_reversalOppositeFollowUpPlaced && g_reversalFirstLegOpenPrice > 0.0) {
            bool adverseFromFirstRev = false;
            if (g_basketBuy)
                adverseFromFirstRev = (askRv >= g_reversalFirstLegOpenPrice + dRv); // lệnh quay đầu = SELL
            else
                adverseFromFirstRev = (bidRv <= g_reversalFirstLegOpenPrice - dRv); // lệnh quay đầu = BUY
            if (adverseFromFirstRev && volRv >= vminRv) {
                if (OpenMarket(oppBasket, volRv, "HYBRID_REV_OPP2")) {
                    g_reversalOppositeFollowUpPlaced = true;
                    Print(L("Lệnh quay đầu bị ngược thêm ≥ ", "First reversal adverse ≥ "),
                          DoubleToString(InpReversalOppositeTriggerPips, 1),
                          L(" pip → thêm 1 lệnh ngược basket (lot ", " pip → extra opposite basket leg (lot "),
                          DoubleToString(InpReversalOppositeLotPctOfBait, 1), L("% mồi).", "% bait)."));
                }
            } else if (adverseFromFirstRev && volRv < vminRv && !InpQuietExpertsLog) {
                Print(L("HYBRID_REV_OPP2: lot < min — không mở.", "HYBRID_REV_OPP2: lot < min — skip."));
            }
        }
    }

    if (lastTicket == 0 || lastType < 0)
        return;

    if (profitLast >= 0.0)
        return;
    if (nSame >= maxTotal) {
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
                const double hv = HedgeVolumeFromBaitLot();
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
    double triggerLvl = 0.0;
    const int dig = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    if (InpMartingaleFromPrevLegPips > 0.0) {
        double prevLegOpen = 0.0;
        if (!LatestSameDirectionOpenPrice(g_basketBuy, prevLegOpen))
            return;
        const double d = InpMartingaleFromPrevLegPips * pip;
        if (g_basketBuy) {
            triggerLvl = prevLegOpen - d;
            stepHit = (bid <= triggerLvl);
        } else {
            triggerLvl = prevLegOpen + d;
            stepHit = (ask >= triggerLvl);
        }
        if (!stepHit)
            return;
        const ENUM_ORDER_TYPE t = g_basketBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        const double addVol = VolumeFromLotPercentOfOneLot(InpBaitLotPct);
        if (OpenMarket(t, addVol, "HYBRID_ADD"))
            Print(L("Nhồi theo leg trước: bid/ask đạt mức so với giá vào leg cùng chiều mới nhất (",
                    "Prev-leg add: vs latest same-dir entry ("),
                  DoubleToString(InpMartingaleFromPrevLegPips, 1),
                  L(" pip bất lợi) → ngưỡng ~", " adverse pip) → thresh ~"), DoubleToString(triggerLvl, dig),
                  L(" | giá vào leg trước ", " | prev entry "), DoubleToString(prevLegOpen, dig));
        return;
    }

    if (g_baitOpenPrice <= 0.0)
        return;

    const double stepDist = InpMartingaleStepPips * pip;
    const int idxNext = nSame;
    if (g_basketBuy && bid <= g_baitOpenPrice - idxNext * stepDist)
        stepHit = true;
    if (!g_basketBuy && ask >= g_baitOpenPrice + idxNext * stepDist)
        stepHit = true;

    if (!stepHit)
        return;

    const ENUM_ORDER_TYPE t = g_basketBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    const double vol = VolumeFromLotPercentOfOneLot(InpBaitLotPct);
    if (OpenMarket(t, vol, "HYBRID_ADD")) {
        triggerLvl = g_basketBuy ? (g_baitOpenPrice - idxNext * stepDist) : (g_baitOpenPrice + idxNext * stepDist);
        Print(L("Nhồi cùng chiều: đạt mức giá_mồi ± n×pip (n=", "Same-dir add: bait ± n×pip (n="),
              idxNext, ") ", L("→ mức ~", "→ lvl ~"), DoubleToString(triggerLvl, dig));
    }
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
    ResetReversalOppositeState();
    g_baitLotVolume = 0.0;
    g_baitOpenPrice = 0.0;
    g_basketBuy = true;
    ResetBasketMoneyRules();

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
    if (InpBaitLotPct <= 0.0) {
        Print(L("InpBaitLotPct phải > 0.", "InpBaitLotPct must be > 0."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpHedgeLotPctOfBait <= 0.0) {
        Print(L("InpHedgeLotPctOfBait phải > 0.", "InpHedgeLotPctOfBait must be > 0."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpUseReversalOppositeOnBaitPips && InpReversalOppositeTriggerPips > 0.0 && InpReversalOppositeLotPctOfBait <= 0.0) {
        Print(L("InpReversalOppositeLotPctOfBait phải > 0 khi bật pip ngược mồi.", "InpReversalOppositeLotPctOfBait must be > 0 when bait adverse pip add is on."));
        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpTakeProfitBaitPct <= 0.0) {
        Print(L("InpTakeProfitBaitPct phải > 0.", "InpTakeProfitBaitPct must be > 0."));
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpMaxLossBaitPct <= 0.0) {
        Print(L("InpMaxLossBaitPct phải > 0.", "InpMaxLossBaitPct must be > 0."));
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
    ResetReversalOppositeState();
    g_baitLotVolume = 0.0;
    g_baitOpenPrice = 0.0;
    g_basketBuy = true;
    g_panel_have_signal = false;
    ResetBasketMoneyRules();

    CloseAllOurPositionsAndPendings();
    Print(L("Khởi tạo: đã hủy pending và đóng position của EA (magic).",
            "Init: removed pendings and closed EA positions (magic)."));

    if (InpShowPanel)
        UiPanelCreate();

    EventSetTimer(1);
    UiPanelUpdate();
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
