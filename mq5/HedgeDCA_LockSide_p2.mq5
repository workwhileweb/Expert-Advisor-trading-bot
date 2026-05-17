//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_p2.mq5                                         |
//| Chỉ Risk P2: spread quá lớn (points) → freeze DCA.               |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.00"
#property description "HedgeDCA + Risk P2 (spread max → freeze DCA). Core: HedgeDCA_LockSide_core.mqh"

#define HDCA_BUILD_P2
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
