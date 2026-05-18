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
input bool InpShowPanel = true;            // Hiển thị bảng (mỗi dòng = 1 OBJ_LABEL — ổn định trên mọi bản MT5)
input int  InpPanelCorner = 0;             // Góc: 0=trên-trái 1=trên-phải 2=dưới-trái 3=dưới-phải
input int  InpPanelX = 10;                 // Lệch X (pixel)
input int  InpPanelY = 25;                 // Lệch Y (pixel)
input int  InpPanelWidth = 400;            // Rộng nền panel
input int  InpPanelHeight = 340;           // Cao nền tối thiểu (tự giãn theo số dòng)
input int  InpPanelFontSize = 10;          // Cỡ chữ panel
input int  InpPanelLineGap = 12;           // Khoảng cách thêm giữa các dòng (pixel, cộng vào cỡ chữ)
input int  InpPanelBgOpacity = 50;         // Độ mờ nền đen (0=trong suốt, 100=đặc)

#define HSSW_UI_BG "HSSW_PANEL_BG"
#define HSSW_UI_LINE_PFX "HSSW_PL_"
#define HSSW_PANEL_MAX_LINES 32
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
int      g_panelVisibleLines = 0;

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

string FmtMoney(const double amount) {
    return DoubleToString(amount, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY);
}

string FmtPctAndMoney(const double pct, const double refMoney) {
    if (refMoney <= 0.0 || !MathIsValidNumber(refMoney))
        return DoubleToString(pct, 1) + "%";
    return DoubleToString(pct, 1) + "% (= " + FmtMoney(refMoney * pct / 100.0) + ")";
}

double MarketPriceForEstimate() {
    double px = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (px <= 0.0)
        px = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if (px <= 0.0)
        px = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
    if (px <= 0.0)
        px = iClose(_Symbol, _Period, 0);
    return px;
}

double NotionalFromLotPrice(const double lot, const double openPrice) {
    if (lot <= 0.0 || openPrice <= 0.0)
        return 0.0;
    const double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    const double nominal = MathAbs(lot * cs * openPrice);
    if (nominal > 0.0 && MathIsValidNumber(nominal))
        return nominal;
    double margin = 0.0;
    if (OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, openPrice, margin) && margin > 0.0)
        return margin;
    return 0.0;
}

double BaitRefMoneyActive() {
    if (g_basketRefMoney > 0.0)
        return g_basketRefMoney;
    const double lot = (g_firstLot > 0.0) ? g_firstLot : NormalizeVolumeLocal(InpFirstLot);
    const double px = (g_firstOpenPrice > 0.0) ? g_firstOpenPrice : MarketPriceForEstimate();
    return NotionalFromLotPrice(lot, px);
}

string FmtLotMultResult(const double baseLot, const double mult, const double resultVol) {
    return DoubleToString(baseLot, 2) + L(" lot × ", " lot × ") + DoubleToString(mult, 2) + L(" → ", " → ") +
           DoubleToString(resultVol, 2) + L(" lot (sau chuẩn hóa)", " lot (normalized)");
}

string FmtLotPlanLine() {
    const double lot1 = NormalizeVolumeLocal(InpFirstLot);
    const double lot2 = NormalizeVolumeLocal(lot1 * InpMartingaleMult);
    const double lot3 = NormalizeVolumeLocal(lot2 * InpMartingaleMult);
    const double lotRev = NormalizeVolumeLocal(lot1 * InpReversalMult);
    return L("Kế hoạch lot: mồi ", "Lot plan: bait ") + DoubleToString(lot1, 2) + L(" | nhồi ", " | add ") +
           DoubleToString(lot2, 2) + ", " + DoubleToString(lot3, 2) + L(" | quay đầu ", " | reversal ") +
           DoubleToString(lotRev, 2);
}

