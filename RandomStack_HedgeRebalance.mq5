//+------------------------------------------------------------------+
//| RandomStack_HedgeRebalance.mq5                                  |
//| Stack rỗng: mở 1 lệnh theo nến — tăng (C>O) BUY, giảm (C<O) SELL. |
//| Quét từng lệnh: chốt khi P+L đạt TP% hoặc SL% trên giá trị vào.   |
//| Hai phía đều có lệnh: bên tổng P+L thấp hơn = lỗ nặng hơn → thêm   |
//| 1 lệnh phía bên lãi hơn. Một phía: không coi 0 USD là “lỗ”; chỉ     |
//| hedge khi tổng phía đang có lệnh ≤ −ngưỡng (nếu bật chế độ đó).    |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version "1.02"
#property description "v1.02: vào lệnh khi flat theo hướng nến (C vs O); v1.01 rebalance/cooldown giữ nguyên."

#include <Trade/Trade.mqh>

#define RST_CMT_PREFIX "RST|"

input group "=== EA ==="
input ulong InpMagic = 910031;
input int InpSlippagePoints = 30;
input bool InpCloseAllOurOnInit = false;

input group "=== Tiền vào mỗi lệnh ==="
input double InpEquityPctPerTrade = 1.0; // % equity tại thời điểm mở

input group "=== Hướng vào khi stack rỗng (theo nến chart) ==="
input int InpFlatEntryBarShift = 1; // 1 = nến vừa đóng (khuyến nghị); 0 = nến đang chạy (nhạy hơn, dễ đảo chiều)

input group "=== Chốt theo % giá trị vào lệnh (tiền sizing lúc mở) ==="
input double InpTakeProfitPctOfEntry = 20.0;
input double InpStopLossPctOfEntry = 20.0;
input bool InpSkipTpSlUntilNextBarAfterOpen = false;

input group "=== Cân bằng theo tổng BUY vs SELL ==="
input int InpRebalanceCooldownSec = 30;      // Tối thiểu giữa hai lệnh rebalance / hedge thêm
input double InpRebalanceMinDiffMoney = 5.0; // Hai phía: chỉ thêm lệnh nếu |sumBuy − sumSell| ≥ giá trị này
input bool InpRebalanceNeedTwoSides = true;  // true (khuyến nghị): chỉ so tổng khi đã có cả BUY và SELL — tránh log sai “SELL=0 lỗ hơn”
input double InpSingleSideHedgeMinLossMoney = 15.0; // Khi InpRebalanceNeedTwoSides=false: chỉ mở hedge ngược khi tổng P+L phía đang có lệnh ≤ −giá trị này
input int InpFlatCooldownSec = 8;            // Sau khi vừa đóng hết lệnh: chờ N giây mới mở lệnh theo nến (giảm spam / whipsaw)
input int InpMaxPositionsTotal = 0;           // 0 = không giới hạn; 4–8 giúp giảm rủi ro tổng

input group "=== Log / thông báo ==="
input bool InpUseAlert = false;
input bool InpQuietExpertsLog = false;

CTrade g_trade;
datetime g_lastRebalanceTime = 0;
datetime g_flatSince = 0; // thời điểm vừa chuyển từ có lệnh → không còn lệnh (0 = chưa từng flat sau có lệnh)

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
    if (StringFind(cmt, RST_CMT_PREFIX) != 0)
        return false;
    const string rest = StringSubstr(cmt, StringLen(RST_CMT_PREFIX));
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
        Print("RandomStack: OpenMarket failed: ", g_trade.ResultRetcodeDescription());
    return ok;
}

int CountOurPositionsOnSymbol() {
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

struct SSidesPnl {
    double sumBuy;
    double sumSell;
    int cntBuy;
    int cntSell;
};

SSidesPnl CollectSidesPnl() {
    SSidesPnl r;
    r.sumBuy = 0.0;
    r.sumSell = 0.0;
    r.cntBuy = 0;
    r.cntSell = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        const double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        const long typ = PositionGetInteger(POSITION_TYPE);
        if (typ == POSITION_TYPE_BUY) {
            r.sumBuy += pnl;
            r.cntBuy++;
        } else if (typ == POSITION_TYPE_SELL) {
            r.sumSell += pnl;
            r.cntSell++;
        }
    }
    return r;
}

