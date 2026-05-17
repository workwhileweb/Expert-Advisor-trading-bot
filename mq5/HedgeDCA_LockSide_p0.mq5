//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_p0.mq5                                         |
//| Chỉ Risk P0: freeze DCA theo margin % / lỗ nổi bot (P0).       |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.00"
#property description "HedgeDCA + Risk P0 (freeze DCA margin/float). Core: HedgeDCA_LockSide_core.mqh"

#define HDCA_BUILD_P0
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
