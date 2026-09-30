//+------------------------------------------------------------------+
//| Config.mqh - ApexFlow input parameters and configuration          |
//|                                                                   |
//| Inputs are copied once into SApexConfig so every engine receives  |
//| an explicit config struct (testable, no hidden globals).          |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_CONFIG_MQH
#define APEXFLOW_CONFIG_MQH

#include "Types.mqh"

//====================================================================
// INPUTS
//====================================================================
input group "=== GENERAL ==="
input ENUM_APEX_MODE InpTradingMode        = APEX_MODE_TEST; // Trading mode
input bool           InpEnableTrading      = false;          // EnableTrading (master switch for order sending)
input bool           InpConfirmLiveTrading = false;          // ConfirmLiveTrading (required for LIVE)
input long           InpMagicNumber        = 26093000;       // MagicNumber (base)
input bool           InpMagicAutoOffset    = true;           // Add per-symbol offset to MagicNumber
input string         InpSymbol             = "";             // Symbol base name ("" = chart symbol)
input string         InpSymbolSuffix       = "";             // Symbol suffix (e.g. "m" or "c" on Exness)
input string         InpStrategyVersion    = "1.0.0";        // StrategyVersion (bump when strategy inputs change)
input string         InpChangeReason       = "";             // Reason for parameter change (logged)

input group "=== ACCOUNT & RISK ==="
input double         InpStartingBalance          = 3.00;   // StartingBalance in USD (milestone only; cent balances /100)
input double         InpTargetBalance            = 270.00; // TargetBalance in USD (milestone only - never affects trading)
input double         InpRiskPerTradePercent      = 1.0;    // RiskPerTradePercent (hard cap 2%)
input double         InpMaxDailyLossPercent      = 3.0;    // MaximumDailyLossPercent (this symbol)
input double         InpMaxAccountDailyLossPct   = 5.0;    // Max daily loss % across all ApexFlow charts
input int            InpMaxConsecutiveLosses     = 3;      // MaximumConsecutiveLosses
input ENUM_APEX_LOSS_RESET InpLossStreakReset    = APEX_RESET_NEW_DAY; // Loss-streak reset rule
input bool           InpResetLossStreak          = false;  // ResetLossStreak (manual reset on load)
input int            InpMaxOpenPositions         = 1;      // MaximumOpenPositions (this symbol)
input int            InpMaxAccountOpenPositions  = 2;      // Max open positions across all ApexFlow charts
input bool           InpBlockCorrelatedSameDir   = true;   // Block same-direction USD-correlated positions

input group "=== SESSIONS (times in each market's local time; DST handled) ==="
input ENUM_APEX_SERVER_TZ InpServerTimeMode   = APEX_TZ_AUTO;  // Server time mode
input int            InpServerGMTOffsetHours  = 0;             // Server GMT offset (standard time, manual/tester)
input ENUM_APEX_DST_RULE InpServerDSTRule     = APEX_DST_NONE; // Server DST rule (manual/tester)
input bool           InpEnableAsia            = false;         // EnableAsia (new entries)
input string         InpAsiaStart             = "09:00";       // Asia start (Tokyo time)
input string         InpAsiaEnd               = "18:00";       // Asia end (Tokyo time)
input bool           InpEnableLondon          = true;          // EnableLondon (new entries)
input string         InpLondonStart           = "08:00";       // London start (London time)
input string         InpLondonEnd             = "17:00";       // London end (London time)
input bool           InpEnableNewYork         = true;          // EnableNewYork (new entries)
input string         InpNewYorkStart          = "08:00";       // New York start (New York time)
input string         InpNewYorkEnd            = "17:00";       // New York end (New York time)
input bool           InpEnableOverlap         = true;          // EnableOverlap (London/NY overlap, derived)
input int            InpNoEntryBeforeEndMin   = 30;            // No new entries N minutes before session end

input group "=== STRATEGY ==="
input int            InpMinimumSignalScore    = 70;    // MinimumSignalScore (0-100)
input int            InpMinimumScoreGap       = 15;    // Min gap between BUY and SELL score
input bool           InpEnableTrendPullback   = true;  // EnableTrendPullback
input bool           InpEnableBreakout        = true;  // EnableBreakout
input bool           InpEnableReversal        = true;  // EnableReversal
input int            InpReversalMinimumScore  = 80;    // Reversal minimum score (stricter)
input bool           InpAllowTransitionEntries = false; // Allow new entries in TRANSITION regime

input group "=== SCORE WEIGHTS (must sum to 100) ==="
input int            InpWeightTrend           = 20; // Trend
input int            InpWeightStructure       = 20; // Structure
input int            InpWeightMomentum        = 15; // Momentum
input int            InpWeightLiquidity       = 15; // Liquidity
input int            InpWeightVolatility      = 10; // Volatility
input int            InpWeightSession         = 10; // Session
input int            InpWeightConfirmation    = 10; // Multi-timeframe confirmation

input group "=== TIMEFRAMES ==="
input ENUM_TIMEFRAMES InpContextTimeframe      = PERIOD_H1;  // ContextTimeframe
input ENUM_TIMEFRAMES InpConfirmationTimeframe = PERIOD_M15; // ConfirmationTimeframe
input ENUM_TIMEFRAMES InpEntryTimeframe        = PERIOD_M5;  // EntryTimeframe

