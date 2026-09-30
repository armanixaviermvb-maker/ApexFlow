//+------------------------------------------------------------------+
//| TestCore.mq5 - offline tests of ApexFlow logic (no orders).       |
//|                                                                   |
//| Covers: DST, session detection, volume normalization, position    |
//| sizing, stop/TP calculation, structure, regime, scoring, BUY /    |
//| SELL / NO_TRADE decisions, break-even, trailing, partial close,   |
//| SL-never-backwards, reconciliation diff, retcode handling.        |
//| Run from Navigator > Scripts on any chart; see the Experts tab.   |
//+------------------------------------------------------------------+
#property copyright "ApexFlow"
#property version   "1.00"

#include "../../Experts/ApexFlow/Config.mqh"
#include "../../Experts/ApexFlow/Utils.mqh"
#include "../../Experts/ApexFlow/Core/SessionEngine.mqh"
#include "../../Experts/ApexFlow/Core/StructureEngine.mqh"
#include "../../Experts/ApexFlow/Core/RegimeEngine.mqh"
#include "../../Experts/ApexFlow/Core/SignalEngine.mqh"
#include "../../Experts/ApexFlow/Core/RiskEngine.mqh"
#include "../../Experts/ApexFlow/Execution/PositionManager.mqh"
#include "../../Experts/ApexFlow/Execution/Reconciliation.mqh"
#include "TestFramework.mqh"

//====================================================================
void TestDst()
  {
   CheckInt(ApexLastSunday(2026, 3), T("2026.03.29 00:00"), "EU last Sunday March 2026");
   CheckInt(ApexLastSunday(2026, 10), T("2026.10.25 00:00"), "EU last Sunday October 2026");
   CheckInt(ApexNthSunday(2026, 3, 2), T("2026.03.08 00:00"), "US 2nd Sunday March 2026");
   CheckInt(ApexNthSunday(2026, 11, 1), T("2026.11.01 00:00"), "US 1st Sunday November 2026");
   CheckInt(ApexLastSunday(2025, 3), T("2025.03.30 00:00"), "EU last Sunday March 2025");
   CheckInt(ApexNthSunday(2025, 11, 1), T("2025.11.02 00:00"), "US 1st Sunday November 2025");

   Check(!ApexIsEuDst(T("2026.03.29 00:59")), "EU DST not yet at 00:59 UTC");
   Check(ApexIsEuDst(T("2026.03.29 01:00")), "EU DST starts 01:00 UTC");
   Check(ApexIsEuDst(T("2026.10.25 00:59")), "EU DST still on 00:59 UTC");
   Check(!ApexIsEuDst(T("2026.10.25 01:00")), "EU DST ends 01:00 UTC");
   Check(!ApexIsUsDst(T("2026.03.08 06:59")), "US DST not yet 06:59 UTC");
   Check(ApexIsUsDst(T("2026.03.08 07:00")), "US DST starts 07:00 UTC");
   Check(ApexIsUsDst(T("2026.11.01 05:59")), "US DST still on 05:59 UTC");
   Check(!ApexIsUsDst(T("2026.11.01 06:00")), "US DST ends 06:00 UTC");

   // Broker server on GMT+2 with EU DST (GMT+3 in summer).
   CheckInt(ApexManualServerOffsetSec(2, APEX_DST_EU, T("2026.07.15 12:00")), 3 * 3600, "server GMT+2 EU summer = +3");
   CheckInt(ApexManualServerOffsetSec(2, APEX_DST_EU, T("2026.01.15 12:00")), 2 * 3600, "server GMT+2 EU winter = +2");
   CheckInt(ApexManualServerOffsetSec(0, APEX_DST_NONE, T("2026.07.15 12:00")), 0, "server GMT+0 no DST");
  }

//====================================================================
void Session(const SApexConfig &c, const string utc, SSessionState &s)
  {
   ZeroMemory(s);
   ApexClassifySession(c, T(utc), s);
  }