bool ExitScanAllowedForPositionByBar(const datetime positionOpenTime) {
    if (!InpSkipTpSlUntilNextBarAfterOpen)
        return true;
    const int sh = iBarShift(_Symbol, _Period, positionOpenTime, false);
    if (sh < 0)
        return true;
    return (sh > 0);
}

void NotifyMsg(const string msg) {
    Print(msg);
    if (InpUseAlert)
        Alert(msg);
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
        const SSidesPnl sides = CollectSidesPnl();
        const double totalFloatBefore = sides.sumBuy + sides.sumSell;
        const long ptyp = PositionGetInteger(POSITION_TYPE);
        const string sideStr = (ptyp == POSITION_TYPE_BUY) ? "BUY" : "SELL";
        const string sidesLine = " | Tổng BUY=" + DoubleToString(sides.sumBuy, 2) + " SELL=" + DoubleToString(sides.sumSell, 2) + " " + cur;

        if (pnl >= tpMoney) {
            const string msg =
                "RandomStack: ĐÓNG ticket " + IntegerToString((long)ticket) + " (" + sideStr + ") — CHỐT LỜI: P+L lệnh=" +
                DoubleToString(pnl, 2) + " " + cur + " ≥ mốc TP " + DoubleToString(tpMoney, 2) + " " + cur + " (" +
                DoubleToString(InpTakeProfitPctOfEntry, 1) + "% giá trị vào " + DoubleToString(entryMoney, 2) +
                "). Tổng P+L nổi (mọi lệnh EA symbol) trước khi đóng: " + DoubleToString(totalFloatBefore, 2) + " " + cur +
                sidesLine;
            NotifyMsg(msg);
            g_trade.PositionClose(ticket, InpSlippagePoints);
            continue;
        }
        if (pnl <= -slMoney) {
            const string msg =
                "RandomStack: ĐÓNG ticket " + IntegerToString((long)ticket) + " (" + sideStr + ") — CẮT LỖ: P+L lệnh=" +
                DoubleToString(pnl, 2) + " " + cur + " ≤ −mốc SL " + DoubleToString(slMoney, 2) + " " + cur + " (" +
                DoubleToString(InpStopLossPctOfEntry, 1) + "% giá trị vào " + DoubleToString(entryMoney, 2) +
                "). Tổng P+L nổi (mọi lệnh EA symbol) trước khi đóng: " + DoubleToString(totalFloatBefore, 2) + " " + cur +
                sidesLine;
            NotifyMsg(msg);
            g_trade.PositionClose(ticket, InpSlippagePoints);
        }
    }
}

bool TryOpenSizedMarket(const ENUM_ORDER_TYPE otype, const string reasonTag) {
    if (InpMaxPositionsTotal > 0 && CountOurPositionsOnSymbol() >= InpMaxPositionsTotal) {
        if (!InpQuietExpertsLog)
            Print("RandomStack: Đạt InpMaxPositionsTotal — không mở thêm (", reasonTag, ").");
        return false;
    }

    const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if (equity <= 0.0) {
        if (!InpQuietExpertsLog)
            Print("RandomStack: Equity ≤ 0 — không mở lệnh.");
        return false;
    }

    const double money = equity * (InpEquityPctPerTrade / 100.0);
    double vol = 0.0;
    if (!VolumeFromMoney(otype, money, vol)) {
        if (!InpQuietExpertsLog)
            Print("RandomStack: Không tính được lot từ % vốn.");
        return false;
    }

    const string cmt = RST_CMT_PREFIX + DoubleToString(money, 2);
    if (StringLen(cmt) > 31) {
        Print("RandomStack: Comment quá dài cho broker.");
        return false;
    }

    double needMargin = 0.0;
    if (!OrderCalcMargin(otype, _Symbol, vol,
                         (otype == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID),
                         needMargin))
        needMargin = 0.0;
    const double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if (needMargin > 0.0 && freeMargin > 0.0 && needMargin > freeMargin * 0.98) {
        if (!InpQuietExpertsLog)
            Print("RandomStack: Margin không đủ — bỏ qua mở lệnh (", reasonTag, ").");
        return false;
    }

    const bool ok = OpenMarket(otype, vol, cmt);
    if (ok) {
        const string side = (otype == ORDER_TYPE_BUY) ? "BUY" : "SELL";
        const string cur = AccountInfoString(ACCOUNT_CURRENCY);
        const string msg = "RandomStack: Đã mở " + side + " vol=" + DoubleToString(vol, 2) + " — sizing " +
                           DoubleToString(money, 2) + " " + cur + " | " + reasonTag;
        if (!InpQuietExpertsLog)
            Print(msg);
    }
    return ok;
}

