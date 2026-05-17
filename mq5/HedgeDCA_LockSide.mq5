//+------------------------------------------------------------------+
//| HedgeDCA_LockSide.mq5                                            |
//| Bản gốc (BASE): hedge + DCA + lock side — không RiskGov P0–P4.  |
//| Logic: HedgeDCA_LockSide_core.mqh (HDCA_BUILD_BASE).              |
//| Các bản mở rộng độc lập: HedgeDCA_LockSide_p0.mq5 … _p4.mq5      |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.00"
#property description "HedgeDCA Lock Side BASE (không P0–P4). Xem HedgeDCA_LockSide_algorithm.md"

#define HDCA_BUILD_BASE
#include "HedgeDCA_LockSide_core.mqh"

int OnInit() {
    HdcaCore_OnInitCommon();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { }

void OnTick() {
    HdcaCore_OnTickCommon();
}

//+------------------------------------------------------------------+