void TestSessions()
  {
   SApexConfig c;
   ConfigLoad(c);
   c.londonStartMin = 480;   // 08:00 London
   c.londonEndMin   = 1020;  // 17:00 London
   c.newYorkStartMin = 480;  // 08:00 New York
   c.newYorkEndMin   = 1020; // 17:00 New York
   c.enableLondon = true;
   c.enableNewYork = true;
   c.enableOverlap = true;
   c.enableAsia = false;
   c.noEntryBeforeEndMin = 30;
   SSessionState s;

   Session(c, "2026.07.15 07:00", s);
   Check(s.session == APEX_SESSION_LONDON && s.entriesAllowed, "summer 07:00 UTC = London open (08:00 BST)");
   Session(c, "2026.01.15 07:00", s);
   Check(s.session != APEX_SESSION_LONDON && !s.entriesAllowed, "winter 07:00 UTC = before London open");
   Session(c, "2026.01.15 08:00", s);
   Check(s.session == APEX_SESSION_LONDON && s.entriesAllowed, "winter 08:00 UTC = London open (08:00 GMT)");
   Session(c, "2026.07.15 12:00", s);
   Check(s.session == APEX_SESSION_OVERLAP, "summer 12:00 UTC = overlap");
   Session(c, "2026.01.15 12:00", s);
   Check(s.session == APEX_SESSION_LONDON, "winter 12:00 UTC = London only (NY 07:00)");
   Session(c, "2026.01.15 13:00", s);
   Check(s.session == APEX_SESSION_OVERLAP, "winter 13:00 UTC = overlap");
   Session(c, "2026.03.20 12:00", s);
   Check(s.session == APEX_SESSION_OVERLAP, "DST gap week: US on DST, UK not -> overlap at 12:00 UTC");
   Session(c, "2026.07.15 15:45", s);
   Check(s.session == APEX_SESSION_OVERLAP && s.entriesAllowed, "London closing but NY continues -> entries allowed");
   Session(c, "2026.07.15 20:45", s);
   Check(s.session == APEX_SESSION_NEW_YORK && !s.entriesAllowed && s.endingSoon, "15 min before NY close -> no new entries");
   Session(c, "2026.07.15 22:00", s);
   Check(!s.entriesAllowed, "after NY close -> no new entries");
   Session(c, "2026.07.18 12:00", s);
   Check(s.session == APEX_SESSION_OUTSIDE && !s.entriesAllowed, "Saturday -> outside session");

   c.enableOverlap = false;
   Session(c, "2026.07.15 12:00", s);
   Check(!s.entriesAllowed, "overlap disabled blocks entries during overlap");
  }

//====================================================================
void TestVolume()
  {
   CheckNear(ApexNormalizeVolumeDown(0.019, 0.01, 100, 0.01), 0.01, 1e-9, "0.019 -> 0.01 (rounded down)");
   CheckNear(ApexNormalizeVolumeDown(0.009, 0.01, 100, 0.01), 0.0, 1e-9, "below minimum -> 0 (never rounded up)");
   CheckNear(ApexNormalizeVolumeDown(0.25, 0.1, 100, 0.1), 0.2, 1e-9, "step 0.1: 0.25 -> 0.2");
   CheckNear(ApexNormalizeVolumeDown(150, 0.01, 100, 0.01), 100, 1e-9, "clamped to maximum");
   CheckNear(ApexNormalizeVolumeDown(0.07, 0.01, 100, 0.01), 0.07, 1e-9, "exact step kept");

   // $3 account, 1% risk = 0.03; a 20-pip EURUSD stop costs ~200 per lot -> 0.00015 lots.
   CheckNear(ApexCalcVolume(0.03, 200, 0.01, 100, 0.01), 0.0, 1e-9, "$3 @1% cannot afford min lot -> 0");
   CheckNear(ApexCalcVolume(10, 100, 0.01, 100, 0.01), 0.10, 1e-9, "risk 10 / 100 per lot = 0.10");
   CheckNear(ApexCalcVolume(10.5, 100, 0.01, 100, 0.01), 0.10, 1e-9, "0.105 rounded down to 0.10");
   CheckNear(ApexCalcVolume(10, 100, 0.01, 0.05, 0.01), 0.05, 1e-9, "respects max volume");
   CheckNear(ApexCalcVolume(10, 0, 0.01, 100, 0.01), 0.0, 1e-9, "zero loss-per-lot -> 0");
   Check(ApexCalcVolume(10.5, 100, 0.01, 100, 0.01) * 100 <= 10.5 + 1e-9, "sized risk never exceeds budget");

   CheckInt(ApexStepDigits(0.01), 2, "step digits 0.01");
   CheckInt(ApexStepDigits(0.1), 1, "step digits 0.1");
   CheckInt(ApexStepDigits(1.0), 0, "step digits 1");
  }

