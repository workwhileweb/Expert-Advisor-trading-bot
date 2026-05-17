//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_p1p2.mq5                                       |
//| Risk P1 + P2: soft DD + recovery + spread (HDCA_VARIANT=130).    |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.02"
#property description "HedgeDCA + Risk P1+P2 (VARIANT=130). HedgeDCA_LockSide_core.mqh"

#define HDCA_BUILD_P1P2
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
