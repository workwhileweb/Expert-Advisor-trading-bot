//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_p1.mq5                                         |
//| Chỉ Risk P1: Soft DD đóng băng DCA + recovery sau Hard MaxDD.    |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.00"
#property description "HedgeDCA + Risk P1 (soft DD, recovery). Core: HedgeDCA_LockSide_core.mqh"

#define HDCA_BUILD_P1
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