//====================================================================
void TestStops()
  {
   SApexConfig c;
   ConfigLoad(c);
   c.stopMode = APEX_STOP_HYBRID;
   c.minStopATR = 0.5;
   c.maxStopATR = 3.0;
   ENUM_APEX_REJECT rej;
   double atr = 0.0010;

   CheckNear(ApexComputeStop(APEX_DIR_BUY, 1.1000, 1.0990, atr, c, rej), 1.0990, 1e-9, "buy structural stop kept");
   CheckNear(ApexComputeStop(APEX_DIR_BUY, 1.1000, 1.0998, atr, c, rej), 1.0995, 1e-9, "hybrid widens tight stop to 0.5 ATR");
   Check(ApexComputeStop(APEX_DIR_BUY, 1.1000, 1.0960, atr, c, rej) == 0 && rej == APEX_REJECT_STOP_TOO_WIDE, "stop > 3 ATR rejected");
   Check(ApexComputeStop(APEX_DIR_BUY, 1.1000, 1.1010, atr, c, rej) == 0 && rej == APEX_REJECT_INVALID_STOP, "buy stop above entry rejected");
   CheckNear(ApexComputeStop(APEX_DIR_SELL, 1.1000, 1.1012, atr, c, rej), 1.1012, 1e-9, "sell structural stop kept");
   Check(ApexComputeStop(APEX_DIR_SELL, 1.1000, 1.0990, atr, c, rej) == 0 && rej == APEX_REJECT_INVALID_STOP, "sell stop below entry rejected");
   Check(ApexComputeStop(APEX_DIR_BUY, 1.1000, 1.0990, 0, c, rej) == 0, "no ATR -> no stop -> no trade");

   c.stopMode = APEX_STOP_ATR;
   c.stopATRMult = 1.5;
   CheckNear(ApexComputeStop(APEX_DIR_BUY, 1.1000, 0, atr, c, rej), 1.0985, 1e-9, "ATR stop 1.5 ATR");

   c.stopMode = APEX_STOP_STRUCTURE;
   Check(ApexComputeStop(APEX_DIR_BUY, 1.1000, 1.0998, atr, c, rej) == 0, "structure mode rejects too-tight stop");

   SLiquidityState liq;
   SStructureState st;
   ZeroMemory(liq);
   ZeroMemory(st);
   c.tpMode = APEX_TP_FIXED_R;
   c.tpR = 2.0;
   CheckNear(ApexComputeTakeProfit(APEX_DIR_BUY, 1.1000, 1.0990, atr, liq, st, c), 1.1020, 1e-9, "buy TP = 2R");
   CheckNear(ApexComputeTakeProfit(APEX_DIR_SELL, 1.1000, 1.1010, atr, liq, st, c), 1.0980, 1e-9, "sell TP = 2R");
   c.tpMode = APEX_TP_STRUCTURE;
   liq.pdh = 1.1015;
   CheckNear(ApexComputeTakeProfit(APEX_DIR_BUY, 1.1000, 1.0990, atr, liq, st, c), 1.1015, 1e-9, "structure TP at PDH (>=1R)");
   liq.pdh = 1.1005;
   CheckNear(ApexComputeTakeProfit(APEX_DIR_BUY, 1.1000, 1.0990, atr, liq, st, c), 1.1020, 1e-9, "level < 1R away -> fixed R fallback");
  }

//====================================================================
//--- Build series rates (index 0 = newest) from oldest->newest closes.
void BuildRates(const double &path[], MqlRates &r[])
  {
   int n = ArraySize(path);
   ArrayResize(r, n);
   double prev = path[0];
   for(int i = 0; i < n; i++)
     {
      int k = n - 1 - i;           // series index
      double o = prev, cl = path[i];
      r[k].open  = o;
      r[k].close = cl;
      r[k].high  = MathMax(o, cl) + 0.3;
      r[k].low   = MathMin(o, cl) - 0.3;
      r[k].time  = (datetime)(1700000000 + i * 300);
      r[k].tick_volume = 1;
      r[k].spread = 0;
      r[k].real_volume = 0;
      prev = cl;
     }
  }

