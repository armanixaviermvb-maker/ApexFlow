//+------------------------------------------------------------------+
//| TestConfig.mq5 - Phase 2 tests for ApexFlow configuration         |
//| Run from Navigator > Scripts on any chart. Results go to the      |
//| Experts log. Places no orders.                                    |
//+------------------------------------------------------------------+
#property copyright "ApexFlow"
#property version   "1.00"

#include "../../Experts/ApexFlow/Config.mqh"

int g_pass = 0;
int g_fail = 0;

void Check(const bool condition, const string name)
  {
   if(condition)
      g_pass++;
   else
     {
      g_fail++;
      PrintFormat("[TEST] FAIL %s", name);
     }
  }

//--- Validation must reject `c` (used for single-field mutations of defaults).
void ExpectInvalid(const SApexConfig &c, const string name)
  {
   string err = "", warn = "";
   Check(!ConfigValidate(c, err, warn), name);
  }

void TestParseHHMM()
  {
   Check(ConfigParseHHMM("08:00") == 480, "parse 08:00");
   Check(ConfigParseHHMM("8:30") == 510, "parse 8:30");
   Check(ConfigParseHHMM(" 17:00 ") == 1020, "parse trimmed");
   Check(ConfigParseHHMM("00:00") == 0, "parse midnight");
   Check(ConfigParseHHMM("23:59") == 1439, "parse 23:59");
   Check(ConfigParseHHMM("24:00") == -1, "reject 24:00");
   Check(ConfigParseHHMM("12:60") == -1, "reject minute 60");
   Check(ConfigParseHHMM("12:5") == -1, "reject single-digit minute");
   Check(ConfigParseHHMM("1200") == -1, "reject missing colon");
   Check(ConfigParseHHMM("ab:cd") == -1, "reject letters");
   Check(ConfigParseHHMM("") == -1, "reject empty");
  }

void TestVersion()
  {
   Check(ConfigIsValidVersion("1.0.0"), "version 1.0.0");
   Check(ConfigIsValidVersion("12.3.45"), "version 12.3.45");
   Check(!ConfigIsValidVersion("1.0"), "reject 1.0");
   Check(!ConfigIsValidVersion("1.0.x"), "reject 1.0.x");
   Check(!ConfigIsValidVersion("1..0"), "reject 1..0");
  }

void TestMagicOffset()
  {
   Check(ConfigMagicOffset("XAUUSD") == 1, "magic XAUUSD");
   Check(ConfigMagicOffset("XAUUSDm") == 1, "magic XAUUSDm (suffix ignored)");
   Check(ConfigMagicOffset("xauusdc") == 1, "magic lower-case cent");
   Check(ConfigMagicOffset("EURUSDm") == 2, "magic EURUSDm");
   Check(ConfigMagicOffset("USDJPY") == 3, "magic USDJPY");
   Check(ConfigMagicOffset("GBPUSD") == 4, "magic GBPUSD");
   long h1 = ConfigMagicOffset("EURGBP");
   long h2 = ConfigMagicOffset("EURGBP");
   Check(h1 == h2 && h1 >= 100 && h1 < 900, "magic hash stable and in range");
  }

void TestDefaultsValid()
  {
   SApexConfig c;
   ConfigLoad(c);
   string err = "", warn = "";
   bool ok = ConfigValidate(c, err, warn);
   if(!ok)
      PrintFormat("[TEST] default config error: %s", err);
   Check(ok, "default config is valid");
   Check(c.mode == APEX_MODE_TEST, "default mode is TEST");
   Check(!c.enableTrading, "EnableTrading defaults to false");
   Check(!c.confirmLive, "ConfirmLiveTrading defaults to false");
   Check(c.riskPct <= APEX_HARD_MAX_RISK_PCT, "default risk within hard cap");
   Check(c.maxOpenPositions == 1, "default max open positions is 1");
  }