input group "=== INDICATORS ==="
input int            InpFastEMA               = 20;  // FastEMA
input int            InpSlowEMA               = 50;  // SlowEMA
input int            InpContextEMA            = 200; // ContextEMA
input int            InpRSIPeriod             = 14;  // RSIPeriod
input int            InpATRPeriod             = 14;  // ATRPeriod
input int            InpATRPercentileLookback = 100; // ATR percentile lookback (bars)
input int            InpSwingStrength         = 3;   // Swing strength (bars each side)

input group "=== VOLATILITY FILTER ==="
input double         InpMinimumATRPoints      = 0;    // MinimumATR in points (0 = off)
input double         InpMaximumATRPoints      = 0;    // MaximumATR in points (0 = off)
input double         InpATRPercentileMin      = 10;   // Min ATR percentile to trade
input double         InpATRPercentileMax      = 95;   // Max ATR percentile to trade

input group "=== STOP LOSS / TAKE PROFIT ==="
input ENUM_APEX_STOP_MODE InpStopMode         = APEX_STOP_HYBRID; // Stop-loss method
input double         InpStopATRBuffer         = 0.2;  // ATR buffer beyond swing
input double         InpStopATRMultiplier     = 1.5;  // ATR stop multiple (ATR mode)
input double         InpMinStopATR            = 0.5;  // Minimum stop distance (x ATR)
input double         InpMaxStopATR            = 3.0;  // Maximum stop distance (x ATR) - wider = NO TRADE
input ENUM_APEX_TP_MODE InpTakeProfitMode     = APEX_TP_FIXED_R; // Take-profit method
input double         InpTakeProfitR           = 2.0;  // Take profit (R multiple)
input double         InpTakeProfitATR         = 3.0;  // Take profit (ATR multiple, ATR mode)

input group "=== PROFIT MANAGEMENT ==="
input double         InpBreakEvenTriggerR     = 1.0;  // BreakEvenTriggerR
input int            InpBreakEvenOffsetPoints = 10;   // BreakEvenOffsetPoints
input bool           InpEnablePartialClose    = true; // Enable partial close
input double         InpPartialProfitR        = 1.5;  // PartialProfitR
input double         InpPartialClosePercent   = 30;   // PartialClosePercent
input bool           InpEnableTrailing        = true; // Enable trailing stop
input double         InpTrailingStartR        = 2.0;  // TrailingStartR
input ENUM_APEX_TRAIL_MODE InpTrailingMode    = APEX_TRAIL_ATR; // Trailing method
input double         InpTrailATRMultiplier    = 1.5;  // ATRMultiplier (trailing)
input ENUM_APEX_ADVERSE_ACTION InpAdverseRegimeAction = APEX_ADVERSE_TIGHTEN; // When regime turns against an open trade

input group "=== EXECUTION & CIRCUIT BREAKERS ==="
input int            InpMaxSpreadPoints       = 0;    // MaxSpreadPoints (0 = use ATR % only)
input double         InpMaxSpreadPercentOfATR = 15;   // MaxSpreadPercentOfATR
input int            InpMaxSlippagePoints     = 10;   // MaxSlippagePoints
input int            InpMaxOrderRetries       = 2;    // Max retries per order request
input int            InpMaxOrderFailures      = 3;    // Consecutive order failures before breaker
input int            InpStaleDataSeconds      = 120;  // Tick older than this = stale data
input double         InpMaxMarginUsePercent   = 50;   // Max % of free margin one new trade may use

input group "=== DASHBOARD & LOGGING ==="
input bool           InpShowDashboard         = true;           // Show on-chart dashboard
input int            InpDashboardFontSize     = 9;              // Dashboard font size
input ENUM_APEX_LOG_LEVEL InpLogLevel         = APEX_LOG_INFO;  // Log level
input bool           InpWriteJournalCSV       = true;           // Write CSV trade/signal journal
input bool           InpLogRejectedSignals    = true;           // Log rejected signals

//====================================================================
// CONFIG STRUCT
//====================================================================
struct SApexConfig
  {
   // general
   ENUM_APEX_MODE    mode;
   bool              enableTrading;
   bool              confirmLive;
   long              magicBase;
   bool              magicAutoOffset;
   long              magic;             // effective magic number
   string            symbol;            // resolved trade symbol
   string            strategyVersion;
   string            changeReason;
   // account & risk
   double            startingBalance;
   double            targetBalance;
   double            riskPct;
   double            maxDailyLossPct;
   double            maxAccountDailyLossPct;
   int               maxConsecutiveLosses;
   ENUM_APEX_LOSS_RESET lossStreakReset;
   bool              resetLossStreak;
   int               maxOpenPositions;
   int               maxAccountOpenPositions;
   bool              blockCorrelatedSameDir;
   // sessions (minutes after local midnight)
   ENUM_APEX_SERVER_TZ serverTimeMode;
   int               serverGmtOffsetHours;
   ENUM_APEX_DST_RULE serverDstRule;
   bool              enableAsia;
   int               asiaStartMin;
   int               asiaEndMin;
   bool              enableLondon;
   int               londonStartMin;
   int               londonEndMin;
   bool              enableNewYork;
   int               newYorkStartMin;
   int               newYorkEndMin;
   bool              enableOverlap;
   int               noEntryBeforeEndMin;
   // strategy
   int               minSignalScore;
   int               minScoreGap;
   bool              enableTrendPullback;
   bool              enableBreakout;
   bool              enableReversal;
   int               reversalMinScore;
   bool              allowTransitionEntries;
   // weights
   int               wTrend;
   int               wStructure;
   int               wMomentum;
   int               wLiquidity;
   int               wVolatility;
   int               wSession;
   int               wConfirmation;
   // timeframes
   ENUM_TIMEFRAMES   tfContext;
   ENUM_TIMEFRAMES   tfConfirm;
   ENUM_TIMEFRAMES   tfEntry;
   // indicators
   int               fastEMA;
   int               slowEMA;
   int               contextEMA;
   int               rsiPeriod;
   int               atrPeriod;
   int               atrPctLookback;
   int               swingStrength;
   // volatility
   double            minATRPoints;
   double            maxATRPoints;
   double            atrPctMin;
   double            atrPctMax;
   // SL / TP
   ENUM_APEX_STOP_MODE stopMode;
   double            stopATRBuffer;
   double            stopATRMult;
   double            minStopATR;
   double            maxStopATR;
   ENUM_APEX_TP_MODE tpMode;
   double            tpR;
   double            tpATR;
   // profit management
   double            beTriggerR;
   int               beOffsetPoints;
   bool              enablePartial;
   double            partialR;
   double            partialPct;
   bool              enableTrailing;
   double            trailStartR;
   ENUM_APEX_TRAIL_MODE trailMode;
   double            trailATRMult;
   ENUM_APEX_ADVERSE_ACTION adverseAction;
   // execution
   int               maxSpreadPoints;
   double            maxSpreadPctATR;
   int               maxSlippagePoints;
   int               maxOrderRetries;
   int               maxOrderFailures;
   int               staleDataSeconds;
   double            maxMarginUsePct;
   // dashboard & logging
   bool              showDashboard;
   int               dashboardFontSize;
   ENUM_APEX_LOG_LEVEL logLevel;
   bool              writeJournalCSV;
   bool              logRejected;
  };