void BullPath(double &path[])
  {
   ArrayResize(path, 0);
   double p = 100;
   int n = 0;
   ArrayResize(path, 38);
   path[n++] = p;
   for(int k = 0; k < 6; k++)
     {
      for(int j = 0; j < 4; j++)
        {
         p += 1;
         path[n++] = p;
        }
      for(int j = 0; j < 2; j++)
        {
         p -= 1;
         path[n++] = p;
        }
     }
   p += 1;
   path[n++] = p;
   ArrayResize(path, n);
  }

void TestStructure()
  {
   double path[];
   MqlRates r[];
   SStructureState s;

   BullPath(path);
   BuildRates(path, r);
   ApexAnalyzeStructure(r, ArraySize(r), 2, 20, s);
   Check(s.valid && s.bias == APEX_BIAS_BULLISH, "rising zigzag = bullish structure");
   Check(s.higherHigh && s.higherLow, "rising zigzag has HH and HL");
   CheckNear(s.lastHigh, 114.3, 1e-9, "latest swing high");
   CheckNear(s.lastLow, 109.7, 1e-9, "latest swing low");

   double bear[];
   ArrayResize(bear, ArraySize(path));
   for(int i = 0; i < ArraySize(path); i++)
      bear[i] = 200 - path[i];
   BuildRates(bear, r);
   ApexAnalyzeStructure(r, ArraySize(r), 2, 20, s);
   Check(s.valid && s.bias == APEX_BIAS_BEARISH, "falling zigzag = bearish structure");
   Check(s.lowerHigh && s.lowerLow, "falling zigzag has LH and LL");

   int n = ArraySize(path);
   ArrayResize(path, n + 1);
   path[n] = path[n - 1] - 6;       // decisive close below the last swing low
   BuildRates(path, r);
   ApexAnalyzeStructure(r, ArraySize(r), 2, 20, s);
   Check(s.bosDown && s.bias == APEX_BIAS_TRANSITION, "bearish break of bullish structure = transition");

   // Liquidity: last bar sweeps below PDL and closes back above it.
   BullPath(path);
   BuildRates(path, r);
   ApexAnalyzeStructure(r, ArraySize(r), 2, 20, s);
   SLiquidityState l;
   double pdl = r[0].low + 0.1;
   ApexAnalyzeLiquidity(r, ArraySize(r), s, 130, pdl, (datetime)0, 1.0, l);
   Check(l.sweptLow && MathAbs(l.sweptLowLevel - pdl) < 1e-9, "sweep below PDL detected");
  }