// shift: 0 = nến hiện tại, 1 = nến trước (đã đóng). Tăng: close>open → BUY; giảm: close<open → SELL. Doji: so close vs nến kế.
bool FlatEntryTypeFromCandle(const int shift, ENUM_ORDER_TYPE& outType, string& outReason) {
    outType = ORDER_TYPE_BUY;
    outReason = "";
    const int sh = shift;
    if (sh < 0) {
        outReason = "InpFlatEntryBarShift < 0";
        return false;
    }
    const int bars = Bars(_Symbol, _Period);
    if (bars < sh + 2) {
        outReason = "chưa đủ lịch sử nến";
        return false;
    }

    const double o = iOpen(_Symbol, _Period, sh);
    const double c = iClose(_Symbol, _Period, sh);
    if (o <= 0.0 || c <= 0.0) {
        outReason = "Open/Close nến không hợp lệ";
        return false;
    }

    if (c > o) {
        outType = ORDER_TYPE_BUY;
        outReason = StringFormat("nến[%d] tăng C>O (%s): O=%s C=%s", sh, EnumToString(_Period), DoubleToString(o, _Digits),
                                 DoubleToString(c, _Digits));
        return true;
    }
    if (c < o) {
        outType = ORDER_TYPE_SELL;
        outReason = StringFormat("nến[%d] giảm C<O (%s): O=%s C=%s", sh, EnumToString(_Period), DoubleToString(o, _Digits),
                                 DoubleToString(c, _Digits));
        return true;
    }

    if (bars < sh + 3) {
        outReason = "doji C=O, thiếu nến trước để phân hướng";
        return false;
    }
    const double cPrev = iClose(_Symbol, _Period, sh + 1);
    if (cPrev <= 0.0) {
        outReason = "Close nến trước không hợp lệ";
        return false;
    }
    if (c >= cPrev) {
        outType = ORDER_TYPE_BUY;
        outReason = StringFormat("nến[%d] doji C=O, C>=C_trước → BUY (%s)", sh, EnumToString(_Period));
    } else {
        outType = ORDER_TYPE_SELL;
        outReason = StringFormat("nến[%d] doji C=O, C<C_trước → SELL (%s)", sh, EnumToString(_Period));
    }
    return true;
}

void TryOpenBarTrendWhenFlat() {
    if (CountOurPositionsOnSymbol() != 0)
        return;

    if (g_flatSince > 0 && InpFlatCooldownSec > 0 && (TimeCurrent() - g_flatSince) < InpFlatCooldownSec)
        return;

    ENUM_ORDER_TYPE otype = ORDER_TYPE_BUY;
    string why = "";
    if (!FlatEntryTypeFromCandle(InpFlatEntryBarShift, otype, why)) {
        if (!InpQuietExpertsLog)
            Print("RandomStack: Chưa vào lệnh (flat) — ", why);
        return;
    }

    TryOpenSizedMarket(otype, "stack rỗng theo nến: " + why);
}

