//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_core.mqh                                      |
//| Trước #include: đặt đúng MỘT macro build (MQL5 không hỗ trợ      |
//| #if HDCA_VARIANT == …). Ví dụ: #define HDCA_BUILD_P0              |
//|   HDCA_BUILD_BASE | HDCA_BUILD_P0 … P4 | HDCA_BUILD_P0P1 …      |
//|   HDCA_BUILD_PALL — gộp P0–P4, bật/tắt bằng input InpPAll_*    |
//+------------------------------------------------------------------+
#ifndef HDCA_CORE_INCLUDED
#define HDCA_CORE_INCLUDED

#ifdef HDCA_BUILD_PALL
#define HDCA_NEED_P0_INPUTS
#define HDCA_NEED_P1_INPUTS
#define HDCA_NEED_P2_INPUTS
#define HDCA_NEED_P3_INPUTS
#define HDCA_NEED_P4_INPUTS
#define HDCA_NEED_P1_RECOVERY
#define HDCA_USE_RISK_FREEZE
#define HDCA_BUILD_LOG_ID 999
#define HDCA_BUILD_IS_PALL
#endif

#ifdef HDCA_BUILD_BASE
#define HDCA_BUILD_LOG_ID 0
#endif
#ifdef HDCA_BUILD_P0
#define HDCA_NEED_P0_INPUTS
#define HDCA_USE_RISK_FREEZE
#define HDCA_BUILD_LOG_ID 10
#endif
#ifdef HDCA_BUILD_P1
#define HDCA_NEED_P1_INPUTS
#define HDCA_NEED_P1_RECOVERY
#define HDCA_USE_RISK_FREEZE
#define HDCA_BUILD_LOG_ID 20
#endif
#ifdef HDCA_BUILD_P2
#define HDCA_NEED_P2_INPUTS
#define HDCA_USE_RISK_FREEZE
#define HDCA_BUILD_LOG_ID 30
#endif
#ifdef HDCA_BUILD_P3
#define HDCA_NEED_P3_INPUTS
#define HDCA_BUILD_LOG_ID 40
#endif
#ifdef HDCA_BUILD_P4
#define HDCA_NEED_P4_INPUTS
#define HDCA_USE_RISK_FREEZE
#define HDCA_BUILD_LOG_ID 50
#endif
#ifdef HDCA_BUILD_P0P1
#define HDCA_NEED_P0_INPUTS
#define HDCA_NEED_P1_INPUTS
#define HDCA_NEED_P1_RECOVERY
#define HDCA_USE_RISK_FREEZE
#define HDCA_BUILD_LOG_ID 110
#endif
#ifdef HDCA_BUILD_P0P2
#define HDCA_NEED_P0_INPUTS
#define HDCA_NEED_P2_INPUTS
#define HDCA_USE_RISK_FREEZE
#define HDCA_BUILD_LOG_ID 120
#endif
#ifdef HDCA_BUILD_P1P2
#define HDCA_NEED_P1_INPUTS
#define HDCA_NEED_P2_INPUTS
#define HDCA_NEED_P1_RECOVERY
#define HDCA_USE_RISK_FREEZE
#define HDCA_BUILD_LOG_ID 130
#endif
#ifdef HDCA_BUILD_P0P1P2
#define HDCA_NEED_P0_INPUTS
#define HDCA_NEED_P1_INPUTS
#define HDCA_NEED_P2_INPUTS
#define HDCA_NEED_P1_RECOVERY
#define HDCA_USE_RISK_FREEZE
#define HDCA_BUILD_LOG_ID 210
#endif
#ifndef HDCA_BUILD_LOG_ID
#define HDCA_BUILD_LOG_ID (-1)
#endif

#include <Trade/Trade.mqh>

enum ENUM_LOCK_SIDE {
    LOCK_NONE = 0,
    LOCK_BUY  = 1,
    LOCK_SELL = 2
};

input group "=== Lệnh gốc ==="
input double InpInitLot     = 0.01;
input ulong  InpMagic       = 20250417;
input int    InpSlippage    = 20;

input group "=== Bước DCA ==="
input int InpDcaStepPoints   = 100;
input int InpMaxDcaAdds      = 8;

input group "=== Hệ số nhân lot ==="
input double InpMultStop  = 1.09;
input double InpMultLimit = 1.09;

