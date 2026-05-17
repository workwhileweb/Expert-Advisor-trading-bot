//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_p0p2.mq5                                       |
//| Risk P0 + P2: margin/float + spread (HDCA_VARIANT=120).          |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.02"
#property description "HedgeDCA + Risk P0+P2 (VARIANT=120). HedgeDCA_LockSide_core.mqh"

#define HDCA_BUILD_P0P2
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