void TryRebalanceTowardWinningSide() {
    if (CountOurPositionsOnSymbol() == 0)
        return;

    if (InpRebalanceCooldownSec > 0 && (TimeCurrent() - g_lastRebalanceTime) < InpRebalanceCooldownSec)
        return;

    SSidesPnl s = CollectSidesPnl();
    if (s.cntBuy + s.cntSell == 0)
        return;

    const string cur = AccountInfoString(ACCOUNT_CURRENCY);
    bool haveDecision = false;
    ENUM_ORDER_TYPE addType = ORDER_TYPE_BUY;
    string why = "";

    // Cả hai phía đều có lệnh: so sánh tổng P+L (không dùng 0 USD của phía không có lệnh).
    if (s.cntBuy > 0 && s.cntSell > 0) {
        const double diff = s.sumBuy - s.sumSell;
        if (MathAbs(diff) < InpRebalanceMinDiffMoney)
            return;
        if (diff < 0.0) {
            addType = ORDER_TYPE_SELL;
            why = StringFormat("hai phía: BUY=%.2f < SELL=%.2f %s → BUY yếu hơn → thêm SELL", s.sumBuy, s.sumSell, cur);
        } else {
            addType = ORDER_TYPE_BUY;
            why = StringFormat("hai phía: BUY=%.2f > SELL=%.2f %s → SELL yếu hơn → thêm BUY", s.sumBuy, s.sumSell, cur);
        }
        haveDecision = true;
    } else if (!InpRebalanceNeedTwoSides) {
        // Một phía: chỉ hedge khi tổng P+L phía đó thực sự lỗ đủ sâu (không pyramid khi đang lãi một chiều).
        const double thr = MathMax(0.0, InpSingleSideHedgeMinLossMoney);
        if (s.cntBuy > 0 && s.cntSell == 0) {
            if (s.sumBuy > -thr)
                return;
            addType = ORDER_TYPE_SELL;
            why = StringFormat("một phía BUY: tổng=%.2f %s ≤ −%.2f → hedge SELL", s.sumBuy, cur, thr);
            haveDecision = true;
        } else if (s.cntSell > 0 && s.cntBuy == 0) {
            if (s.sumSell > -thr)
                return;
            addType = ORDER_TYPE_BUY;
            why = StringFormat("một phía SELL: tổng=%.2f %s ≤ −%.2f → hedge BUY", s.sumSell, cur, thr);
            haveDecision = true;
        } else
            return;
    } else {
        // Chỉ so hai phía nhưng hiện chỉ có một phía → không thêm (giảm lệnh ngược oan).
        return;
    }

    if (!haveDecision)
        return;

    if (TryOpenSizedMarket(addType, why))
        g_lastRebalanceTime = TimeCurrent();
}

void OnTick() {
    ManagePerPositionExits();

    static int s_prevOurCount = -1;
    const int n = CountOurPositionsOnSymbol();
    if (n == 0 && s_prevOurCount > 0)
        g_flatSince = TimeCurrent();
    s_prevOurCount = n;

    if (n == 0)
        TryOpenBarTrendWhenFlat();
    else
        TryRebalanceTowardWinningSide();
}

int OnInit() {
    if (InpEquityPctPerTrade <= 0.0) {
        Print("RandomStack: InpEquityPctPerTrade phải > 0.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpTakeProfitPctOfEntry <= 0.0 || InpStopLossPctOfEntry <= 0.0) {
        Print("RandomStack: TP/SL % phải > 0.");
        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpSingleSideHedgeMinLossMoney < 0.0) {
        Print("RandomStack: InpSingleSideHedgeMinLossMoney không được âm.");
        return INIT_PARAMETERS_INCORRECT;
    }
    if (InpFlatEntryBarShift < 0) {
        Print("RandomStack: InpFlatEntryBarShift phải ≥ 0.");
        return INIT_PARAMETERS_INCORRECT;
    }

    if (InpCloseAllOurOnInit) {
        CloseAllOurPositionsAndPendings();
        Print("RandomStack: Init — đã đóng/hủy lệnh EA (magic) trên symbol.");
    }

    const long mm = (long)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    if (mm != (long)ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) {
        Print("RandomStack CẢNH BÁO: tài khoản không phải hedging — MT5 có thể gộp nhiều lệnh cùng symbol thành một vị thế; ",
              "TP/SL theo từng ticket chỉ đúng khi mỗi lệnh tách riêng (hedging).");
    }

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
}
