//+------------------------------------------------------------------+
//| HedgeDCA_LockSide_p4.mq5                                         |
//| Chỉ Risk P4: lỗ nổi tổng toàn tài khoản (mọi lệnh) → freeze DCA. |
//+------------------------------------------------------------------+
#property copyright "Expert-Advisor-trading-bot"
#property version   "2.00"
#property description "HedgeDCA + Risk P4 (account floating → freeze DCA). Core: HedgeDCA_LockSide_core.mqh"

#define HDCA_BUILD_P4
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
