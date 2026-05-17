//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_pAll.mq5                                       |
//| Gộp Risk P0–P4: bật/tắt từng lớp qua input InpPAll_EnableP0…P4.  |
//| Core: HedgeDCA_LockSide_core.mqh (#define HDCA_BUILD_PALL).      |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.10"
#property description "HedgeDCA + Risk P0–P4 (toggles). HedgeDCA_LockSide_core.mqh"

#define HDCA_BUILD_PALL
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