string FmtSidewayRangeDetail() {
    const double pip = PipSizeLocal();
    const int dig = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    const double priceRange = g_sidewayRangePips * pip;
    const double maxPrice = InpSidewayMaxRangePips * pip;
    return L("Biên đo ", "Measured ") + DoubleToString(g_sidewayRangePips, 2) + L(" pip (", " pip (") +
           DoubleToString(priceRange, dig) + L(" giá) · ngưỡng ≤ ", " price) · max ≤ ") +
           DoubleToString(InpSidewayMaxRangePips, 2) + L(" pip (", " pip (") + DoubleToString(maxPrice, dig) + L(" giá)", " price)");
}

string FmtBasketTpExplain(const bool useLocked) {
    const double ref = BaitRefMoneyActive();
    const double tp = useLocked && g_basketTpMoney > 0.0 ? g_basketTpMoney : ref * (InpBasketTakeProfitPct / 100.0);
    return L("Chốt lời basket: mốc ", "Basket TP: target ") + FmtMoney(tp) + L(" (", " (") +
           FmtPctAndMoney(InpBasketTakeProfitPct, ref) + L(", ref mồi ", ", bait ref ") + FmtMoney(ref) + ")";
}

string FmtBasketSlExplain(const bool useLocked) {
    if (InpBasketStopLossPct <= 0.0)
        return L("Cắt lỗ basket: tắt", "Basket SL: off");
    const double ref = BaitRefMoneyActive();
    const double sl = useLocked && g_basketSlMoney > 0.0 ? g_basketSlMoney : ref * (InpBasketStopLossPct / 100.0);
    return L("Cắt lỗ basket: mốc −", "Basket SL: cut at −") + FmtMoney(sl) + L(" (", " (") +
           FmtPctAndMoney(InpBasketStopLossPct, ref) + L(", ref mồi ", ", bait ref ") + FmtMoney(ref) + ")";
}

string FmtAccountTpExplain() {
    if (InpAccountTakeProfitPct <= 0.0)
        return "";
    const double bal = (g_balanceAtBasketOpen > 0.0) ? g_balanceAtBasketOpen : AccountInfoDouble(ACCOUNT_BALANCE);
    const double thr = bal * (InpAccountTakeProfitPct / 100.0);
    return L("TK chốt lời: +", "Acct TP: +") + FmtMoney(thr) + L(" equity (", " equity (") +
           FmtPctAndMoney(InpAccountTakeProfitPct, bal) + L(" balance ", " of balance ") + FmtMoney(bal) + ")";
}

string FmtAccountSlExplain() {
    if (InpAccountStopLossPct <= 0.0)
        return "";
    const double bal = (g_balanceAtBasketOpen > 0.0) ? g_balanceAtBasketOpen : AccountInfoDouble(ACCOUNT_BALANCE);
    const double thr = bal * (InpAccountStopLossPct / 100.0);
    return L("TK cắt lỗ: −", "Acct SL: −") + FmtMoney(thr) + L(" equity (", " equity (") +
           FmtPctAndMoney(InpAccountStopLossPct, bal) + L(" balance ", " of balance ") + FmtMoney(bal) + ")";
}

string UiTruncate(const string s, const int maxLen) {
    if (maxLen <= 0 || StringLen(s) <= maxLen)
        return s;
    return StringSubstr(s, 0, maxLen - 3) + "...";
}

string UiPanelLineName(const int idx) {
    return HSSW_UI_LINE_PFX + IntegerToString(idx);
}

void UiPanelDeleteLine(const int idx) {
    ObjectDelete(0, UiPanelLineName(idx));
}

void UiPanelDelete() {
    ObjectDelete(0, "HSSW_PANEL_TX"); // legacy OBJ_EDIT
    for (int i = 0; i < HSSW_PANEL_MAX_LINES; i++)
        UiPanelDeleteLine(i);
    ObjectDelete(0, HSSW_UI_BG);
    g_panelVisibleLines = 0;
    ChartRedraw(0);
}

uchar UiPanelBgAlpha() {
    const int pct = MathMax(0, MathMin(100, InpPanelBgOpacity));
    return (uchar)MathMax(0, MathMin(255, (int)MathRound(255.0 * pct / 100.0)));
}