//====================================================================
// HELPERS
//====================================================================

//--- Parse "HH:MM" into minutes after midnight. Returns -1 if invalid.
int ConfigParseHHMM(const string text)
  {
   string s = text;
   StringTrimLeft(s);
   StringTrimRight(s);
   string parts[];
   if(StringSplit(s, ':', parts) != 2)
      return -1;
   if(StringLen(parts[0]) < 1 || StringLen(parts[0]) > 2 || StringLen(parts[1]) != 2)
      return -1;
   for(int p = 0; p < 2; p++)
      for(int i = 0; i < StringLen(parts[p]); i++)
        {
         ushort ch = StringGetCharacter(parts[p], i);
         if(ch < '0' || ch > '9')
            return -1;
        }
   int hh = (int)StringToInteger(parts[0]);
   int mm = (int)StringToInteger(parts[1]);
   if(hh > 23 || mm > 59)
      return -1;
   return hh * 60 + mm;
  }

//--- Stable per-symbol magic offset. Known majors get fixed small offsets
//--- so logs are easy to read; anything else gets a deterministic hash.
long ConfigMagicOffset(const string symbol)
  {
   string u = symbol;
   StringToUpper(u);
   string known[] = {"XAUUSD", "EURUSD", "USDJPY", "GBPUSD", "AUDUSD",
                     "USDCAD", "USDCHF", "NZDUSD", "XAGUSD"
                    };
   for(int i = 0; i < ArraySize(known); i++)
      if(StringFind(u, known[i]) == 0)
         return i + 1;
   uint h = 0;
   for(int i = 0; i < StringLen(u); i++)
      h = h * 31 + StringGetCharacter(u, i);
   return 100 + (long)(h % 800);
  }

//--- Validate "MAJOR.MINOR.PATCH".
bool ConfigIsValidVersion(const string version)
  {
   string parts[];
   if(StringSplit(version, '.', parts) != 3)
      return false;
   for(int p = 0; p < 3; p++)
     {
      if(StringLen(parts[p]) == 0)
         return false;
      for(int i = 0; i < StringLen(parts[p]); i++)
        {
         ushort ch = StringGetCharacter(parts[p], i);
         if(ch < '0' || ch > '9')
            return false;
        }
     }
   return true;
  }

