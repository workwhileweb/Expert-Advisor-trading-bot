//+------------------------------------------------------------------+
//| Hybrid_LSTM_TA_SignalTrade.mq5                                   |
//| Dự báo long/short từ Hybrid_LSTM_TA_Signal.mqh + chiến lược @1   |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version "1.00"
#property description "LSTM+TA; lot mồi/nhồi = % của 1.00 lot; hedge = % lot so với lot mồi."

#include <Trade/Trade.mqh>
#include "Hybrid_LSTM_TA_Signal.mqh"

input group "=== Quét tín hiệu (khi không có basket) ===" input bool InpHybridOnNewBar = true; // Quét khi có nến mới
input int InpHybridScanSeconds = 1;                                                            // Quét tối thiểu mỗi N giây (0 = tắt, chỉ nến mới nếu bật trên)

input group "=== Giao dịch ===" input ulong InpMagic = 910027;
input int InpSlippagePoints = 30;
input double InpBaitLotPct = 10.0;               // % của 1.00 lot (10 = 0.10 lot) — lệnh mồi & nhồi
input int InpMaxMartingaleAdds = 2;              // Số lệnh nhồi thêm (tổng tối đa = 1 + giá trị này)
input double InpMartingaleStepPips = 20.0;       // Khi FromPrevLegPips=0: giá_mồi ± n×pip (n=số leg cùng chiều; BUY −, SELL +)
input double InpMartingaleFromPrevLegPips = 0.0; // 0=tắt. >0: nhồi khi giá đi thêm X pip bất lợi so với giá vào leg cùng chiều mới nhất (mồi hoặc nhồi trước)
input double InpTakeProfitEquityPct = 5.0;       // Chốt khi P+L ròng >= equity×%/100 ($). % nhỏ hoặc equity nhỏ → mốc $ nhỏ → dễ chốt rất nhanh
input double InpMaxLossEquityPct = 50.0;         // Đóng khi P+L ròng <= −equity×%/100 ($). Mặc định −50% equity (xa); giảm % → cắt sớm hơn
input double InpTrailDropFromPeakPct = 5.0;      // Khi P+L ròng dương: đỉnh đã đạt − giảm % từ đỉnh → chốt (vd đỉnh 100→sàn 95). % nhỏ → chốt sớm khi hồi nhẹ
input double InpReversalClosePctOfTp = 5.0;      // 0=tắt. P+L>0: hồi từ đỉnh ≥ (mốc TP $ × %/100) → đóng. % nhỏ hoặc equity nhỏ → đóng nhanh khi giá quay đầu
input bool InpUseHedge = true;                   // Tới max nhồi + giá vượt thêm X pip: mở hedge ngược
input double InpHedgeBeyondPips = 10.0;          // Pip vượt qua giá vào cuối (ngược chiều lệnh chính)
input double InpHedgeLotPctOfBait = 500.0;       // % lot so với lot lệnh mồi (500 = 5×) — tiền vào hedge quay đầu
input int InpBasketLogIntervalSec = 5;           // Mỗi N giây in trạng thái basket (0 = mỗi lần quét)
input int InpLogMaxChunkChars = 900;             // Chia dòng log dài (0 = một dòng)

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
datetime g_lastBasketStatusLog = 0;
double g_baitLotVolume = 0.0; // lot lệnh mồi vừa mở (cho tỉ lệ hedge)
double g_baitOpenPrice = 0.0; // giá vào mồi — mốc nhồi theo n×pip
bool g_basketBuy = true;      // chiều basket (khớp lệnh mồi)

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
        const int nSame = CountOurSameDirectionBasketLegs(g_basketBuy);
        const double pnl = BasketProfitMoney();
        const double tpAbs = eq * (InpTakeProfitEquityPct / 100.0);
        const double lossCap = -eq * (InpMaxLossEquityPct / 100.0);
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
        t += "  hedge " + (g_hedgePlaced ? "OK" : "--") + "\n";
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
    Print(L("Mốc chốt lời (", "Take-profit ("), DoubleToString(InpTakeProfitEquityPct, 1),
          L("% equity): ~", "% equity): ~"), DoubleToString(tpAbsDollar, 2), " ", cur);
    Print(L("Cần thêm ~", "Need ~"), DoubleToString(MathMax(0.0, needMoreForTp), 2), " ", cur,
          L(" P+L ròng để đạt mốc chốt lời.", " net P+L to reach take-profit."));
    Print(L("Mốc đóng khi lỗ (", "Hard loss cut ("), DoubleToString(InpMaxLossEquityPct, 1),
          L("% equity): ~", "% equity): ~"), DoubleToString(lossCapDollar, 2), " ", cur,
          L(" P+L ròng.", " net P+L."));
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
    }
}