//====================================================================
void TestRegime()
  {
   SRegimeInputs inp;
   int vote, align;

   ZeroMemory(inp);
   inp.emaFastCtx = 1.3; inp.emaSlowCtx = 1.2; inp.emaLongCtx = 1.1;
   inp.slopeNorm = 0.5; inp.rsiCtx = 60; inp.returnAtr = 2; inp.atrPercentile = 50;
   inp.rangeWidthAtr = 8; inp.confirmBias = APEX_BIAS_BULLISH;
   Check(ApexClassifyRegime(inp, vote, align) == APEX_REGIME_TREND_UP && vote == 5, "all bullish votes = TREND_UP");

   inp.emaFastCtx = 1.1; inp.emaLongCtx = 1.3;
   inp.slopeNorm = -0.5; inp.rsiCtx = 40; inp.returnAtr = -2; inp.confirmBias = APEX_BIAS_BEARISH;
   Check(ApexClassifyRegime(inp, vote, align) == APEX_REGIME_TREND_DOWN && vote == -5, "all bearish votes = TREND_DOWN");

   inp.atrPercentile = 95;
   Check(ApexClassifyRegime(inp, vote, align) == APEX_REGIME_HIGH_VOL, "ATR percentile 95 = HIGH_VOLATILITY");
   inp.atrPercentile = 5;
   Check(ApexClassifyRegime(inp, vote, align) == APEX_REGIME_LOW_VOL, "ATR percentile 5 = LOW_VOLATILITY");

   ZeroMemory(inp);
   inp.emaFastCtx = 1.2; inp.emaSlowCtx = 1.3; inp.emaLongCtx = 1.1; // not aligned
   inp.rsiCtx = 50; inp.atrPercentile = 50; inp.rangeWidthAtr = 4; inp.confirmBias = APEX_BIAS_RANGE;
   Check(ApexClassifyRegime(inp, vote, align) == APEX_REGIME_RANGE, "mixed votes + narrow range = RANGE");
   inp.confirmBias = APEX_BIAS_TRANSITION;
   Check(ApexClassifyRegime(inp, vote, align) == APEX_REGIME_TRANSITION, "structure transition = TRANSITION");

   // Single indicator cannot create a trend: only EMA aligned.
   ZeroMemory(inp);
   inp.emaFastCtx = 1.3; inp.emaSlowCtx = 1.2; inp.emaLongCtx = 1.1;
   inp.rsiCtx = 50; inp.atrPercentile = 50; inp.rangeWidthAtr = 4; inp.confirmBias = APEX_BIAS_RANGE;
   Check(ApexClassifyRegime(inp, vote, align) != APEX_REGIME_TREND_UP, "EMA alignment alone is not a trend");

   // Hysteresis.
   CRegimeEngine eng;
   SRegimeInputs up;
   ZeroMemory(up);
   up.emaFastCtx = 1.3; up.emaSlowCtx = 1.2; up.emaLongCtx = 1.1; up.slopeNorm = 0.5; up.rsiCtx = 60;
   up.returnAtr = 2; up.atrPercentile = 50; up.rangeWidthAtr = 8; up.confirmBias = APEX_BIAS_BULLISH;
   SRegimeInputs rng;
   ZeroMemory(rng);
   rng.emaFastCtx = 1.2; rng.emaSlowCtx = 1.3; rng.emaLongCtx = 1.1; rng.rsiCtx = 50; rng.atrPercentile = 50;
   rng.rangeWidthAtr = 4; rng.confirmBias = APEX_BIAS_RANGE;
   SRegimeInputs tr = rng;
   tr.confirmBias = APEX_BIAS_TRANSITION;
   eng.Update(up, 1);
   Check(eng.Regime() == APEX_REGIME_TREND_UP, "hysteresis: initial TREND_UP");
   eng.Update(rng, 2);
   Check(eng.Regime() == APEX_REGIME_TREND_UP, "hysteresis: one RANGE reading does not switch");
   eng.Update(rng, 3);
   Check(eng.Regime() == APEX_REGIME_RANGE, "hysteresis: second RANGE reading switches");
   eng.Update(tr, 4);
   Check(eng.Regime() == APEX_REGIME_TRANSITION, "TRANSITION applies immediately (risk-reducing)");
  }

//====================================================================
void TestScoring()
  {
   SApexConfig c;
   ConfigLoad(c);
   SScoreInputs inp;
   ZeroMemory(inp);
   inp.vote = 5; inp.ctxEmaAlign = 1; inp.confirmBias = APEX_BIAS_BULLISH; inp.entryBias = APEX_BIAS_BULLISH;
   inp.confirmBosUp = true; inp.rsiEntry = 60; inp.closeEntry = 1.2; inp.emaFastEntry = 1.1;
   inp.sweptLow = true; inp.roomUpAtr = 5; inp.roomDownAtr = 5; inp.atrPercentile = 50; inp.session = APEX_SESSION_OVERLAP;
   SScoreBreakdown buy, sell;
   ApexComputeScores(inp, c, buy, sell);
   CheckNear(buy.total, 100.0, 1e-6, "perfect bullish inputs = BUY 100");
   CheckNear(sell.total, 32.0, 1e-6, "perfect bullish inputs -> SELL 32 (momentum 4.5 + liquidity 7.5 + vol 10 + session 10)");
   Check(buy.total - sell.total >= 50, "BUY dominates SELL for bullish inputs");
   Check(buy.total >= 0 && buy.total <= 100 && sell.total >= 0 && sell.total <= 100, "scores within 0..100");

   inp.session = APEX_SESSION_OUTSIDE;
   ApexComputeScores(inp, c, buy, sell);
   CheckNear(buy.total, 100.0 - c.wSession, 1e-6, "outside session removes session weight");

   // Symmetry: mirrored inputs give mirrored scores.
   SScoreInputs m;
   ZeroMemory(m);
   m.vote = -5; m.ctxEmaAlign = -1; m.confirmBias = APEX_BIAS_BEARISH; m.entryBias = APEX_BIAS_BEARISH;
   m.confirmBosDown = true; m.rsiEntry = 40; m.closeEntry = 1.1; m.emaFastEntry = 1.2;
   m.sweptHigh = true; m.roomUpAtr = 5; m.roomDownAtr = 5; m.atrPercentile = 50; m.session = APEX_SESSION_OVERLAP;
   SScoreBreakdown b2, s2;
   ApexComputeScores(m, c, b2, s2);
   CheckNear(s2.total, 100.0, 1e-6, "mirrored bearish inputs = SELL 100");
  }