void TestValidationRejects()
  {
   SApexConfig base;
   ConfigLoad(base);
   SApexConfig c;

   c = base; c.riskPct = APEX_HARD_MAX_RISK_PCT + 0.01; ExpectInvalid(c, "reject risk above hard cap");
   c = base; c.riskPct = 0;                     ExpectInvalid(c, "reject zero risk");
   c = base; c.maxDailyLossPct = 50;            ExpectInvalid(c, "reject daily loss above cap");
   c = base; c.maxOpenPositions = 0;            ExpectInvalid(c, "reject 0 open positions");
   c = base; c.maxOpenPositions = APEX_HARD_MAX_OPEN_POSITIONS + 1; ExpectInvalid(c, "reject too many positions");
   c = base; c.targetBalance = c.startingBalance; ExpectInvalid(c, "reject target <= start");
   c = base; c.wTrend = 30;                     ExpectInvalid(c, "reject weights not summing to 100");
   c = base; c.wTrend = -5; c.wStructure = 45;  ExpectInvalid(c, "reject negative weight");
   c = base; c.tfEntry = PERIOD_H4;             ExpectInvalid(c, "reject entry TF above confirmation");
   c = base; c.tfContext = PERIOD_CURRENT;      ExpectInvalid(c, "reject PERIOD_CURRENT");
   c = base; c.slowEMA = c.fastEMA;             ExpectInvalid(c, "reject slow EMA == fast EMA");
   c = base; c.londonStartMin = -1;             ExpectInvalid(c, "reject bad London time");
   c = base; c.londonEndMin = c.londonStartMin; ExpectInvalid(c, "reject empty London session");
   c = base; c.enableAsia = false; c.enableLondon = false; c.enableNewYork = false; c.enableOverlap = false;
   ExpectInvalid(c, "reject no sessions");
   c = base; c.enableTrendPullback = false; c.enableBreakout = false; c.enableReversal = false;
   ExpectInvalid(c, "reject no strategies");
   c = base; c.reversalMinScore = c.minSignalScore - 1; ExpectInvalid(c, "reject reversal score below minimum");
   c = base; c.minStopATR = 2; c.maxStopATR = 1; ExpectInvalid(c, "reject min stop > max stop");
   c = base; c.atrPctMin = 90; c.atrPctMax = 10; ExpectInvalid(c, "reject inverted ATR percentile");
   c = base; c.partialPct = 100;                ExpectInvalid(c, "reject 100% partial close");
   c = base; c.strategyVersion = "v1";          ExpectInvalid(c, "reject bad strategy version");
   c = base; c.magicBase = 0;                   ExpectInvalid(c, "reject zero magic");
  }

void TestWarnings()
  {
   SApexConfig c;
   ConfigLoad(c);
   string err = "", warn = "";
   c.partialR = 3.0;
   c.tpR = 2.0;
   Check(ConfigValidate(c, err, warn) && StringFind(warn, "PartialProfitR") >= 0,
         "warn when partial R >= TP R");
  }

void TestDiff()
  {
   SApexConfig a;
   ConfigLoad(a);
   SApexConfig b;
   b = a;
   string changes[];

   Check(ConfigDiff(ConfigToText(a), ConfigToText(b), changes) == 0 && ArraySize(changes) == 0,
         "diff identical configs");

   b.mode = APEX_MODE_DEMO;
   Check(ConfigDiff(ConfigToText(a), ConfigToText(b), changes) == 0 && ArraySize(changes) == 1,
         "mode change is operational, not strategy");

   b = a;
   b.riskPct = 0.5;
   b.minSignalScore = 75;
   Check(ConfigDiff(ConfigToText(a), ConfigToText(b), changes) == 2, "two strategy changes detected");

   string v = "";
   Check(ConfigTextValue(ConfigToText(a), "o.strategy_version", v) && v == a.strategyVersion,
         "read strategy version from text");
  }

void TestPermissionOutsideTester()
  {
   // TEST mode must never permit real orders outside the Strategy Tester.
   SApexConfig c;
   ConfigLoad(c);
   string reason = "";
   c.mode = APEX_MODE_TEST;
   c.enableTrading = true;
   c.confirmLive = true;
   Check(!ConfigOrdersPermitted(c, reason), "TEST mode blocks orders even with all switches on");

   c.mode = APEX_MODE_LIVE;
   c.enableTrading = false;
   c.confirmLive = true;
   Check(!ConfigOrdersPermitted(c, reason), "LIVE blocked when EnableTrading=false");

   c.enableTrading = true;
   c.confirmLive = false;
   Check(!ConfigOrdersPermitted(c, reason), "LIVE blocked when ConfirmLiveTrading=false");

   ENUM_ACCOUNT_TRADE_MODE accMode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(accMode != ACCOUNT_TRADE_MODE_REAL)
     {
      c.confirmLive = true;
      Check(!ConfigOrdersPermitted(c, reason), "LIVE blocked on non-real account");
     }
   else
     {
      c.mode = APEX_MODE_DEMO;
      Check(!ConfigOrdersPermitted(c, reason), "DEMO blocked on real account");
     }
  }

void OnStart()
  {
   TestParseHHMM();
   TestVersion();
   TestMagicOffset();
   TestDefaultsValid();
   TestValidationRejects();
   TestWarnings();
   TestDiff();
   TestPermissionOutsideTester();
   PrintFormat("[TEST] TestConfig: %d passed, %d failed", g_pass, g_fail);
  }
