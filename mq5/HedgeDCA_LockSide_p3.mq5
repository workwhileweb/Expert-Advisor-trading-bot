//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_p3.mq5                                         |
//| Chỉ Risk P3: khoảng cách thời gian tối thiểu giữa hai lệnh DCA.   |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.00"
#property description "HedgeDCA + Risk P3 (min giây giữa các DCA). Core: HedgeDCA_LockSide_core.mqh"

#define HDCA_BUILD_P3
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