//====================================================================
// LOAD
//====================================================================
void ConfigLoad(SApexConfig &c)
  {
   c.mode            = InpTradingMode;
   c.enableTrading   = InpEnableTrading;
   c.confirmLive     = InpConfirmLiveTrading;
   c.magicBase       = InpMagicNumber;
   c.magicAutoOffset = InpMagicAutoOffset;
   c.symbol          = (InpSymbol == "") ? _Symbol : InpSymbol + InpSymbolSuffix;
   c.magic           = c.magicBase + (c.magicAutoOffset ? ConfigMagicOffset(c.symbol) : (long)0);
   c.strategyVersion = InpStrategyVersion;
   c.changeReason    = InpChangeReason;

   c.startingBalance         = InpStartingBalance;
   c.targetBalance           = InpTargetBalance;
   c.riskPct                 = InpRiskPerTradePercent;
   c.maxDailyLossPct         = InpMaxDailyLossPercent;
   c.maxAccountDailyLossPct  = InpMaxAccountDailyLossPct;
   c.maxConsecutiveLosses    = InpMaxConsecutiveLosses;
   c.lossStreakReset         = InpLossStreakReset;
   c.resetLossStreak         = InpResetLossStreak;
   c.maxOpenPositions        = InpMaxOpenPositions;
   c.maxAccountOpenPositions = InpMaxAccountOpenPositions;
   c.blockCorrelatedSameDir  = InpBlockCorrelatedSameDir;

   c.serverTimeMode       = InpServerTimeMode;
   c.serverGmtOffsetHours = InpServerGMTOffsetHours;
   c.serverDstRule        = InpServerDSTRule;
   c.enableAsia           = InpEnableAsia;
   c.asiaStartMin         = ConfigParseHHMM(InpAsiaStart);
   c.asiaEndMin           = ConfigParseHHMM(InpAsiaEnd);
   c.enableLondon         = InpEnableLondon;
   c.londonStartMin       = ConfigParseHHMM(InpLondonStart);
   c.londonEndMin         = ConfigParseHHMM(InpLondonEnd);
   c.enableNewYork        = InpEnableNewYork;
   c.newYorkStartMin      = ConfigParseHHMM(InpNewYorkStart);
   c.newYorkEndMin        = ConfigParseHHMM(InpNewYorkEnd);
   c.enableOverlap        = InpEnableOverlap;
   c.noEntryBeforeEndMin  = InpNoEntryBeforeEndMin;

   c.minSignalScore      = InpMinimumSignalScore;
   c.minScoreGap         = InpMinimumScoreGap;
   c.enableTrendPullback = InpEnableTrendPullback;
   c.enableBreakout      = InpEnableBreakout;
   c.enableReversal      = InpEnableReversal;
   c.reversalMinScore    = InpReversalMinimumScore;
   c.allowTransitionEntries = InpAllowTransitionEntries;

   c.wTrend        = InpWeightTrend;
   c.wStructure    = InpWeightStructure;
   c.wMomentum     = InpWeightMomentum;
   c.wLiquidity    = InpWeightLiquidity;
   c.wVolatility   = InpWeightVolatility;
   c.wSession      = InpWeightSession;
   c.wConfirmation = InpWeightConfirmation;

   c.tfContext = InpContextTimeframe;
   c.tfConfirm = InpConfirmationTimeframe;
   c.tfEntry   = InpEntryTimeframe;

   c.fastEMA        = InpFastEMA;
   c.slowEMA        = InpSlowEMA;
   c.contextEMA     = InpContextEMA;
   c.rsiPeriod      = InpRSIPeriod;
   c.atrPeriod      = InpATRPeriod;
   c.atrPctLookback = InpATRPercentileLookback;
   c.swingStrength  = InpSwingStrength;

   c.minATRPoints = InpMinimumATRPoints;
   c.maxATRPoints = InpMaximumATRPoints;
   c.atrPctMin    = InpATRPercentileMin;
   c.atrPctMax    = InpATRPercentileMax;

   c.stopMode      = InpStopMode;
   c.stopATRBuffer = InpStopATRBuffer;
   c.stopATRMult   = InpStopATRMultiplier;
   c.minStopATR    = InpMinStopATR;
   c.maxStopATR    = InpMaxStopATR;
   c.tpMode        = InpTakeProfitMode;
   c.tpR           = InpTakeProfitR;
   c.tpATR         = InpTakeProfitATR;

   c.beTriggerR     = InpBreakEvenTriggerR;
   c.beOffsetPoints = InpBreakEvenOffsetPoints;
   c.enablePartial  = InpEnablePartialClose;
   c.partialR       = InpPartialProfitR;
   c.partialPct     = InpPartialClosePercent;
   c.enableTrailing = InpEnableTrailing;
   c.trailStartR    = InpTrailingStartR;
   c.trailMode      = InpTrailingMode;
   c.trailATRMult   = InpTrailATRMultiplier;
   c.adverseAction  = InpAdverseRegimeAction;

   c.maxSpreadPoints   = InpMaxSpreadPoints;
   c.maxSpreadPctATR   = InpMaxSpreadPercentOfATR;
   c.maxSlippagePoints = InpMaxSlippagePoints;
   c.maxOrderRetries   = InpMaxOrderRetries;
   c.maxOrderFailures  = InpMaxOrderFailures;
   c.staleDataSeconds  = InpStaleDataSeconds;
   c.maxMarginUsePct   = InpMaxMarginUsePercent;

   c.showDashboard     = InpShowDashboard;
   c.dashboardFontSize = InpDashboardFontSize;
   c.logLevel          = InpLogLevel;
   c.writeJournalCSV   = InpWriteJournalCSV;
   c.logRejected       = InpLogRejectedSignals;
  }

//====================================================================
// VALIDATE
// Returns false with the first blocking error; non-blocking concerns
// are appended to `warnings`.
//====================================================================
bool ConfigFail(string &error, const string message)
  {
   error = message;
   return false;
  }

void ConfigWarn(string &warnings, const string message)
  {
   if(warnings != "")
      warnings += "; ";
   warnings += message;
  }

