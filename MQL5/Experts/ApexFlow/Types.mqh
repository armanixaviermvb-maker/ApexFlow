//+------------------------------------------------------------------+
//| Types.mqh - shared constants and enumerations for ApexFlow        |
//| Phase 2: enums needed by the input configuration.                 |
//| Phase 3 extends this file with engine/state types.                |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_TYPES_MQH
#define APEXFLOW_TYPES_MQH

#define APEX_NAME          "ApexFlow"
#define APEX_CODE_VERSION  "1.0.0"
#define APEX_LOG_TAG       "[APEXFLOW]"

//--- Hard safety caps. Inputs above these are rejected at initialization.
//--- They cannot be changed from the input dialog on purpose.
#define APEX_HARD_MAX_RISK_PCT          2.0
#define APEX_HARD_MAX_DAILY_LOSS_PCT    10.0
#define APEX_HARD_MAX_OPEN_POSITIONS    3
#define APEX_HARD_MAX_ACCOUNT_POSITIONS 10

//--- Trading mode. TEST is the default; LIVE needs three explicit switches.
enum ENUM_APEX_MODE
  {
   APEX_MODE_TEST = 0, // TEST - analysis only (orders simulated only in Strategy Tester)
   APEX_MODE_DEMO = 1, // DEMO - orders allowed on demo accounts only
   APEX_MODE_LIVE = 2  // LIVE - real money, requires ConfirmLiveTrading
  };

//--- How the broker server clock relates to GMT.
enum ENUM_APEX_SERVER_TZ
  {
   APEX_TZ_AUTO   = 0, // Auto (live: server time - GMT; tester: falls back to manual)
   APEX_TZ_MANUAL = 1  // Manual offset + DST rule below
  };

//--- Daylight-saving rule the broker server clock follows.
enum ENUM_APEX_DST_RULE
  {
   APEX_DST_NONE = 0, // None (server stays on fixed GMT offset)
   APEX_DST_EU   = 1, // European rule (last Sun Mar - last Sun Oct)
   APEX_DST_US   = 2  // US rule (2nd Sun Mar - 1st Sun Nov)
  };

//--- When the consecutive-loss breaker is cleared.
enum ENUM_APEX_LOSS_RESET
  {
   APEX_RESET_NEW_DAY = 0, // New broker trading day
   APEX_RESET_MANUAL  = 1  // Manual only (reload EA with ResetLossStreak=true)
  };

//--- Stop-loss placement method.
enum ENUM_APEX_STOP_MODE
  {
   APEX_STOP_STRUCTURE = 0, // Beyond structural swing (+ ATR buffer)
   APEX_STOP_ATR       = 1, // ATR multiple from entry
   APEX_STOP_HYBRID    = 2  // Structure, clamped to ATR min/max
  };

//--- Take-profit method.
enum ENUM_APEX_TP_MODE
  {
   APEX_TP_FIXED_R   = 0, // Fixed R multiple
   APEX_TP_STRUCTURE = 1, // Next structure / liquidity level
   APEX_TP_ATR       = 2  // ATR multiple
  };

//--- Trailing-stop method.
enum ENUM_APEX_TRAIL_MODE
  {
   APEX_TRAIL_ATR       = 0, // ATR trailing
   APEX_TRAIL_STRUCTURE = 1, // Structure (swing) trailing
   APEX_TRAIL_HYBRID    = 2  // Tighter-but-safe of ATR and structure
  };

//--- Log verbosity.
enum ENUM_APEX_LOG_LEVEL
  {
   APEX_LOG_ERROR = 0, // Errors only
   APEX_LOG_INFO  = 1, // Info (recommended)
   APEX_LOG_DEBUG = 2  // Debug (verbose)
  };

//+------------------------------------------------------------------+
string ApexModeToString(const ENUM_APEX_MODE mode)
  {
   switch(mode)
     {
      case APEX_MODE_TEST: return "TEST";
      case APEX_MODE_DEMO: return "DEMO";
      case APEX_MODE_LIVE: return "LIVE";
     }
   return "UNKNOWN";
  }

#endif // APEXFLOW_TYPES_MQH