void ManageBasket() {
    const int n = CountOurPositions();
    if (n <= 0)
        return;

    RecoverBasketGlobalsIfNeeded();
    const int nSame = CountOurSameDirectionBasketLegs(g_basketBuy);

    const double eq = MathMax(AccountInfoDouble(ACCOUNT_EQUITY), 1.0);
    const double pnl = BasketProfitMoney();
    const double tpAbs = eq * (InpTakeProfitEquityPct / 100.0);
    const double lossCap = -eq * (InpMaxLossEquityPct / 100.0);

    // Chỉ ghi nhận đỉnh khi lãi đủ lớn so với nhiễu (tránh đỉnh ~0 làm trailFloor cực nhỏ).
    const double minPeakProfitMoney = MathMax(tpAbs * 0.0001, eq * 1e-6);
    if (pnl > g_peakBasketProfit && pnl >= minPeakProfitMoney)
        g_peakBasketProfit = pnl;

    if (pnl >= tpAbs) {
        const string cur = AccountInfoString(ACCOUNT_CURRENCY);
        string dVi = "Luật: đóng khi P+L ròng >= equity × (InpTakeProfitEquityPct / 100).\n";
        dVi += "Input InpTakeProfitEquityPct = " + DoubleToString(InpTakeProfitEquityPct, 2) + "% → mốc TP tiền = " + DoubleToString(tpAbs, 2) + " " + cur + ".\n";
        dVi += "Kiểm tra: P+L " + DoubleToString(pnl, 2) + " >= " + DoubleToString(tpAbs, 2) + " (" + cur + ").\n";
        dVi += "Vì sao dễ chốt nhanh: mốc TP là một phần equity hiện tại ($); equity nhỏ hoặc lot lớn → ít pip đã đủ $. Muốn khó chốt hơn: tăng InpTakeProfitEquityPct hoặc giảm lot.";
        string dEn = "Rule: close when net P+L >= equity × (InpTakeProfitEquityPct / 100).\n";
        dEn += "Input InpTakeProfitEquityPct = " + DoubleToString(InpTakeProfitEquityPct, 2) + "% → TP target = " + DoubleToString(tpAbs, 2) + " " + cur + ".\n";
        dEn += "Check: P+L " + DoubleToString(pnl, 2) + " >= " + DoubleToString(tpAbs, 2) + ".\n";
        dEn += "Why fast: TP is a fraction of current equity in money; small equity or large lot reaches $ quickly. Raise InpTakeProfitEquityPct or reduce volume for slower exits.";
        LogBasketExitBanner("Chốt lời (TP theo % equity)", "Take profit (% equity)", eq, pnl, cur, dVi, dEn);
        CloseAllOurPositionsAndPendings();
        g_peakBasketProfit = 0.0;
        g_hedgePlaced = false;
        return;
    }

    if (pnl <= lossCap) {
        const string cur = AccountInfoString(ACCOUNT_CURRENCY);
        string dVi = "Luật: đóng khi P+L ròng <= −equity × (InpMaxLossEquityPct / 100).\n";
        dVi += "Input InpMaxLossEquityPct = " + DoubleToString(InpMaxLossEquityPct, 2) + "% → mốc cắt lỗ = " + DoubleToString(lossCap, 2) + " " + cur + ".\n";
        dVi += "Kiểm tra: P+L " + DoubleToString(pnl, 2) + " <= " + DoubleToString(lossCap, 2) + ".\n";
        dVi += "Mặc định 50% equity là xa; nếu giảm input (vd 5–10%) thì cắt rất nhanh khi basket âm.";
        string dEn = "Rule: close when net P+L <= −equity × (InpMaxLossEquityPct / 100).\n";
        dEn += "Input InpMaxLossEquityPct = " + DoubleToString(InpMaxLossEquityPct, 2) + "% → stop level = " + DoubleToString(lossCap, 2) + " " + cur + ".\n";
        dEn += "Check: P+L " + DoubleToString(pnl, 2) + " <= " + DoubleToString(lossCap, 2) + ".\n";
        dEn += "Lower % makes hard stop fire sooner.";
        LogBasketExitBanner("Cắt lỗ cứng (% equity)", "Hard stop loss (% equity)", eq, pnl, cur, dVi, dEn);
        CloseAllOurPositionsAndPendings();
        g_peakBasketProfit = 0.0;
        g_hedgePlaced = false;
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
            dVi += "Chốt nhanh khi equity nhỏ (tpAbs nhỏ) hoặc % nhỏ → ngưỡng $ nhỏ; tắt bằng InpReversalClosePctOfTp=0.";
            string dEn = "Rule: net profit > 0 and P+L <= peak − (tpAbs × InpReversalClosePctOfTp/100).\n";
            dEn += "tpAbs = " + DoubleToString(tpAbs, 2) + "; InpReversalClosePctOfTp = " + DoubleToString(InpReversalClosePctOfTp, 2) + "% → giveback $ = " + DoubleToString(givebackUsd, 2) + ".\n";
            dEn += "Peak / reversal floor / current P+L as above. Set InpReversalClosePctOfTp=0 to disable.";
            LogBasketExitBanner("Chốt quay đầu (hồi lãi từ đỉnh)", "Reversal exit (giveback vs TP$)", eq, pnl, cur, dVi, dEn);
            CloseAllOurPositionsAndPendings();
            g_peakBasketProfit = 0.0;
            g_hedgePlaced = false;
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
    g_baitLotVolume = 0.0;
    g_baitOpenPrice = 0.0;
    g_basketBuy = true;

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
    g_baitLotVolume = 0.0;
    g_baitOpenPrice = 0.0;
    g_basketBuy = true;
    g_panel_have_signal = false;

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