bool ConfigValidate(const SApexConfig &c, string &error, string &warnings)
  {
   error = "";
   warnings = "";

   //--- general
   if(c.symbol == "")
      return ConfigFail(error, "symbol is empty");
   if(c.magicBase <= 0)
      return ConfigFail(error, "MagicNumber must be > 0");
   if(!ConfigIsValidVersion(c.strategyVersion))
      return ConfigFail(error, "StrategyVersion must look like 1.0.0");
   if(c.mode != APEX_MODE_LIVE && c.confirmLive)
      ConfigWarn(warnings, "ConfirmLiveTrading=true has no effect outside LIVE mode");

   //--- account & risk (no escalation is possible: all values are fixed caps)
   if(c.startingBalance <= 0)
      return ConfigFail(error, "StartingBalance must be > 0");
   if(c.targetBalance <= c.startingBalance)
      return ConfigFail(error, "TargetBalance must be greater than StartingBalance");
   if(c.riskPct <= 0 || c.riskPct > APEX_HARD_MAX_RISK_PCT)
      return ConfigFail(error, StringFormat("RiskPerTradePercent must be in (0, %.1f]", APEX_HARD_MAX_RISK_PCT));
   if(c.maxDailyLossPct <= 0 || c.maxDailyLossPct > APEX_HARD_MAX_DAILY_LOSS_PCT)
      return ConfigFail(error, StringFormat("MaximumDailyLossPercent must be in (0, %.1f]", APEX_HARD_MAX_DAILY_LOSS_PCT));
   if(c.maxAccountDailyLossPct <= 0 || c.maxAccountDailyLossPct > APEX_HARD_MAX_DAILY_LOSS_PCT)
      return ConfigFail(error, StringFormat("Account max daily loss %% must be in (0, %.1f]", APEX_HARD_MAX_DAILY_LOSS_PCT));
   if(c.maxDailyLossPct < c.riskPct)
      ConfigWarn(warnings, "MaximumDailyLossPercent is below RiskPerTradePercent: one full loss stops the day");
   if(c.maxConsecutiveLosses < 1 || c.maxConsecutiveLosses > 20)
      return ConfigFail(error, "MaximumConsecutiveLosses must be 1..20");
   if(c.maxOpenPositions < 1 || c.maxOpenPositions > APEX_HARD_MAX_OPEN_POSITIONS)
      return ConfigFail(error, StringFormat("MaximumOpenPositions must be 1..%d", APEX_HARD_MAX_OPEN_POSITIONS));
   if(c.maxAccountOpenPositions < 1 || c.maxAccountOpenPositions > APEX_HARD_MAX_ACCOUNT_POSITIONS)
      return ConfigFail(error, StringFormat("Account max open positions must be 1..%d", APEX_HARD_MAX_ACCOUNT_POSITIONS));

   //--- sessions
   if(c.serverGmtOffsetHours < -12 || c.serverGmtOffsetHours > 14)
      return ConfigFail(error, "Server GMT offset must be -12..14");
   if(c.asiaStartMin < 0 || c.asiaEndMin < 0 || c.asiaStartMin == c.asiaEndMin)
      return ConfigFail(error, "Asia session times invalid (use HH:MM, start != end)");
   if(c.londonStartMin < 0 || c.londonEndMin < 0 || c.londonStartMin == c.londonEndMin)
      return ConfigFail(error, "London session times invalid (use HH:MM, start != end)");
   if(c.newYorkStartMin < 0 || c.newYorkEndMin < 0 || c.newYorkStartMin == c.newYorkEndMin)
      return ConfigFail(error, "New York session times invalid (use HH:MM, start != end)");
   if(!c.enableAsia && !c.enableLondon && !c.enableNewYork && !c.enableOverlap)
      return ConfigFail(error, "No entry session enabled");
   if(c.noEntryBeforeEndMin < 0 || c.noEntryBeforeEndMin > 180)
      return ConfigFail(error, "No-entry-before-end minutes must be 0..180");

   //--- strategy
   if(c.minSignalScore < 50 || c.minSignalScore > 100)
      return ConfigFail(error, "MinimumSignalScore must be 50..100");
   if(c.minScoreGap < 0 || c.minScoreGap > 50)
      return ConfigFail(error, "Minimum score gap must be 0..50");
   if(c.reversalMinScore < c.minSignalScore || c.reversalMinScore > 100)
      return ConfigFail(error, "Reversal minimum score must be >= MinimumSignalScore and <= 100");
   if(!c.enableTrendPullback && !c.enableBreakout && !c.enableReversal)
      return ConfigFail(error, "No strategy module enabled");

   //--- weights
   if(c.wTrend < 0 || c.wStructure < 0 || c.wMomentum < 0 || c.wLiquidity < 0 ||
      c.wVolatility < 0 || c.wSession < 0 || c.wConfirmation < 0)
      return ConfigFail(error, "Score weights must be >= 0");
   int wsum = c.wTrend + c.wStructure + c.wMomentum + c.wLiquidity +
              c.wVolatility + c.wSession + c.wConfirmation;
   if(wsum != 100)
      return ConfigFail(error, StringFormat("Score weights must sum to 100 (currently %d)", wsum));

   //--- timeframes: context > confirmation > entry, explicit (not PERIOD_CURRENT)
   if(c.tfContext == PERIOD_CURRENT || c.tfConfirm == PERIOD_CURRENT || c.tfEntry == PERIOD_CURRENT)
      return ConfigFail(error, "Timeframes must be explicit (not 'current')");
   if(!(PeriodSeconds(c.tfContext) > PeriodSeconds(c.tfConfirm) &&
        PeriodSeconds(c.tfConfirm) > PeriodSeconds(c.tfEntry)))
      return ConfigFail(error, "Timeframes must satisfy Context > Confirmation > Entry");

   //--- indicators
   if(c.fastEMA < 2 || c.slowEMA <= c.fastEMA || c.contextEMA <= c.slowEMA || c.contextEMA > 1000)
      return ConfigFail(error, "EMA periods must satisfy 2 <= Fast < Slow < Context <= 1000");
   if(c.rsiPeriod < 2 || c.rsiPeriod > 100)
      return ConfigFail(error, "RSIPeriod must be 2..100");
   if(c.atrPeriod < 2 || c.atrPeriod > 200)
      return ConfigFail(error, "ATRPeriod must be 2..200");
   if(c.atrPctLookback < 20 || c.atrPctLookback > 1000)
      return ConfigFail(error, "ATR percentile lookback must be 20..1000");
   if(c.swingStrength < 1 || c.swingStrength > 10)
      return ConfigFail(error, "Swing strength must be 1..10");

   //--- volatility
   if(c.minATRPoints < 0 || c.maxATRPoints < 0)
      return ConfigFail(error, "ATR point limits must be >= 0");
   if(c.maxATRPoints > 0 && c.maxATRPoints <= c.minATRPoints)
      return ConfigFail(error, "MaximumATR must be greater than MinimumATR");
   if(c.atrPctMin < 0 || c.atrPctMax > 100 || c.atrPctMin >= c.atrPctMax)
      return ConfigFail(error, "ATR percentile range must satisfy 0 <= min < max <= 100");

   //--- stop loss / take profit
   if(c.stopATRBuffer < 0 || c.stopATRBuffer > 2)
      return ConfigFail(error, "Stop ATR buffer must be 0..2");
   if(c.stopATRMult <= 0 || c.stopATRMult > 10)
      return ConfigFail(error, "ATR stop multiple must be in (0, 10]");
   if(c.minStopATR <= 0 || c.maxStopATR <= c.minStopATR || c.maxStopATR > 10)
      return ConfigFail(error, "Stop ATR bounds must satisfy 0 < min < max <= 10");
   if(c.tpR < 0.5 || c.tpR > 10)
      return ConfigFail(error, "Take profit R must be 0.5..10");
   if(c.tpATR <= 0 || c.tpATR > 20)
      return ConfigFail(error, "Take profit ATR multiple must be in (0, 20]");

   //--- profit management
   if(c.beTriggerR <= 0 || c.beTriggerR > 10)
      return ConfigFail(error, "BreakEvenTriggerR must be in (0, 10]");
   if(c.beOffsetPoints < 0)
      return ConfigFail(error, "BreakEvenOffsetPoints must be >= 0");
   if(c.partialR <= 0 || c.partialR > 10)
      return ConfigFail(error, "PartialProfitR must be in (0, 10]");
   if(c.partialPct < 1 || c.partialPct > 90)
      return ConfigFail(error, "PartialClosePercent must be 1..90");
   if(c.trailStartR <= 0 || c.trailStartR > 20)
      return ConfigFail(error, "TrailingStartR must be in (0, 20]");
   if(c.trailATRMult < 0.5 || c.trailATRMult > 10)
      return ConfigFail(error, "Trailing ATRMultiplier must be 0.5..10");
   if(c.enablePartial && c.tpMode == APEX_TP_FIXED_R && c.partialR >= c.tpR)
      ConfigWarn(warnings, "PartialProfitR >= TakeProfitR: partial close will never trigger");
   if(c.enableTrailing && c.tpMode == APEX_TP_FIXED_R && c.trailStartR >= c.tpR)
      ConfigWarn(warnings, "TrailingStartR >= TakeProfitR: trailing will never trigger");

   //--- execution
   if(c.maxSpreadPoints < 0)
      return ConfigFail(error, "MaxSpreadPoints must be >= 0");
   if(c.maxSpreadPctATR <= 0 || c.maxSpreadPctATR > 100)
      return ConfigFail(error, "MaxSpreadPercentOfATR must be in (0, 100]");
   if(c.maxSlippagePoints < 0)
      return ConfigFail(error, "MaxSlippagePoints must be >= 0");
   if(c.maxOrderRetries < 0 || c.maxOrderRetries > 5)
      return ConfigFail(error, "Max order retries must be 0..5");
   if(c.maxOrderFailures < 1 || c.maxOrderFailures > 20)
      return ConfigFail(error, "Order failure breaker must be 1..20");
   if(c.staleDataSeconds < 10 || c.staleDataSeconds > 3600)
      return ConfigFail(error, "Stale data seconds must be 10..3600");
   if(c.maxMarginUsePct <= 0 || c.maxMarginUsePct > 90)
      return ConfigFail(error, "Max margin use % must be in (0, 90]");

   //--- dashboard
   if(c.dashboardFontSize < 6 || c.dashboardFontSize > 20)
      return ConfigFail(error, "Dashboard font size must be 6..20");

   return true;
  }