input group "=== Chốt lời (pip basket) ==="
input bool InpUseNoLockWinnerClose = true;
input int InpLockedSideTPPips   = 50;
input int InpNoLockWinnerTPPips = 200;
input int InpPointsPerPip       = 10;

input group "=== Bảo vệ ==="
input double InpMaxDD_USD   = 200.0;
input bool   InpAutoRestart = true;

input group "=== Giới hạn lot ==="
input double InpMaxTotalLot = 1.0;

#ifdef HDCA_BUILD_IS_PALL
input group "=== Risk PAll — bật/tắt từng lớp ==="
input bool InpPAll_EnableP0 = true;
input bool InpPAll_EnableP1 = true;
input bool InpPAll_EnableP2 = true;
input bool InpPAll_EnableP3 = true;
input bool InpPAll_EnableP4 = true;
#endif

#ifdef HDCA_NEED_P0_INPUTS
input group "=== Risk P0 (freeze DCA) ==="
input bool   InpRiskGovP0_Enable     = true;
input double InpStressMarginLevelPct  = 200.0;
input double InpStressFloatingLossUSD = 0.0;
#endif

#ifdef HDCA_NEED_P1_INPUTS
input group "=== Risk P1 (soft DD + recovery sau Hard DD) ==="
input double InpSoftDD_USD          = 0.0;
input int    InpRecoveryRestarts    = 0;
input double InpRecoveryLotFactor   = 0.5;
input int    InpRecoveryCooldownSec = 0;
#endif

#ifdef HDCA_NEED_P2_INPUTS
input group "=== Risk P2 (spread) ==="
input int InpP2MaxSpreadPoints = 80; // 0 = tắt nhánh spread
#endif

#ifdef HDCA_NEED_P3_INPUTS
input group "=== Risk P3 (tần suất DCA) ==="
input int InpP3MinSecondsBetweenDca = 30;
#endif

#ifdef HDCA_NEED_P4_INPUTS
input group "=== Risk P4 (toàn tài khoản) ==="
input double InpP4MaxAccountFloatingLossUSD = 500.0; // 0 = tắt; tổng P/L nổi mọi vị thế trên TK
#endif

input group "=== Khác ==="
input bool InpVerboseLog = true;

CTrade g_trade;

ENUM_LOCK_SIDE g_lock = LOCK_NONE;
bool             g_ddHalt = false;
bool             g_dca_frozen = false;

#ifdef HDCA_NEED_P1_RECOVERY
int              g_recovery_restarts_left = 0;
datetime         g_recovery_cooldown_until = 0;
double           g_cycle_base_lot = 0.0;
#endif

#ifdef HDCA_NEED_P3_INPUTS
datetime         g_last_dca_open_time = 0;
#endif

double PipPoints() { return (double)InpPointsPerPip * _Point; }

#ifdef HDCA_NEED_P1_RECOVERY
double CycleBaseLot() {
    if (g_cycle_base_lot > 0.0)
        return g_cycle_base_lot;
    return InpInitLot;
}
#else
double CycleBaseLot() { return InpInitLot; }
#endif

bool SetFilling() {
    const int fm = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if ((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
        g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    else if ((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
        g_trade.SetTypeFilling(ORDER_FILLING_IOC);
    else
        g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
    return true;
}

double NormLot(const double raw) {
    const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if (step <= 0.0)
        return vmin;
    double v = MathFloor(raw / step + 1e-12) * step;
    if (v < vmin)
        v = vmin;
    if (v > vmax)
        v = vmax;
    return v;
}

bool OpenMarket(const ENUM_ORDER_TYPE t, const double volume, const string cmt) {
    g_trade.SetExpertMagicNumber(InpMagic);
    g_trade.SetDeviationInPoints(InpSlippage);
    SetFilling();
    if (t == ORDER_TYPE_BUY)
        return g_trade.Buy(volume, _Symbol, 0.0, 0.0, 0.0, cmt);
    return g_trade.Sell(volume, _Symbol, 0.0, 0.0, 0.0, cmt);
}

int CountSide(const ENUM_POSITION_TYPE pt) {
    int n = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pt)
            n++;
    }
    return n;
}

double SumLotsSide(const ENUM_POSITION_TYPE pt) {
    double s = 0.0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pt)
            s += PositionGetDouble(POSITION_VOLUME);
    }
    return s;
}

double TotalLotsOur() { return SumLotsSide(POSITION_TYPE_BUY) + SumLotsSide(POSITION_TYPE_SELL); }