void UiPanelEnsureBackground(const int corner, const int w, const int h) {
    const uchar alpha = UiPanelBgAlpha();
    const color bgFill = (color)ColorToARGB(clrBlack, alpha);
    const color bgBorder = (color)ColorToARGB(C'90,90,90', alpha);
    if (ObjectFind(0, HSSW_UI_BG) < 0) {
        ObjectCreate(0, HSSW_UI_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_BACK, false);
        ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_HIDDEN, true);
    }
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_BGCOLOR, bgFill);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_COLOR, bgBorder);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_XDISTANCE, InpPanelX);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_YDISTANCE, InpPanelY);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, HSSW_UI_BG, OBJPROP_YSIZE, h);
}

bool UiPanelTextHas(const string text, const string needle) {
    return (StringFind(text, needle) >= 0);
}

color UiPanelColorForLine(const string text, const int lineIdx) {
    if (StringLen(text) == 0)
        return C'70,70,75';

    if (UiPanelTextHas(text, "━━") || UiPanelTextHas(text, "Hybrid Sideway"))
        return C'255,210,90';

    if (UiPanelTextHas(text, _Symbol))
        return C'150,195,255';

    if (UiPanelTextHas(text, "SIDEWAY"))
        return C'255,175,75';

    if (UiPanelTextHas(text, "XU HƯỚNG") || UiPanelTextHas(text, "TRENDING"))
        return C'110,235,150';

    if (UiPanelTextHas(text, "Biên đo") || UiPanelTextHas(text, "Measured "))
        return C'175,185,205';

    if (UiPanelTextHas(text, "Kế hoạch lot") || UiPanelTextHas(text, "Lot plan") || UiPanelTextHas(text, "Chốt lời basket") ||
        UiPanelTextHas(text, "Basket TP") || UiPanelTextHas(text, "Cắt lỗ basket") || UiPanelTextHas(text, "Basket SL") ||
        UiPanelTextHas(text, "TK chốt") || UiPanelTextHas(text, "Acct TP") || UiPanelTextHas(text, "TK cắt") || UiPanelTextHas(text, "Acct SL"))
        return C'190,200,220';

    if (UiPanelTextHas(text, "Cửa sổ") || UiPanelTextHas(text, "Window "))
        return C'175,185,205';

    if (UiPanelTextHas(text, "Chờ tín hiệu") || UiPanelTextHas(text, "Waiting signal"))
        return C'220,225,235';

    if (UiPanelTextHas(text, "LONG"))
        return C'90,255,130';

    if (UiPanelTextHas(text, "SHORT"))
        return C'255,110,110';

    if (UiPanelTextHas(text, "NEUTRAL"))
        return C'210,210,120';

    if (UiPanelTextHas(text, "P(up/down)"))
        return C'200,170,255';

    if (UiPanelTextHas(text, "Pattern:") || UiPanelTextHas(text, "Dự báo:") || UiPanelTextHas(text, "Forecast:"))
        return C'130,220,245';

    if (UiPanelTextHas(text, "Ghi chú:") || UiPanelTextHas(text, "Note:") || UiPanelTextHas(text, "Quét:") || UiPanelTextHas(text, "Scan:"))
        return C'165,170,180';

    if (UiPanelTextHas(text, "Chưa quét") || UiPanelTextHas(text, "No hybrid scan"))
        return C'140,145,155';

    if (UiPanelTextHas(text, "Basket"))
        return C'100,215,255';

    if (UiPanelTextHas(text, "Mồi lot") || UiPanelTextHas(text, "Bait lot") || UiPanelTextHas(text, "stage"))
        return C'210,200,255';

    if (UiPanelTextHas(text, "P+L ròng") || UiPanelTextHas(text, "Net P+L")) {
        if (UiPanelTextHas(text, "lãi") || UiPanelTextHas(text, "profit"))
            return C'80,255,120';
        if (UiPanelTextHas(text, "lỗ") || UiPanelTextHas(text, "loss"))
            return C'255,95,95';
        return clrWhite;
    }

    if (UiPanelTextHas(text, "Leg +") || UiPanelTextHas(text, "Sum +"))
        return C'235,235,245';

    if (UiPanelTextHas(text, "→ TP") || UiPanelTextHas(text, "-> TP") || UiPanelTextHas(text, "cần thêm") || UiPanelTextHas(text, "more to TP"))
        return C'120,255,160';

    if (UiPanelTextHas(text, "→ SL") || UiPanelTextHas(text, "-> SL") || UiPanelTextHas(text, "còn trước SL") || UiPanelTextHas(text, "room before SL"))
        return C'255,150,120';

    if (UiPanelTextHas(text, "Giá trị mồi") || UiPanelTextHas(text, "Bait notional"))
        return C'210,200,255';

    if (UiPanelTextHas(text, "Leg cuối") || UiPanelTextHas(text, "Latest leg"))
        return C'255,230,120';

    if (UiPanelTextHas(text, "Vị thế EA") || UiPanelTextHas(text, "EA positions"))
        return C'180,185,195';

    const color alt[] = {C'235,240,250', C'200,225,255', C'210,245,220', C'245,220,255'};
    return alt[lineIdx % 4];
}