//====================================================================
void MakeScores(const double b, const double s, SScoreBreakdown &buy, SScoreBreakdown &sell)
  {
   ZeroMemory(buy);
   ZeroMemory(sell);
   buy.total = b;
   sell.total = s;
  }

void MakeSetup(SSetup &x, const int dir, const ENUM_APEX_STRATEGY st, const bool valid, const double stop)
  {
   x.valid = valid;
   x.dir = dir;
   x.strategy = st;
   x.structuralStop = stop;
   x.quality = 0.5;
   x.note = valid ? "test setup" : "test: no setup";
  }

void TestDecisions()
  {
   SApexConfig c;
   ConfigLoad(c);
   c.minSignalScore = 70;
   c.minScoreGap = 15;
   c.reversalMinScore = 80;
   c.allowTransitionEntries = false;
   SScoreBreakdown buy, sell;
   SSetup setups[2];
   SSignalResult r;

   MakeScores(85, 30, buy, sell);
   MakeSetup(setups[0], APEX_DIR_BUY, APEX_STRAT_TREND_PULLBACK, true, 1.0990);
   MakeSetup(setups[1], APEX_DIR_SELL, APEX_STRAT_TREND_PULLBACK, false, 0);
   ApexDecide(c, APEX_REGIME_TREND_UP, 4, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_BUY && r.strategy == APEX_STRAT_TREND_PULLBACK, "TREND_UP + strong BUY + setup = BUY");
   CheckNear(r.structuralStop, 1.0990, 1e-9, "BUY carries the setup stop");

   MakeSetup(setups[0], APEX_DIR_BUY, APEX_STRAT_TREND_PULLBACK, false, 0);
   ApexDecide(c, APEX_REGIME_TREND_UP, 4, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_NO_TRADE && r.reject == APEX_REJECT_NO_SETUP, "high score without setup = NO_TRADE");

   MakeScores(60, 30, buy, sell);
   MakeSetup(setups[0], APEX_DIR_BUY, APEX_STRAT_TREND_PULLBACK, true, 1.0990);
   ApexDecide(c, APEX_REGIME_TREND_UP, 4, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_NO_TRADE && r.reject == APEX_REJECT_SCORE_BELOW_THRESHOLD, "score below threshold = NO_TRADE");

   MakeScores(80, 70, buy, sell);
   ApexDecide(c, APEX_REGIME_TREND_UP, 4, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_NO_TRADE && r.reject == APEX_REJECT_SCORE_GAP, "BUY and SELL too close = NO_TRADE");

   MakeScores(30, 85, buy, sell);
   MakeSetup(setups[0], APEX_DIR_BUY, APEX_STRAT_TREND_PULLBACK, false, 0);
   MakeSetup(setups[1], APEX_DIR_SELL, APEX_STRAT_TREND_PULLBACK, true, 1.1012);
   ApexDecide(c, APEX_REGIME_TREND_DOWN, -4, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_SELL, "TREND_DOWN + strong SELL + setup = SELL");

   ApexDecide(c, APEX_REGIME_TREND_UP, 4, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_NO_TRADE, "adaptive: TREND_UP never opens a SELL pullback");

   MakeScores(85, 30, buy, sell);
   MakeSetup(setups[0], APEX_DIR_BUY, APEX_STRAT_TREND_PULLBACK, true, 1.0990);
   ApexDecide(c, APEX_REGIME_TREND_DOWN, -4, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_NO_TRADE, "adaptive: after regime flips down, old BUY setup is invalid");

   ApexDecide(c, APEX_REGIME_TRANSITION, 0, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_NO_TRADE && r.reject == APEX_REJECT_REGIME_TRANSITION, "TRANSITION = NO_TRADE by default");

   MakeScores(82, 30, buy, sell);
   MakeSetup(setups[0], APEX_DIR_BUY, APEX_STRAT_REVERSAL, true, 1.0990);
   ApexDecide(c, APEX_REGIME_RANGE, 0, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_BUY && r.strategy == APEX_STRAT_REVERSAL, "RANGE reversal at 82 >= 80 = BUY");
   MakeScores(75, 30, buy, sell);
   ApexDecide(c, APEX_REGIME_RANGE, 0, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_NO_TRADE, "RANGE reversal at 75 < 80 = NO_TRADE (stricter threshold)");

   MakeScores(75, 20, buy, sell);
   MakeSetup(setups[0], APEX_DIR_BUY, APEX_STRAT_TREND_PULLBACK, true, 1.0990);
   ApexDecide(c, APEX_REGIME_HIGH_VOL, 3, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_NO_TRADE, "HIGH_VOLATILITY needs +10 score (75 < 80)");
   ApexDecide(c, APEX_REGIME_UNKNOWN, 0, buy, sell, setups, 2, r);
   Check(r.decision == APEX_DECISION_NO_TRADE && r.reject == APEX_REJECT_DATA_NOT_READY, "UNKNOWN regime = NO_TRADE");
  }