bool MinMaxOpenSide(const ENUM_POSITION_TYPE pt, double &extreme) {
    bool ok = false;
    extreme = (pt == POSITION_TYPE_BUY) ? DBL_MAX : -DBL_MAX;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pt)
            continue;
        const double op = PositionGetDouble(POSITION_PRICE_OPEN);
        if (pt == POSITION_TYPE_BUY) {
            if (op < extreme)
                extreme = op;
        } else {
            if (op > extreme)
                extreme = op;
        }
        ok = true;
    }
    return ok;
}

bool WeightedAvgOpen(const ENUM_POSITION_TYPE pt, double &avg, double &lots) {
    double num = 0.0;
    lots = 0.0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pt)
            continue;
        const double v = PositionGetDouble(POSITION_VOLUME);
        const double op = PositionGetDouble(POSITION_PRICE_OPEN);
        num += op * v;
        lots += v;
    }
    if (lots <= 0.0)
        return false;
    avg = num / lots;
    return true;
}

double BasketPipsBuy() {
    double avg, lots;
    if (!WeightedAvgOpen(POSITION_TYPE_BUY, avg, lots))
        return -1e100;
    const double pip = PipPoints();
    if (pip <= 0.0)
        return -1e100;
    return (SymbolInfoDouble(_Symbol, SYMBOL_BID) - avg) / pip;
}

double BasketPipsSell() {
    double avg, lots;
    if (!WeightedAvgOpen(POSITION_TYPE_SELL, avg, lots))
        return -1e100;
    const double pip = PipPoints();
    if (pip <= 0.0)
        return -1e100;
    return (avg - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / pip;
}

double FloatingProfitOur() {
    double p = 0.0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
    }
    return p;
}

#ifdef HDCA_NEED_P4_INPUTS
double FloatingProfitEntireAccount() {
    double p = 0.0;
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
    }
    return p;
}
#endif

bool OurSymbolHasOurPositions() {
    return CountSide(POSITION_TYPE_BUY) > 0 || CountSide(POSITION_TYPE_SELL) > 0;
}