//====================================================================
// EXECUTION PERMISSION (real-money protection, Section 49)
// Evaluated at init and periodically; the Execution engine must call
// this before every order request.
//====================================================================
bool ConfigOrdersPermitted(const SApexConfig &c, string &reason)
  {
   //--- Strategy Tester: orders are simulated, no money at risk.
   if(MQLInfoInteger(MQL_TESTER))
     {
      reason = "Strategy Tester (simulated orders)";
      return true;
     }
   if(c.mode == APEX_MODE_TEST)
     {
      reason = "TEST mode: analysis only";
      return false;
     }
   if(!c.enableTrading)
     {
      reason = "EnableTrading=false";
      return false;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      reason = "Algo Trading disabled in terminal";
      return false;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      reason = "Algo trading not allowed for this EA (Common tab)";
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     {
      reason = "Trading not allowed on this account";
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      reason = "Broker disallows expert trading on this account";
      return false;
     }

   ENUM_ACCOUNT_TRADE_MODE accMode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   bool isReal = (accMode == ACCOUNT_TRADE_MODE_REAL);

   if(c.mode == APEX_MODE_DEMO)
     {
      if(isReal)
        {
         reason = "DEMO mode refused on a REAL account";
         return false;
        }
      reason = "DEMO mode on demo account";
      return true;
     }

   // APEX_MODE_LIVE
   if(!c.confirmLive)
     {
      reason = "LIVE mode requires ConfirmLiveTrading=true";
      return false;
     }
   if(!isReal)
     {
      reason = "LIVE mode requires a REAL account (use DEMO mode on demo)";
      return false;
     }
   reason = "LIVE trading ENABLED - real money";
   return true;
  }

//====================================================================
// VERSIONING / CHANGE TRACKING (Section 43)
// Keys starting with "s." affect strategy behaviour and require a
// StrategyVersion bump when changed; "o." keys are operational.
//====================================================================
string ConfigB(const bool v)   { return v ? "true" : "false"; }
string ConfigD(const double v) { return DoubleToString(v, 4); }

string ConfigToText(const SApexConfig &c)
  {
   string t = "";
   t += "o.strategy_version=" + c.strategyVersion + "\n";
   t += "o.mode=" + ApexModeToString(c.mode) + "\n";
   t += "o.enable_trading=" + ConfigB(c.enableTrading) + "\n";
   t += "o.confirm_live=" + ConfigB(c.confirmLive) + "\n";
   t += "o.magic=" + IntegerToString(c.magic) + "\n";
   t += "o.symbol=" + c.symbol + "\n";
   t += "o.starting_balance=" + ConfigD(c.startingBalance) + "\n";
   t += "o.target_balance=" + ConfigD(c.targetBalance) + "\n";
   t += "o.server_time_mode=" + EnumToString(c.serverTimeMode) + "\n";
   t += "o.server_gmt_offset=" + IntegerToString(c.serverGmtOffsetHours) + "\n";
   t += "o.server_dst_rule=" + EnumToString(c.serverDstRule) + "\n";
   t += "o.show_dashboard=" + ConfigB(c.showDashboard) + "\n";
   t += "o.log_level=" + EnumToString(c.logLevel) + "\n";
   t += "o.write_journal=" + ConfigB(c.writeJournalCSV) + "\n";
   t += "o.log_rejected=" + ConfigB(c.logRejected) + "\n";

   t += "s.risk_pct=" + ConfigD(c.riskPct) + "\n";
   t += "s.max_daily_loss_pct=" + ConfigD(c.maxDailyLossPct) + "\n";
   t += "s.max_account_daily_loss_pct=" + ConfigD(c.maxAccountDailyLossPct) + "\n";
   t += "s.max_consecutive_losses=" + IntegerToString(c.maxConsecutiveLosses) + "\n";
   t += "s.loss_streak_reset=" + EnumToString(c.lossStreakReset) + "\n";
   t += "s.max_open_positions=" + IntegerToString(c.maxOpenPositions) + "\n";
   t += "s.max_account_open_positions=" + IntegerToString(c.maxAccountOpenPositions) + "\n";
   t += "s.block_correlated=" + ConfigB(c.blockCorrelatedSameDir) + "\n";
   t += "s.asia=" + ConfigB(c.enableAsia) + "," + IntegerToString(c.asiaStartMin) + "-" + IntegerToString(c.asiaEndMin) + "\n";
   t += "s.london=" + ConfigB(c.enableLondon) + "," + IntegerToString(c.londonStartMin) + "-" + IntegerToString(c.londonEndMin) + "\n";
   t += "s.new_york=" + ConfigB(c.enableNewYork) + "," + IntegerToString(c.newYorkStartMin) + "-" + IntegerToString(c.newYorkEndMin) + "\n";
   t += "s.overlap=" + ConfigB(c.enableOverlap) + "\n";
   t += "s.no_entry_before_end_min=" + IntegerToString(c.noEntryBeforeEndMin) + "\n";
   t += "s.min_signal_score=" + IntegerToString(c.minSignalScore) + "\n";
   t += "s.min_score_gap=" + IntegerToString(c.minScoreGap) + "\n";
   t += "s.strategies=" + ConfigB(c.enableTrendPullback) + "," + ConfigB(c.enableBreakout) + "," + ConfigB(c.enableReversal) + "\n";
   t += "s.reversal_min_score=" + IntegerToString(c.reversalMinScore) + "\n";
   t += "s.transition_entries=" + ConfigB(c.allowTransitionEntries) + "\n";
   t += "s.adverse_action=" + EnumToString(c.adverseAction) + "\n";
   t += "s.max_margin_use_pct=" + ConfigD(c.maxMarginUsePct) + "\n";
   t += "s.weights=" + IntegerToString(c.wTrend) + "," + IntegerToString(c.wStructure) + "," +
        IntegerToString(c.wMomentum) + "," + IntegerToString(c.wLiquidity) + "," +
        IntegerToString(c.wVolatility) + "," + IntegerToString(c.wSession) + "," +
        IntegerToString(c.wConfirmation) + "\n";
   t += "s.timeframes=" + EnumToString(c.tfContext) + "," + EnumToString(c.tfConfirm) + "," + EnumToString(c.tfEntry) + "\n";
   t += "s.ema=" + IntegerToString(c.fastEMA) + "," + IntegerToString(c.slowEMA) + "," + IntegerToString(c.contextEMA) + "\n";
   t += "s.rsi=" + IntegerToString(c.rsiPeriod) + "\n";
   t += "s.atr=" + IntegerToString(c.atrPeriod) + "," + IntegerToString(c.atrPctLookback) + "\n";
   t += "s.swing_strength=" + IntegerToString(c.swingStrength) + "\n";
   t += "s.atr_points=" + ConfigD(c.minATRPoints) + "," + ConfigD(c.maxATRPoints) + "\n";
   t += "s.atr_percentile=" + ConfigD(c.atrPctMin) + "," + ConfigD(c.atrPctMax) + "\n";
   t += "s.stop=" + EnumToString(c.stopMode) + "," + ConfigD(c.stopATRBuffer) + "," + ConfigD(c.stopATRMult) + "," +
        ConfigD(c.minStopATR) + "," + ConfigD(c.maxStopATR) + "\n";
   t += "s.take_profit=" + EnumToString(c.tpMode) + "," + ConfigD(c.tpR) + "," + ConfigD(c.tpATR) + "\n";
   t += "s.break_even=" + ConfigD(c.beTriggerR) + "," + IntegerToString(c.beOffsetPoints) + "\n";
   t += "s.partial=" + ConfigB(c.enablePartial) + "," + ConfigD(c.partialR) + "," + ConfigD(c.partialPct) + "\n";
   t += "s.trailing=" + ConfigB(c.enableTrailing) + "," + ConfigD(c.trailStartR) + "," +
        EnumToString(c.trailMode) + "," + ConfigD(c.trailATRMult) + "\n";
   t += "s.spread=" + IntegerToString(c.maxSpreadPoints) + "," + ConfigD(c.maxSpreadPctATR) + "\n";
   t += "s.execution=" + IntegerToString(c.maxSlippagePoints) + "," + IntegerToString(c.maxOrderRetries) + "," +
        IntegerToString(c.maxOrderFailures) + "," + IntegerToString(c.staleDataSeconds) + "\n";
   return t;
  }

//--- Value for `key` in a ConfigToText blob, or false if absent.
bool ConfigTextValue(const string text, const string key, string &value)
  {
   string lines[];
   int n = StringSplit(text, '\n', lines);
   for(int i = 0; i < n; i++)
     {
      int eq = StringFind(lines[i], "=");
      if(eq <= 0)
         continue;
      if(StringSubstr(lines[i], 0, eq) == key)
        {
         value = StringSubstr(lines[i], eq + 1);
         return true;
        }
     }
   return false;
  }

//--- Compare two config blobs. Fills `changes` with "key: old -> new".
//--- Returns the number of strategy ("s.") keys that changed.
int ConfigDiff(const string oldText, const string newText, string &changes[])
  {
   ArrayResize(changes, 0);
   int strategyChanges = 0;
   string lines[];
   int n = StringSplit(newText, '\n', lines);
   for(int i = 0; i < n; i++)
     {
      int eq = StringFind(lines[i], "=");
      if(eq <= 0)
         continue;
      string key = StringSubstr(lines[i], 0, eq);
      string nv  = StringSubstr(lines[i], eq + 1);
      string ov  = "";
      bool had   = ConfigTextValue(oldText, key, ov);
      if(had && ov == nv)
         continue;
      int k = ArraySize(changes);
      ArrayResize(changes, k + 1);
      changes[k] = key + ": " + (had ? ov : "<none>") + " -> " + nv;
      if(StringSubstr(key, 0, 2) == "s.")
         strategyChanges++;
     }
   return strategyChanges;
  }

string ConfigStateFile(const SApexConfig &c)
  {
   return "ApexFlow\\config_" + c.symbol + "_" + IntegerToString(c.magic) + ".txt";
  }

bool ConfigReadFile(const string path, string &text)
  {
   text = "";
   if(!FileIsExist(path))
      return false;
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   while(!FileIsEnding(h))
      text += FileReadString(h) + "\n";
   FileClose(h);
   return true;
  }

bool ConfigWriteFile(const string path, const string text)
  {
   int h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      PrintFormat("%s EVENT=CONFIG_SAVE_FAILED FILE=%s ERROR=%d", APEX_LOG_TAG, path, GetLastError());
      return false;
     }
   FileWriteString(h, text);
   FileClose(h);
   return true;
  }