//====================================================================
void TestProtection()
  {
   CheckNear(ApexProfitR(APEX_DIR_BUY, 1.1000, 1.1010, 0.0010), 1.0, 1e-9, "BUY +1R");
   CheckNear(ApexProfitR(APEX_DIR_SELL, 1.1000, 1.1010, 0.0010), -1.0, 1e-9, "SELL -1R");

   CheckNear(ApexBreakEvenSL(APEX_DIR_BUY, 1.1000, 0.0001), 1.1001, 1e-9, "BUY break-even = entry + offset");
   CheckNear(ApexBreakEvenSL(APEX_DIR_SELL, 1.1000, 0.0001), 1.0999, 1e-9, "SELL break-even = entry - offset");

   Check(ApexSLImproves(APEX_DIR_BUY, 1.0990, 1.1000, 0), "BUY: raising SL reduces risk");
   Check(!ApexSLImproves(APEX_DIR_BUY, 1.0990, 1.0980, 0), "BUY: lowering SL is refused (never backwards)");
   Check(ApexSLImproves(APEX_DIR_SELL, 1.1010, 1.1000, 0), "SELL: lowering SL reduces risk");
   Check(!ApexSLImproves(APEX_DIR_SELL, 1.1010, 1.1020, 0), "SELL: raising SL is refused (never backwards)");
   Check(!ApexSLImproves(APEX_DIR_BUY, 1.0990, 1.0990, 0), "unchanged SL is not an improvement");
   Check(!ApexSLImproves(APEX_DIR_BUY, 1.0990, 1.0991, 0.0005), "improvement below minimum step ignored");
   Check(!ApexSLImproves(APEX_DIR_BUY, 1.0990, 0, 0), "zero SL (removing the stop) is refused");

   CheckNear(ApexAtrTrailSL(APEX_DIR_BUY, 1.1050, 0.0010, 1.5), 1.1035, 1e-9, "BUY ATR trail");
   CheckNear(ApexAtrTrailSL(APEX_DIR_SELL, 1.0950, 0.0010, 1.5), 1.0965, 1e-9, "SELL ATR trail");
   CheckNear(ApexHybridTrailSL(APEX_DIR_BUY, 1.1035, 1.1020), 1.1020, 1e-9, "BUY hybrid uses looser stop");
   CheckNear(ApexHybridTrailSL(APEX_DIR_SELL, 1.0965, 1.0980), 1.0980, 1e-9, "SELL hybrid uses looser stop");
   CheckNear(ApexHybridTrailSL(APEX_DIR_BUY, 1.1035, 0), 1.1035, 1e-9, "hybrid falls back to ATR");

   CheckNear(ApexPartialCloseVolume(0.10, 0.10, 30, 0.01, 0.01), 0.03, 1e-9, "30% of 0.10 = 0.03");
   CheckNear(ApexPartialCloseVolume(0.01, 0.01, 30, 0.01, 0.01), 0.0, 1e-9, "min-lot position: partial skipped");
   CheckNear(ApexPartialCloseVolume(0.02, 0.02, 30, 0.01, 0.01), 0.0, 1e-9, "0.006 below min lot: partial skipped");
   CheckNear(ApexPartialCloseVolume(0.02, 0.02, 50, 0.01, 0.01), 0.01, 1e-9, "50% of 0.02 = 0.01, remainder 0.01 ok");
   CheckNear(ApexPartialCloseVolume(0.10, 0.07, 30, 0.01, 0.01), 0.03, 1e-9, "partial based on initial volume");

   Check(ApexRegimeAgainst(APEX_DIR_BUY, APEX_REGIME_TREND_DOWN), "BUY vs TREND_DOWN is adverse");
   Check(!ApexRegimeAgainst(APEX_DIR_BUY, APEX_REGIME_RANGE), "BUY vs RANGE is not adverse");
  }