bool Risk_ShouldFreezeDca() {
#ifdef HDCA_BUILD_IS_PALL
    if (!OurSymbolHasOurPositions())
        return false;
    if (InpPAll_EnableP2 && InpP2MaxSpreadPoints > 0) {
        const double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
        if (sp > (double)InpP2MaxSpreadPoints)
            return true;
    }
    if (InpPAll_EnableP1 && InpSoftDD_USD > 0.0 && FloatingProfitOur() <= -InpSoftDD_USD)
        return true;
    if (InpPAll_EnableP0 && InpRiskGovP0_Enable) {
        if (InpStressMarginLevelPct > 0.0) {
            const double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
            if (ml > 0.0 && ml <= InpStressMarginLevelPct)
                return true;
        }
        if (InpStressFloatingLossUSD > 0.0 && FloatingProfitOur() <= -InpStressFloatingLossUSD)
            return true;
    }
    if (InpPAll_EnableP4 && InpP4MaxAccountFloatingLossUSD > 0.0 &&
        FloatingProfitEntireAccount() <= -InpP4MaxAccountFloatingLossUSD)
        return true;
    return false;
#endif
#ifdef HDCA_BUILD_BASE
    return false;
#endif
#ifdef HDCA_BUILD_P0
    if (!InpRiskGovP0_Enable || !OurSymbolHasOurPositions())
        return false;
    if (InpStressMarginLevelPct > 0.0) {
        const double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        if (ml > 0.0 && ml <= InpStressMarginLevelPct)
            return true;
    }
    if (InpStressFloatingLossUSD > 0.0 && FloatingProfitOur() <= -InpStressFloatingLossUSD)
        return true;
    return false;
#endif
#ifdef HDCA_BUILD_P1
    if (!OurSymbolHasOurPositions())
        return false;
    if (InpSoftDD_USD > 0.0 && FloatingProfitOur() <= -InpSoftDD_USD)
        return true;
    return false;
#endif
#ifdef HDCA_BUILD_P2
    if (!OurSymbolHasOurPositions() || InpP2MaxSpreadPoints <= 0)
        return false;
    const double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
    return sp > (double)InpP2MaxSpreadPoints;
#endif
#ifdef HDCA_BUILD_P3
    return false;
#endif
#ifdef HDCA_BUILD_P4
    if (!OurSymbolHasOurPositions() || InpP4MaxAccountFloatingLossUSD <= 0.0)
        return false;
    return FloatingProfitEntireAccount() <= -InpP4MaxAccountFloatingLossUSD;
#endif
#ifdef HDCA_BUILD_P0P1
    if (!OurSymbolHasOurPositions())
        return false;
    if (InpSoftDD_USD > 0.0 && FloatingProfitOur() <= -InpSoftDD_USD)
        return true;
    if (InpRiskGovP0_Enable) {
        if (InpStressMarginLevelPct > 0.0) {
            const double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
            if (ml > 0.0 && ml <= InpStressMarginLevelPct)
                return true;
        }
        if (InpStressFloatingLossUSD > 0.0 && FloatingProfitOur() <= -InpStressFloatingLossUSD)
            return true;
    }
    return false;
#endif
#ifdef HDCA_BUILD_P0P2
    if (!OurSymbolHasOurPositions())
        return false;
    if (InpP2MaxSpreadPoints > 0) {
        const double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
        if (sp > (double)InpP2MaxSpreadPoints)
            return true;
    }
    if (!InpRiskGovP0_Enable)
        return false;
    if (InpStressMarginLevelPct > 0.0) {
        const double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        if (ml > 0.0 && ml <= InpStressMarginLevelPct)
            return true;
    }
    if (InpStressFloatingLossUSD > 0.0 && FloatingProfitOur() <= -InpStressFloatingLossUSD)
        return true;
    return false;
#endif
#ifdef HDCA_BUILD_P1P2
    if (!OurSymbolHasOurPositions())
        return false;
    if (InpP2MaxSpreadPoints > 0) {
        const double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
        if (sp > (double)InpP2MaxSpreadPoints)
            return true;
    }
    if (InpSoftDD_USD > 0.0 && FloatingProfitOur() <= -InpSoftDD_USD)
        return true;
    return false;
#endif
#ifdef HDCA_BUILD_P0P1P2
    if (!OurSymbolHasOurPositions())
        return false;
    if (InpP2MaxSpreadPoints > 0) {
        const double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
        if (sp > (double)InpP2MaxSpreadPoints)
            return true;
    }
    if (InpSoftDD_USD > 0.0 && FloatingProfitOur() <= -InpSoftDD_USD)
        return true;
    if (InpRiskGovP0_Enable) {
        if (InpStressMarginLevelPct > 0.0) {
            const double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
            if (ml > 0.0 && ml <= InpStressMarginLevelPct)
                return true;
        }
        if (InpStressFloatingLossUSD > 0.0 && FloatingProfitOur() <= -InpStressFloatingLossUSD)
            return true;
    }
    return false;
#endif
    return false;
}

void UpdateRiskGovernor() {
    const bool now = Risk_ShouldFreezeDca();
    if (now == g_dca_frozen)
        return;
    g_dca_frozen = now;
    if (InpVerboseLog) {
        const double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        const double fp = FloatingProfitOur();
        if (now)
            PrintFormat("[Risk HDCA_BUILD_LOG_ID=%d] STRESS → freeze DCA | margin=%.2f%% | bot_float=%.2f", HDCA_BUILD_LOG_ID, ml, fp);
        else
            PrintFormat("[Risk HDCA_BUILD_LOG_ID=%d] NORMAL → DCA allowed | margin=%.2f%% | bot_float=%.2f", HDCA_BUILD_LOG_ID, ml, fp);
    }
}

#ifdef HDCA_NEED_P1_RECOVERY
void BeginRecoveryAfterHardDd() {
    g_cycle_base_lot = 0.0;
    g_recovery_restarts_left = 0;
    if (InpRecoveryRestarts > 0 && InpRecoveryLotFactor > 0.0)
        g_recovery_restarts_left = InpRecoveryRestarts;
    if (InpRecoveryCooldownSec > 0)
        g_recovery_cooldown_until = TimeCurrent() + InpRecoveryCooldownSec;
    else
        g_recovery_cooldown_until = 0;
    if (g_recovery_restarts_left > 0 || g_recovery_cooldown_until > 0)
        PrintFormat("[Risk P1] Recovery after Hard DD | restarts_left=%d | lot_factor=%.4f | cooldown=%s",
                    g_recovery_restarts_left, InpRecoveryLotFactor,
                    (g_recovery_cooldown_until > 0 ? TimeToString(g_recovery_cooldown_until, TIME_DATE | TIME_SECONDS) : "—"));
}
#endif // HDCA_NEED_P1_RECOVERY

