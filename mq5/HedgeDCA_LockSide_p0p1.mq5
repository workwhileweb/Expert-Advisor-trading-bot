//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_p0p1.mq5                                       |
//| Risk P0 + P1: margin/float freeze + soft DD + recovery (VARIANT 110). |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.01"
#property description "HedgeDCA + Risk P0+P1 (core HDCA_VARIANT=110). HedgeDCA_LockSide_core.mqh"

#define HDCA_BUILD_P0P1
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