//====================================================================
void TestReconcileAndRetcodes()
  {
   ulong tracked[] = {1, 2, 3};
   ulong actual[]  = {2, 3, 4};
   ulong adopt[], gone[];
   ApexReconcileDiff(tracked, actual, adopt, gone);
   Check(ArraySize(adopt) == 1 && adopt[0] == 4, "untracked broker position is adopted");
   Check(ArraySize(gone) == 1 && gone[0] == 1, "vanished position is recorded as closed");

   ulong none[];
   ArrayResize(none, 0);
   ApexReconcileDiff(tracked, tracked, adopt, gone);
   Check(ArraySize(adopt) == 0 && ArraySize(gone) == 0, "matching state = no discrepancy");
   ApexReconcileDiff(none, actual, adopt, gone);
   Check(ArraySize(adopt) == 3, "restart: all broker positions adopted");

   Check(ApexRetcodeSuccess(TRADE_RETCODE_DONE), "DONE is success");
   Check(!ApexRetcodeSuccess(TRADE_RETCODE_REJECT), "REJECT is failure");
   Check(!ApexRetcodeSuccess(TRADE_RETCODE_INVALID_STOPS), "INVALID_STOPS is failure");
   Check(ApexRetcodeRetryable(TRADE_RETCODE_REQUOTE), "REQUOTE is retryable");
   Check(ApexRetcodeRetryable(TRADE_RETCODE_PRICE_CHANGED), "PRICE_CHANGED is retryable");
   Check(!ApexRetcodeRetryable(TRADE_RETCODE_NO_MONEY), "NO_MONEY is not retried");
   Check(!ApexRetcodeRetryable(TRADE_RETCODE_INVALID_STOPS), "INVALID_STOPS is not retried");

   Check(ApexUsdExposure("EURUSD", APEX_DIR_BUY) == -1, "BUY EURUSD = short USD");
   Check(ApexUsdExposure("USDJPYm", APEX_DIR_BUY) == 1, "BUY USDJPY = long USD");
   Check(ApexUsdExposure("XAUUSDc", APEX_DIR_SELL) == 1, "SELL XAUUSD = long USD");
   Check(ApexUsdExposure("EURGBP", APEX_DIR_BUY) == 0, "EURGBP has no USD leg");
   Check(ApexIsFamilyMagic(26093004, 26093000) && !ApexIsFamilyMagic(26094000, 26093000), "magic family range");
  }

//====================================================================
void OnStart()
  {
   g_apexLogLevel = APEX_LOG_ERROR;
   TestDst();
   TestSessions();
   TestVolume();
   TestStops();
   TestStructure();
   TestRegime();
   TestScoring();
   TestDecisions();
   TestProtection();
   TestReconcileAndRetcodes();
   TestSummary("TestCore");
  }