void CloseSide(const ENUM_POSITION_TYPE pt) {
    g_trade.SetExpertMagicNumber(InpMagic);
    g_trade.SetDeviationInPoints(InpSlippage);
    SetFilling();
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        const ulong ticket = PositionGetTicket(i);
        if (ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if (PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
        if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            continue;
        if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != pt)
            continue;
        g_trade.PositionClose(ticket, InpSlippage);
    }
}

void CloseAllOur() {
    CloseSide(POSITION_TYPE_BUY);
    CloseSide(POSITION_TYPE_SELL);
}

void LogSyncGrid() {
    const int up = CountSide(POSITION_TYPE_BUY);
    const int dn = CountSide(POSITION_TYPE_SELL);
    if (InpVerboseLog)
        PrintFormat("SyncGrid: Up=%d Dn=%d", up, dn);
}

void LogLotCalc(const ENUM_POSITION_TYPE pt, const int addIndex, const double raw, const double norm) {
    if (!InpVerboseLog)
        return;
    const double mult = (pt == POSITION_TYPE_BUY) ? InpMultLimit : InpMultStop;
    PrintFormat("[LotCalc] step=%d, mult=%.4f, raw=%.6f, norm=%.6f, stepLot=%.4f",
                addIndex, mult, raw, norm, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
}

#ifdef HDCA_BUILD_IS_PALL
bool HdcaPAll_GetInitialPairLot(double &v0, bool &useRecoveryLot) {
    useRecoveryLot = false;
    if (!InpPAll_EnableP1) {
        v0 = NormLot(InpInitLot);
        return true;
    }
    if (g_recovery_cooldown_until > 0 && TimeCurrent() < g_recovery_cooldown_until) {
        static datetime s_lastCdLog = 0;
        if (TimeCurrent() - s_lastCdLog >= 60) {
            PrintFormat("HedgeDCA: Recovery cooldown — chờ đến %s",
                        TimeToString(g_recovery_cooldown_until, TIME_DATE | TIME_SECONDS));
            s_lastCdLog = TimeCurrent();
        }
        return false;
    }
    useRecoveryLot = (g_recovery_restarts_left > 0);
    const double lotFactor = (useRecoveryLot && InpRecoveryLotFactor > 0.0) ? InpRecoveryLotFactor : 1.0;
    v0 = NormLot(InpInitLot * lotFactor);
    return true;
}
#endif

bool TryOpenInitialPair() {
    double v0;
    bool useRecoveryLot = false;
#ifdef HDCA_BUILD_IS_PALL
    if (!HdcaPAll_GetInitialPairLot(v0, useRecoveryLot))
        return false;
#else
#ifdef HDCA_NEED_P1_RECOVERY
    if (g_recovery_cooldown_until > 0 && TimeCurrent() < g_recovery_cooldown_until) {
        static datetime s_lastCdLog = 0;
        if (TimeCurrent() - s_lastCdLog >= 60) {
            PrintFormat("HedgeDCA: Recovery cooldown — chờ đến %s",
                        TimeToString(g_recovery_cooldown_until, TIME_DATE | TIME_SECONDS));
            s_lastCdLog = TimeCurrent();
        }
        return false;
    }
    useRecoveryLot = (g_recovery_restarts_left > 0);
    const double lotFactor = (useRecoveryLot && InpRecoveryLotFactor > 0.0) ? InpRecoveryLotFactor : 1.0;
    v0 = NormLot(InpInitLot * lotFactor);
#else
    v0 = NormLot(InpInitLot);
#endif
#endif
    if (v0 + v0 > InpMaxTotalLot + 1e-12) {
        Print("HedgeDCA: InpMaxTotalLot quá nhỏ cho 2 lệnh gốc.");
        return false;
    }
    if (!OpenMarket(ORDER_TYPE_BUY, v0, "HDCA ini BUY"))
        return false;
    if (!OpenMarket(ORDER_TYPE_SELL, v0, "HDCA ini SELL")) {
        CloseSide(POSITION_TYPE_BUY);
        return false;
    }
#ifdef HDCA_BUILD_IS_PALL
    if (InpPAll_EnableP1) {
        g_cycle_base_lot = v0;
        g_recovery_cooldown_until = 0;
        if (useRecoveryLot) {
            g_recovery_restarts_left--;
            PrintFormat("[Risk P1] Recovery open: lot/leg=%.6f | restarts_left=%d", v0, g_recovery_restarts_left);
        }
    } else {
        g_cycle_base_lot = 0.0;
        g_recovery_cooldown_until = 0;
    }
#else
#ifdef HDCA_NEED_P1_RECOVERY
    g_cycle_base_lot = v0;
    g_recovery_cooldown_until = 0;
    if (useRecoveryLot) {
        g_recovery_restarts_left--;
        PrintFormat("[Risk P1] Recovery open: lot/leg=%.6f | restarts_left=%d", v0, g_recovery_restarts_left);
    }
#endif
#endif
    g_lock = LOCK_NONE;
    g_ddHalt = false;
    if (InpVerboseLog) {
        PrintFormat("=== HedgeDCA Lock Side | %s | pt=%.8g ===", _Symbol, _Point);
        PrintFormat("MultiStop=%.2f MultiLimit=%.2f", InpMultStop, InpMultLimit);
        PrintFormat("MaxTotalLot=%.2f", InpMaxTotalLot);
        Print("Initial orders OK");
    }
    return true;
}

void OnLockedBuyHitTP(const double pips) {
    if (InpVerboseLog)
        PrintFormat("[TP] Locked BUY đạt TP: pips=%.12g", pips);
    CloseSide(POSITION_TYPE_BUY);
    LogSyncGrid();
    const int nb = CountSide(POSITION_TYPE_BUY);
    const int ns = CountSide(POSITION_TYPE_SELL);
    if (nb == 0 && ns == 0) {
        if (InpVerboseLog)
            Print("Reset cycle, ready to open initial orders");
        g_lock = LOCK_NONE;
        if (InpAutoRestart && !g_ddHalt)
            TryOpenInitialPair();
    } else if (ns > 0) {
        g_lock = LOCK_SELL;
        if (InpVerboseLog)
            Print("Chuyển lock sang SELL, tiếp tục DCA.");
    } else {
        g_lock = LOCK_NONE;
    }
}

void OnLockedSellHitTP(const double pips) {
    if (InpVerboseLog)
        PrintFormat("[TP] Locked SELL đạt TP: pips=%.12g", pips);
    CloseSide(POSITION_TYPE_SELL);
    LogSyncGrid();
    const int nb = CountSide(POSITION_TYPE_BUY);
    const int ns = CountSide(POSITION_TYPE_SELL);
    if (nb == 0 && ns == 0) {
        if (InpVerboseLog)
            Print("Reset cycle, ready to open initial orders");
        g_lock = LOCK_NONE;
        if (InpAutoRestart && !g_ddHalt)
            TryOpenInitialPair();
    } else if (nb > 0) {
        g_lock = LOCK_BUY;
        if (InpVerboseLog)
            Print("Chuyển lock sang BUY, tiếp tục DCA.");
    } else {
        g_lock = LOCK_NONE;
    }
}

void OnNoLockBuyWinner(const double pips) {
    if (InpVerboseLog)
        PrintFormat("[TP] No lock, BUY đạt TP: pips=%.12g", pips);
    CloseSide(POSITION_TYPE_BUY);
    LogSyncGrid();
    g_lock = LOCK_SELL;
    if (InpVerboseLog)
        Print("Chuyển lock sang SELL");
}

void OnNoLockSellWinner(const double pips) {
    if (InpVerboseLog)
        PrintFormat("[TP] No lock, SELL đạt TP: pips=%.12g", pips);
    CloseSide(POSITION_TYPE_SELL);
    LogSyncGrid();
    g_lock = LOCK_BUY;
    if (InpVerboseLog)
        Print("Chuyển lock sang BUY");
}

void CheckMaxDD() {
    if (InpMaxDD_USD <= 0.0)
        return;
    const double fp = FloatingProfitOur();
    if (fp <= -InpMaxDD_USD) {
        PrintFormat("HedgeDCA: MaxDD hit (%.2f <= -%.2f) — đóng tất cả.", fp, InpMaxDD_USD);
        CloseAllOur();
        g_ddHalt = !InpAutoRestart;
        g_lock = LOCK_NONE;
#ifdef HDCA_BUILD_IS_PALL
        if (InpPAll_EnableP1)
            BeginRecoveryAfterHardDd();
#else
#ifdef HDCA_NEED_P1_RECOVERY
        BeginRecoveryAfterHardDd();
#endif
#endif
    }
}

void TryDcaBuy() {
#ifdef HDCA_USE_RISK_FREEZE
    if (g_dca_frozen)
        return;
#endif
#ifdef HDCA_NEED_P3_INPUTS
#ifdef HDCA_BUILD_IS_PALL
    if (InpPAll_EnableP3 && InpP3MinSecondsBetweenDca > 0 && g_last_dca_open_time > 0 &&
        (TimeCurrent() - g_last_dca_open_time) < InpP3MinSecondsBetweenDca)
        return;
#else
    if (InpP3MinSecondsBetweenDca > 0 && g_last_dca_open_time > 0 &&
        (TimeCurrent() - g_last_dca_open_time) < InpP3MinSecondsBetweenDca)
        return;
#endif
#endif
    const int n = CountSide(POSITION_TYPE_BUY);
    if (n <= 0 || n >= 1 + InpMaxDcaAdds)
        return;
    double minOp;
    if (!MinMaxOpenSide(POSITION_TYPE_BUY, minOp))
        return;
    const double step = (double)InpDcaStepPoints * _Point;
    if (SymbolInfoDouble(_Symbol, SYMBOL_BID) > minOp - step)
        return;
    const int addIndex = n;
    const double mult = InpMultLimit;
    const double raw = CycleBaseLot() * MathPow(mult, (double)addIndex);
    const double lot = NormLot(raw);
    if (TotalLotsOur() + lot > InpMaxTotalLot + 1e-12) {
        if (InpVerboseLog)
            Print("HedgeDCA: MaxTotalLot — không thêm BUY.");
        return;
    }
    LogLotCalc(POSITION_TYPE_BUY, addIndex, raw, lot);
    if (OpenMarket(ORDER_TYPE_BUY, lot, "HDCA DCA BUY")) {
#ifdef HDCA_NEED_P3_INPUTS
#ifdef HDCA_BUILD_IS_PALL
        if (InpPAll_EnableP3)
            g_last_dca_open_time = TimeCurrent();
#else
        g_last_dca_open_time = TimeCurrent();
#endif
#endif
    }
}

void TryDcaSell() {
#ifdef HDCA_USE_RISK_FREEZE
    if (g_dca_frozen)
        return;
#endif
#ifdef HDCA_NEED_P3_INPUTS
#ifdef HDCA_BUILD_IS_PALL
    if (InpPAll_EnableP3 && InpP3MinSecondsBetweenDca > 0 && g_last_dca_open_time > 0 &&
        (TimeCurrent() - g_last_dca_open_time) < InpP3MinSecondsBetweenDca)
        return;
#else
    if (InpP3MinSecondsBetweenDca > 0 && g_last_dca_open_time > 0 &&
        (TimeCurrent() - g_last_dca_open_time) < InpP3MinSecondsBetweenDca)
        return;
#endif
#endif
    const int n = CountSide(POSITION_TYPE_SELL);
    if (n <= 0 || n >= 1 + InpMaxDcaAdds)
        return;
    double maxOp;
    if (!MinMaxOpenSide(POSITION_TYPE_SELL, maxOp))
        return;
    const double step = (double)InpDcaStepPoints * _Point;
    if (SymbolInfoDouble(_Symbol, SYMBOL_ASK) < maxOp + step)
        return;
    const int addIndex = n;
    const double mult = InpMultStop;
    const double raw = CycleBaseLot() * MathPow(mult, (double)addIndex);
    const double lot = NormLot(raw);
    if (TotalLotsOur() + lot > InpMaxTotalLot + 1e-12) {
        if (InpVerboseLog)
            Print("HedgeDCA: MaxTotalLot — không thêm SELL.");
        return;
    }
    LogLotCalc(POSITION_TYPE_SELL, addIndex, raw, lot);
    if (OpenMarket(ORDER_TYPE_SELL, lot, "HDCA DCA SELL")) {
#ifdef HDCA_NEED_P3_INPUTS
#ifdef HDCA_BUILD_IS_PALL
        if (InpPAll_EnableP3)
            g_last_dca_open_time = TimeCurrent();
#else
        g_last_dca_open_time = TimeCurrent();
#endif
#endif
    }
}

void ProcessTpAndLock() {
    const int nb = CountSide(POSITION_TYPE_BUY);
    const int ns = CountSide(POSITION_TYPE_SELL);
    const double pb = BasketPipsBuy();
    const double ps = BasketPipsSell();

    if (g_lock == LOCK_BUY && nb > 0 && pb >= (double)InpLockedSideTPPips) {
        OnLockedBuyHitTP(pb);
        return;
    }
    if (g_lock == LOCK_SELL && ns > 0 && ps >= (double)InpLockedSideTPPips) {
        OnLockedSellHitTP(ps);
        return;
    }

    if (InpUseNoLockWinnerClose && g_lock == LOCK_NONE && nb > 0 && ns > 0) {
        if (pb >= (double)InpNoLockWinnerTPPips) {
            OnNoLockBuyWinner(pb);
            return;
        }
        if (ps >= (double)InpNoLockWinnerTPPips) {
            OnNoLockSellWinner(ps);
            return;
        }
    }

    if (g_lock == LOCK_NONE && nb > 0 && ns == 0 && pb >= (double)InpLockedSideTPPips) {
        if (InpVerboseLog)
            PrintFormat("[TP] Single BUY basket TP: pips=%.12g", pb);
        CloseSide(POSITION_TYPE_BUY);
        LogSyncGrid();
        if (InpAutoRestart && !g_ddHalt)
            TryOpenInitialPair();
        return;
    }
    if (g_lock == LOCK_NONE && ns > 0 && nb == 0 && ps >= (double)InpLockedSideTPPips) {
        if (InpVerboseLog)
            PrintFormat("[TP] Single SELL basket TP: pips=%.12g", ps);
        CloseSide(POSITION_TYPE_SELL);
        LogSyncGrid();
        if (InpAutoRestart && !g_ddHalt)
            TryOpenInitialPair();
    }
}

void HdcaCore_OnInitCommon() {
    g_ddHalt = false;
    g_lock = LOCK_NONE;
    g_dca_frozen = false;
#ifdef HDCA_NEED_P1_RECOVERY
    g_recovery_restarts_left = 0;
    g_recovery_cooldown_until = 0;
    g_cycle_base_lot = 0.0;
#endif
#ifdef HDCA_NEED_P3_INPUTS
    g_last_dca_open_time = 0;
#endif
    g_trade.SetExpertMagicNumber(InpMagic);
    PrintFormat("HedgeDCA_LockSide core | BUILD_LOG_ID=%d | Magic=%I64u | DcaStep=%d pt | LockTP=%d pip",
                HDCA_BUILD_LOG_ID, (ulong)InpMagic, InpDcaStepPoints, InpLockedSideTPPips);
#ifdef HDCA_NEED_P1_RECOVERY
#ifdef HDCA_BUILD_IS_PALL
    if (InpPAll_EnableP1) {
        if (InpSoftDD_USD > 0.0 && InpMaxDD_USD > 0.0 && InpSoftDD_USD >= InpMaxDD_USD)
            Print("HedgeDCA warning: InpSoftDD_USD nên < InpMaxDD_USD.");
        if (InpRecoveryRestarts > 0 && InpRecoveryLotFactor <= 0.0)
            Print("HedgeDCA warning: InpRecoveryLotFactor <= 0 — recovery tắt.");
    }
#else
    if (InpSoftDD_USD > 0.0 && InpMaxDD_USD > 0.0 && InpSoftDD_USD >= InpMaxDD_USD)
        Print("HedgeDCA warning: InpSoftDD_USD nên < InpMaxDD_USD.");
    if (InpRecoveryRestarts > 0 && InpRecoveryLotFactor <= 0.0)
        Print("HedgeDCA warning: InpRecoveryLotFactor <= 0 — recovery tắt.");
#endif
#endif
}

void HdcaCore_OnTickCommon() {
    if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
        return;

    CheckMaxDD();
    if (g_ddHalt)
        return;

    const int nb = CountSide(POSITION_TYPE_BUY);
    const int ns = CountSide(POSITION_TYPE_SELL);
    if (nb == 0 && ns == 0) {
        g_lock = LOCK_NONE;
#ifdef HDCA_USE_RISK_FREEZE
        UpdateRiskGovernor();
#endif
        if (InpAutoRestart && !g_ddHalt)
            TryOpenInitialPair();
        return;
    }

#ifdef HDCA_USE_RISK_FREEZE
    UpdateRiskGovernor();
#endif
    ProcessTpAndLock();
    TryDcaBuy();
    TryDcaSell();
}

#endif // HDCA_CORE_INCLUDED