void UiPanelSetLine(const int idx, const int corner, const int x, const int y, const string text, const color clr) {
    const string name = UiPanelLineName(idx);
    const int fs = MathMax(8, MathMin(16, InpPanelFontSize));
    if (ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
    }
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void UiPanelUpdate() {
    if (!InpShowPanel) {
        if (g_panelVisibleLines > 0 || ObjectFind(0, HSSW_UI_BG) >= 0)
            UiPanelDelete();
        return;
    }

    const int corner = MathMax(0, MathMin(3, InpPanelCorner));
    const int w = MathMax(120, InpPanelWidth);
    const int gap = MathMax(4, InpPanelLineGap);
    const int lineH = MathMax(InpPanelFontSize + gap, InpPanelFontSize + 8);
    const int x0 = InpPanelX + 8;
    const int y0 = InpPanelY + 8;

    const int nPos = CountOurPositions();
    string t = "━━ Hybrid Sideway + Mart ━━\n";
    t += _Symbol + "  " + EnumToString(_Period) + "\n\n";

    t += L("Thị trường: ", "Market: ");
    if (g_isSideway)
        t += L("SIDEWAY ⏸ (không mở mới)\n", "SIDEWAY ⏸ (no new entry)\n");
    else
        t += L("XU HƯỚNG ✓ (cho phép vào)\n", "TRENDING ✓ (entry allowed)\n");
    t += FmtSidewayRangeDetail() + "\n";
    t += L("Cửa sổ ", "Window ") + IntegerToString(InpSidewayWindowSec) + L(" giây · mẫu mỗi ", " sec · sample every ");
    t += IntegerToString(InpSidewaySampleSec) + L(" giây\n", " sec\n");
    t += FmtLotPlanLine() + "\n";
    t += FmtBasketTpExplain(false) + "\n";
    t += FmtBasketSlExplain(false) + "\n";
    if (StringLen(FmtAccountTpExplain()) > 0)
        t += FmtAccountTpExplain() + "\n";
    if (StringLen(FmtAccountSlExplain()) > 0)
        t += FmtAccountSlExplain() + "\n";
    t += "\n";

    if (nPos <= 0) {
        t += L("● Chờ tín hiệu (không basket)\n\n", "● Waiting signal (no basket)\n\n");
        if (g_panel_have_signal) {
            string dtxt = (g_panel_fd > 0) ? "LONG ⤴" : (g_panel_fd < 0 ? "SHORT ⤵" : "NEUTRAL ○");
            t += L("Dự báo: ", "Forecast: ") + dtxt + "\n";
            t += L("Xác suất: tăng ", "Probability: up ") + DoubleToString(g_panel_pu * 100.0, 1) + "% · giảm " +
                   DoubleToString(g_panel_pd * 100.0, 1) + "%\n";
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
        t += L("Mồi: ", "Bait: ") + DoubleToString(g_firstLot, 2) + L(" lot @ ", " lot @ ") +
               DoubleToString(g_firstOpenPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) + "\n";
        t += L("Giá trị mồi (ref): ", "Bait notional (ref): ") + FmtMoney(g_basketRefMoney) + "\n";
        t += L("Stage nhồi/quay đầu: ", "Martingale stage: ") + IntegerToString(g_addStage) + "/3\n";
        t += FmtBasketTpExplain(true) + "\n";
        t += FmtBasketSlExplain(true) + "\n";
        if (StringLen(FmtAccountTpExplain()) > 0)
            t += FmtAccountTpExplain() + "\n";
        if (StringLen(FmtAccountSlExplain()) > 0)
            t += FmtAccountSlExplain() + "\n";
        t += L("P+L ròng: ", "Net P+L: ") + FmtMoney(pnl);
        t += (pnl >= 0.0 ? L(" (đang lãi)\n", " (in profit)\n") : L(" (đang lỗ)\n", " (in loss)\n"));
        t += L("Leg +/−: ", "Leg +/−: ") + FmtMoney(sumWin) + " / " + FmtMoney(sumLoss) + "\n";
        if (g_basketTpMoney > 0.0) {
            const double needTp = MathMax(0.0, g_basketTpMoney - pnl);
            t += L("→ cần thêm ", "→ need ") + FmtMoney(needTp) + L(" để chạm TP mốc ", " more to hit TP ") +
                   FmtMoney(g_basketTpMoney) + "\n";
        }
        if (g_basketSlMoney > 0.0) {
            const double roomSl = MathMax(0.0, pnl + g_basketSlMoney);
            t += L("→ còn trước SL mốc −", "→ room before SL −") + FmtMoney(g_basketSlMoney) + L(": ", ": ") +
                   FmtMoney(roomSl) + "\n";
        }
        ulong lt = 0;
        double lop = 0.0;
        datetime lot = 0;
        long lty = -1;
        if (LatestOurPosition(lt, lop, lot, lty)) {
            double lp = 0.0;
            if (PositionSelectByTicket(lt))
                lp = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            t += L("Leg cuối P+L: ", "Latest leg P+L: ") + FmtMoney(lp) + "\n";
        }
        t += L("Vị thế EA: ", "EA positions: ") + IntegerToString(nPos) + "\n";
    }

    StringReplace(t, "\r\n", "\n");
    StringReplace(t, "\r", "\n");
    string lines[];
    int nLines = StringSplit(t, '\n', lines);
    if (nLines <= 0 && StringLen(t) > 0) {
        ArrayResize(lines, 1);
        lines[0] = t;
        nLines = 1;
    }
    if (nLines > HSSW_PANEL_MAX_LINES)
        nLines = HSSW_PANEL_MAX_LINES;

    const int bgH = MathMax(InpPanelHeight, y0 - InpPanelY + nLines * lineH + 8);
    UiPanelEnsureBackground(corner, w, bgH);

    for (int i = 0; i < nLines; i++) {
        StringTrimRight(lines[i]);
        StringTrimLeft(lines[i]);
        UiPanelSetLine(i, corner, x0, y0 + i * lineH, lines[i], UiPanelColorForLine(lines[i], i));
    }
    for (int j = nLines; j < g_panelVisibleLines; j++)
        UiPanelDeleteLine(j);
    g_panelVisibleLines = nLines;

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
          L(" | khối lượng ", " | volume "), DoubleToString(vol, 2), L(" lot", " lot"));
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
    RecoverBasketGlobalsIfNeeded();
    if (g_basketTpMoney <= 0.0 && g_basketSlMoney <= 0.0)
        LockBasketTpSlFromFirstLeg();

    if (g_basketTpMoney > 0.0 && pnl >= g_basketTpMoney) {
        string dVi = "Luật: P+L ròng ≥ mốc chốt lời basket.\n";
        dVi += "Giá trị mồi (ref) = " + FmtMoney(g_basketRefMoney) + " · " + FmtPctAndMoney(InpBasketTakeProfitPct, g_basketRefMoney) +
               " → mốc TP = " + FmtMoney(g_basketTpMoney) + ".\n";
        dVi += "Kiểm tra: P+L " + FmtMoney(pnl) + " ≥ " + FmtMoney(g_basketTpMoney) + " → chốt lãi.";
        string dEn = "Rule: net P+L >= basket TP target.\n";
        dEn += "Bait ref " + FmtMoney(g_basketRefMoney) + " · " + FmtPctAndMoney(InpBasketTakeProfitPct, g_basketRefMoney) +
               " → TP " + FmtMoney(g_basketTpMoney) + ". Net " + FmtMoney(pnl) + " → take profit.";
        LogExitBanner("Chốt lời basket", "Basket take profit", pnl, dVi, dEn);
        CloseAllOurPositions();
        closed = true;
        return true;
    }

    if (g_basketSlMoney > 0.0 && pnl <= -g_basketSlMoney) {
        string dVi = "Luật: P+L ròng ≤ −mốc cắt lỗ basket.\n";
        dVi += "Giá trị mồi (ref) = " + FmtMoney(g_basketRefMoney) + " · " + FmtPctAndMoney(InpBasketStopLossPct, g_basketRefMoney) +
               " → cắt tại P+L = −" + FmtMoney(g_basketSlMoney) + ".\n";
        dVi += "P+L hiện " + FmtMoney(pnl) + " → cắt lỗ.";
        string dEn = "Rule: net P+L <= −basket SL. Ref " + FmtMoney(g_basketRefMoney) + " · " +
               FmtPctAndMoney(InpBasketStopLossPct, g_basketRefMoney) + " → cut at −" + FmtMoney(g_basketSlMoney) +
               ". Net " + FmtMoney(pnl) + " → stop loss.";
        LogExitBanner("Cắt lỗ basket", "Basket stop loss", pnl, dVi, dEn);
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
                string dVi = "Luật: equity tăng so với lúc mở basket ≥ ngưỡng chốt lời tài khoản.\n";
                dVi += "Balance lúc mở: " + FmtMoney(g_balanceAtBasketOpen) + " · " +
                       FmtPctAndMoney(InpAccountTakeProfitPct, g_balanceAtBasketOpen) + " → ngưỡng +" + FmtMoney(tpAcc) +
                       ".\nDelta equity " + FmtMoney(delta) + " ≥ +" + FmtMoney(tpAcc) + " → chốt (lãi TK).";
                string dEn = "Account TP: equity gain " + FmtMoney(delta) + " >= threshold +" + FmtMoney(tpAcc) + " (" +
                       FmtPctAndMoney(InpAccountTakeProfitPct, g_balanceAtBasketOpen) + " of open balance).";
                LogExitBanner("Chốt lời tài khoản", "Account take profit", pnl, dVi, dEn);
                CloseAllOurPositions();
                closed = true;
                return true;
            }
        }
        if (InpAccountStopLossPct > 0.0) {
            const double slAcc = g_balanceAtBasketOpen * (InpAccountStopLossPct / 100.0);
            if (delta <= -slAcc) {
                string dVi = "Luật: equity giảm so với lúc mở basket ≥ ngưỡng cắt lỗ tài khoản.\n";
                dVi += "Balance lúc mở: " + FmtMoney(g_balanceAtBasketOpen) + " · " +
                       FmtPctAndMoney(InpAccountStopLossPct, g_balanceAtBasketOpen) + " → ngưỡng −" + FmtMoney(slAcc) +
                       ".\nDelta equity " + FmtMoney(delta) + " ≤ −" + FmtMoney(slAcc) + " → cắt (lỗ TK).";
                string dEn = "Account SL: equity change " + FmtMoney(delta) + " <= −" + FmtMoney(slAcc) + " (" +
                       FmtPctAndMoney(InpAccountStopLossPct, g_balanceAtBasketOpen) + " of open balance).";
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
                       L("Leg mồi đang lỗ — nhồi cùng chiều: ", "Bait leg losing — same-dir add: ") +
                           FmtLotMultResult(prevVol, InpMartingaleMult, vol),
                       FmtLotMultResult(prevVol, InpMartingaleMult, vol));
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
                       L("Leg #2 vẫn lỗ — nhồi tiếp: ", "Leg #2 still losing — add: ") +
                           FmtLotMultResult(prevVol, InpMartingaleMult, vol),
                       FmtLotMultResult(prevVol, InpMartingaleMult, vol));
        }
        return;
    }

    if (g_addStage == 2 && nSame >= 3) {
        const double vol = NormalizeVolumeLocal(g_firstLot * InpReversalMult);
        const ENUM_ORDER_TYPE t = g_basketBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        if (vol >= vmin && OpenMarket(t, vol, "HSSW_REV")) {
            g_addStage = 3;
            LogLegOpen("lệnh quay đầu", "reversal leg", t, vol,
                       L("Sau 3 leg cùng chiều vẫn lỗ — quay đầu: ", "After 3 same-dir legs still losing — reversal: ") +
                           FmtLotMultResult(g_firstLot, InpReversalMult, vol),
                       FmtLotMultResult(g_firstLot, InpReversalMult, vol));
        }
    }
}