//--- Log parameter changes since the last run and persist the current
//--- config. Warns when strategy inputs changed without a version bump.
void ConfigTrackChanges(const SApexConfig &c)
  {
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      return;
   string path    = ConfigStateFile(c);
   string current = ConfigToText(c);
   string previous = "";
   if(!ConfigReadFile(path, previous))
     {
      PrintFormat("%s EVENT=CONFIG_FIRST_RUN STRATEGY_VERSION=%s", APEX_LOG_TAG, c.strategyVersion);
      ConfigWriteFile(path, current);
      return;
     }
   string changes[];
   int strategyChanges = ConfigDiff(previous, current, changes);
   if(ArraySize(changes) == 0)
      return;

   string oldVersion = "";
   ConfigTextValue(previous, "o.strategy_version", oldVersion);
   string when = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   for(int i = 0; i < ArraySize(changes); i++)
      PrintFormat("%s EVENT=CONFIG_CHANGE TIME=%s CHANGE=%s REASON=%s",
                  APEX_LOG_TAG, when, changes[i], (c.changeReason == "" ? "<not given>" : c.changeReason));
   if(strategyChanges > 0 && oldVersion == c.strategyVersion)
      PrintFormat("%s WARNING=STRATEGY_PARAMETERS_CHANGED_WITHOUT_VERSION_BUMP VERSION=%s CHANGED=%d",
                  APEX_LOG_TAG, c.strategyVersion, strategyChanges);
   ConfigWriteFile(path, current);
  }

#endif // APEXFLOW_CONFIG_MQH
