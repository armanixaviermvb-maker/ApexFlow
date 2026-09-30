//+------------------------------------------------------------------+
//| ApexFlow.mq5                                                      |
//| Adaptive, session-aware MetaTrader 5 Expert Advisor.              |
//|                                                                   |
//| No martingale. No loss doubling. No risk escalation.              |
//| No guaranteed returns: every trade can lose.                      |
//|                                                                   |
//| Phase 2 build: configuration, validation, execution permission    |
//| and chart status only. This build contains NO trading logic.      |
//+------------------------------------------------------------------+
#property copyright   "ApexFlow"
#property version     "1.00"
#property description "ApexFlow MT5 - adaptive session-aware EA."
#property description "Defaults to TEST mode. LIVE requires EnableTrading, LIVE mode and ConfirmLiveTrading."
#property description "No martingale, no loss doubling, no guaranteed returns."

#include "Config.mqh"

//--- runtime state
SApexConfig g_cfg;
bool        g_ordersPermitted  = false;
string      g_permissionReason = "";
bool        g_permissionKnown  = false;

//+------------------------------------------------------------------+
//| Re-evaluate order permission; log whenever it changes.            |
//+------------------------------------------------------------------+
void RefreshPermission()
  {
   string reason = "";
   bool permitted = ConfigOrdersPermitted(g_cfg, reason);
   if(!g_permissionKnown || permitted != g_ordersPermitted || reason != g_permissionReason)
     {
      PrintFormat("%s EVENT=ORDER_PERMISSION SYMBOL=%s MODE=%s PERMITTED=%s REASON=%s",
                  APEX_LOG_TAG, g_cfg.symbol, ApexModeToString(g_cfg.mode),
                  (permitted ? "YES" : "NO"), reason);
      g_permissionKnown = true;
     }
   g_ordersPermitted  = permitted;
   g_permissionReason = reason;
  }

//+------------------------------------------------------------------+
//| Temporary chart status (replaced by UI/Dashboard.mqh in Phase 13) |
//+------------------------------------------------------------------+
void UpdateStatus()
  {
   if(!g_cfg.showDashboard)
      return;
   string accType = "REAL";
   ENUM_ACCOUNT_TRADE_MODE accMode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(accMode == ACCOUNT_TRADE_MODE_DEMO)
      accType = "DEMO";
   else
      if(accMode == ACCOUNT_TRADE_MODE_CONTEST)
         accType = "CONTEST";

   string s = "";
   s += "--------------------------------\n";
   s += "APEXFLOW\n";
   s += "--------------------------------\n";
   if(g_cfg.mode == APEX_MODE_LIVE)
     {
      s += "!!!  LIVE MODE - REAL MONEY AT RISK  !!!\n";
      s += "--------------------------------\n";
     }
   s += "MODE:      " + ApexModeToString(g_cfg.mode) + "\n";
   s += "SYMBOL:    " + g_cfg.symbol + "   MAGIC: " + IntegerToString(g_cfg.magic) + "\n";
   s += "ACCOUNT:   " + accType + " / " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
   s += "BALANCE:   " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   s += "EQUITY:    " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
   s += "RISK:      " + DoubleToString(g_cfg.riskPct, 2) + "% per trade\n";
   s += "ORDERS:    " + (g_ordersPermitted ? "PERMITTED" : "BLOCKED") + " (" + g_permissionReason + ")\n";
   s += "VERSION:   " + APEX_CODE_VERSION + " / strategy " + g_cfg.strategyVersion + "\n";
   s += "SYSTEM:    PHASE 2 BUILD - NO TRADING LOGIC\n";
   s += "--------------------------------\n";
   Comment(s);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   ConfigLoad(g_cfg);

   string error = "", warnings = "";
   if(!ConfigValidate(g_cfg, error, warnings))
     {
      PrintFormat("%s EVENT=INIT_FAILED REASON=%s", APEX_LOG_TAG, error);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(warnings != "")
      PrintFormat("%s EVENT=CONFIG_WARNING DETAIL=%s", APEX_LOG_TAG, warnings);

   if(!SymbolSelect(g_cfg.symbol, true))
     {
      PrintFormat("%s EVENT=INIT_FAILED REASON=symbol_not_found SYMBOL=%s ERROR=%d",
                  APEX_LOG_TAG, g_cfg.symbol, GetLastError());
      return INIT_PARAMETERS_INCORRECT;
     }

   ConfigTrackChanges(g_cfg);

   PrintFormat("%s EVENT=INIT VERSION=%s STRATEGY_VERSION=%s SYMBOL=%s MAGIC=%I64d MODE=%s",
               APEX_LOG_TAG, APEX_CODE_VERSION, g_cfg.strategyVersion, g_cfg.symbol,
               g_cfg.magic, ApexModeToString(g_cfg.mode));
   if(g_cfg.mode == APEX_MODE_LIVE)
      PrintFormat("%s WARNING=LIVE_MODE_SELECTED real-money orders possible once all safeguards pass",
                  APEX_LOG_TAG);

   RefreshPermission();
   if(!EventSetTimer(1))
      PrintFormat("%s EVENT=TIMER_FAILED ERROR=%d", APEX_LOG_TAG, GetLastError());
   UpdateStatus();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
   PrintFormat("%s EVENT=DEINIT REASON=%d", APEX_LOG_TAG, reason);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // Phase 4+: fast path (price, spread, position management) and
   // new-bar triggered analysis path. Intentionally empty in Phase 2.
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   RefreshPermission();
   UpdateStatus();
  }
//+------------------------------------------------------------------+