void TryOpenFirstFromSignal() {
    if (!TradingAllowedBySideway()) {
        Print(L("[SIDEWAY] ", "[SIDEWAY] "), FmtSidewayRangeDetail(),
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
    Print(L("Hướng: ", "Direction: "), fd, L(" | xác suất tăng ", " | prob up "), DoubleToString(pu * 100.0, 1),
          L("% · giảm ", "% · down "), DoubleToString(pd * 100.0, 1), "%");

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

    const double refOpen = g_basketRefMoney;
    LogLegOpen("lệnh mồi", "bait leg", t, vol,
               L("Tín hiệu Hybrid ", "Hybrid signal ") + ((fd > 0) ? "LONG" : "SHORT") +
                   L(" · lot mồi ", " · bait lot ") + DoubleToString(vol, 2) +
                   L(" · giá trị ref ", " · notional ref ") + FmtMoney(refOpen) + L(" · không sideway", " · not sideway"),
               L("Hybrid ", "Hybrid ") + ((fd > 0) ? "LONG" : "SHORT") + L(" · bait ", " · bait ") +
                   DoubleToString(vol, 2) + L(" lot · ref ", " lot · ref ") + FmtMoney(refOpen));

    Print(L("Khóa chốt lời basket: ", "Locked basket TP: "), FmtMoney(g_basketTpMoney), L(" (", " ("),
          FmtPctAndMoney(InpBasketTakeProfitPct, refOpen), L(", ref mồi ", ", bait ref "), FmtMoney(refOpen), ")");
    if (g_basketSlMoney > 0.0)
        Print(L("Khóa cắt lỗ basket: −", "Locked basket SL: −"), FmtMoney(g_basketSlMoney), L(" (", " ("),
              FmtPctAndMoney(InpBasketStopLossPct, refOpen), ")");
    else
        Print(L("Cắt lỗ basket: tắt (InpBasketStopLossPct = 0).", "Basket SL: off (InpBasketStopLossPct = 0)."));
    if (InpAccountTakeProfitPct > 0.0)
        Print(L("Ngưỡng chốt lời TK khi mở basket: +", "Account TP threshold at basket open: +"),
              FmtMoney(g_balanceAtBasketOpen * (InpAccountTakeProfitPct / 100.0)), L(" (", " ("),
              FmtPctAndMoney(InpAccountTakeProfitPct, g_balanceAtBasketOpen), L(" balance ", " of balance "),
              FmtMoney(g_balanceAtBasketOpen), ")");
    if (InpAccountStopLossPct > 0.0)
        Print(L("Ngưỡng cắt lỗ TK khi mở basket: −", "Account SL threshold at basket open: −"),
              FmtMoney(g_balanceAtBasketOpen * (InpAccountStopLossPct / 100.0)), L(" (", " ("),
              FmtPctAndMoney(InpAccountStopLossPct, g_balanceAtBasketOpen), ")");
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
