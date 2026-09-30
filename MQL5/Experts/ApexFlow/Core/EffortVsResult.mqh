//+------------------------------------------------------------------+
//| EffortVsResult.mqh - absorption and dominance-shift analysis      |
//|                                                                   |
//| Bars are series of CLOSED entry-timeframe bars (0 = last closed): |
//|   bar 0            : response bar (dominance shift)               |
//|   bars 1..W        : absorption window                            |
//|   bars W+1..W+B    : participation baseline                       |
//| Effort arrays come from COrderFlow::BarEfforts and are PROXIES     |
//| unless labelled otherwise. High effort + small result + rejection |
//| is only a candidate: absorption alone never means reversal.       |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_EFFORTVSRESULT_MQH
#define APEXFLOW_EFFORTVSRESULT_MQH

#include "../Types.mqh"
#include "../Utils.mqh"

struct SEffortResult
  {
   bool              ok;                // enough data
   double            participation;     // mean opposing effort in the window
   double            baseline;          // mean opposing effort in the baseline
   double            effortRatio;       // participation / baseline
   bool              elevated;          // effortRatio >= minimum
   double            actualMove;        // closing-basis move in the effort direction (price)
   double            expectedMove;      // move expected if result were proportional to effort
   double            displacementATR;   // actualMove / ATR
   double            resultRatio;       // actualMove / expectedMove
   double            effortResultRatio; // effortRatio / max(resultRatio, 0.05)
   double            rejection;         // 0..1 wick + close-location rejection
   double            spreadRatio;       // window spread / baseline spread
   bool              spreadAbnormal;    // spread-driven activity (e.g. rollover) -> penalised
   double            absorptionScore;   // 0..100
  };

struct SDominance
  {
   double            score;             // 0..100
   bool              strongClose;       // close in the trade direction, in the outer 40% of the range
   bool              engulfing;
   bool              heldExtreme;       // BUY: higher low vs window; SELL: lower high vs window
   bool              microBreak;        // close beyond the window's extreme (micro swing break)
   bool              closeBeyondBar1;   // close beyond the previous bar's extreme
   double            displacementATR;   // body in the trade direction, in ATR
   bool              activityRising;    // effort in the trade direction above window average
   bool              bookUsed;          // broker-local book was available (NATIVE, live only)
   double            bookImbalance;
  };

//--- Effort vs result for a prospective trade in `dir`:
//--- BUY looks at SELLING effort that failed to push price lower, SELL the inverse.
void ApexEffortVsResult(const int dir, const MqlRates &r[], const double &buyE[], const double &sellE[],
                        const int window, const int baseline, const double atr, const double effortMin,
                        SEffortResult &out)
  {
   ZeroMemory(out);
   int need = window + baseline + 2;
   if(ArraySize(r) < need || ArraySize(buyE) < need || ArraySize(sellE) < need || window < 1 || baseline < 1)
      return;
   out.ok = true;
   bool buy = (dir == APEX_DIR_BUY);

   double effW = 0, effB = 0, moveB = 0, sprW = 0, sprB = 0;
   for(int i = 1; i <= window; i++)
     {
      effW += buy ? sellE[i] : buyE[i];
      sprW += r[i].spread;
     }
   for(int i = window + 1; i <= window + baseline; i++)
     {
      effB  += buy ? sellE[i] : buyE[i];
      moveB += MathAbs(r[i].close - r[i].open);
      sprB  += r[i].spread;
     }
   effW /= window;
   effB /= baseline;
   moveB /= baseline;
   sprW /= window;
   sprB /= baseline;

   out.participation = effW;
   out.baseline      = effB;
   out.effortRatio   = (effB > 0) ? effW / effB : 0.0;
   out.elevated      = (out.effortRatio >= effortMin);

   if(moveB <= 0)
      moveB = (atr > 0) ? 0.1 * atr : 1e-9;
   double ref = r[window + 1].close;
   double extremeClose = r[1].close;
   for(int i = 2; i <= window; i++)
      extremeClose = buy ? MathMin(extremeClose, r[i].close) : MathMax(extremeClose, r[i].close);
   out.actualMove      = buy ? MathMax(0.0, ref - extremeClose) : MathMax(0.0, extremeClose - ref);
   out.expectedMove    = moveB * window * MathMax(out.effortRatio, 1.0);
   out.resultRatio     = (out.expectedMove > 0) ? out.actualMove / out.expectedMove : 0.0;
   out.effortResultRatio = out.effortRatio / MathMax(out.resultRatio, 0.05);
   out.displacementATR = (atr > 0) ? out.actualMove / atr : 0.0;

   double rej = 0;
   for(int i = 1; i <= window; i++)
     {
      double range = r[i].high - r[i].low;
      if(range <= 0)
         continue;
      double wick = buy ? (MathMin(r[i].open, r[i].close) - r[i].low) / range
                    : (r[i].high - MathMax(r[i].open, r[i].close)) / range;
      double loc  = buy ? (r[i].close - r[i].low) / range : (r[i].high - r[i].close) / range;
      rej = MathMax(rej, 0.5 * wick + 0.5 * loc);
     }
   out.rejection = ApexClamp(rej, 0, 1);

   out.spreadRatio    = (sprB > 0) ? sprW / sprB : 1.0;
   out.spreadAbnormal = (out.spreadRatio > 2.0);

   double e = ApexClamp((out.effortRatio - 1.0) / 1.5, 0, 1);
   double weakResult = 1.0 - ApexClamp(out.resultRatio, 0, 1);
   double score = 100.0 * (0.40 * e + 0.35 * weakResult + 0.25 * out.rejection);
   if(out.spreadAbnormal)
      score *= 0.7;
   if(!out.elevated)
      score = MathMin(score, 40.0); // no elevated participation -> no absorption
   out.absorptionScore = ApexClamp(score, 0, 100);
  }

//--- Evidence that control is shifting toward `dir` on the response bar (bar 0).
void ApexDominanceShift(const int dir, const MqlRates &r[], const double &buyE[], const double &sellE[],
                        const int window, const double atr, const bool bookAvailable,
                        const double bookImbalance, SDominance &d)
  {
   ZeroMemory(d);
   if(ArraySize(r) < window + 2 || ArraySize(buyE) < window + 1 || ArraySize(sellE) < window + 1 || window < 1)
      return;
   bool buy = (dir == APEX_DIR_BUY);
   MqlRates b0 = r[0];
   MqlRates b1 = r[1];
   double range0 = MathMax(b0.high - b0.low, 1e-12);
   double body0 = MathAbs(b0.close - b0.open);
   double body1 = MathAbs(b1.close - b1.open);

   double winLow = r[1].low, winHigh = r[1].high, effWin = 0;
   for(int i = 1; i <= window; i++)
     {
      winLow  = MathMin(winLow, r[i].low);
      winHigh = MathMax(winHigh, r[i].high);
      effWin += buy ? buyE[i] : sellE[i];
     }
   effWin /= window;

   double s = 0;
   if(buy)
     {
      d.strongClose     = (b0.close > b0.open && (b0.close - b0.low) / range0 >= 0.6);
      d.engulfing       = (b0.close > b0.open && b0.close >= MathMax(b1.open, b1.close) &&
                           b0.open <= MathMin(b1.open, b1.close) && body0 >= body1);
      d.heldExtreme     = (b0.low > winLow);
      d.microBreak      = (b0.close > winHigh);
      d.closeBeyondBar1 = (b0.close > b1.high);
      d.displacementATR = (atr > 0) ? (b0.close - b0.open) / atr : 0;
      d.activityRising  = (buyE[0] > effWin);
      d.bookUsed        = bookAvailable;
      d.bookImbalance   = bookImbalance;
      if(bookAvailable && bookImbalance > 0.1)
         s += 0.10;
     }
   else
     {
      d.strongClose     = (b0.close < b0.open && (b0.high - b0.close) / range0 >= 0.6);
      d.engulfing       = (b0.close < b0.open && b0.close <= MathMin(b1.open, b1.close) &&
                           b0.open >= MathMax(b1.open, b1.close) && body0 >= body1);
      d.heldExtreme     = (b0.high < winHigh);
      d.microBreak      = (b0.close < winLow);
      d.closeBeyondBar1 = (b0.close < b1.low);
      d.displacementATR = (atr > 0) ? (b0.open - b0.close) / atr : 0;
      d.activityRising  = (sellE[0] > effWin);
      d.bookUsed        = bookAvailable;
      d.bookImbalance   = bookImbalance;
      if(bookAvailable && bookImbalance < -0.1)
         s += 0.10;
     }
   if(d.strongClose)
      s += 0.15;
   if(d.engulfing)
      s += 0.15;
   if(d.heldExtreme)
      s += 0.15;
   if(d.microBreak)
      s += 0.25;
   else
      if(d.closeBeyondBar1)
         s += 0.10;
   s += 0.15 * ApexClamp(d.displacementATR / 0.5, 0, 1);
   if(d.activityRising)
      s += 0.15;
   d.score = 100.0 * ApexClamp(s, 0, 1);
  }

//--- Structure confirmation (0..1) and contradiction check.
double ApexARStructureScore(const int dir, const SDominance &d, const SStructureState &entrySt,
                            const SStructureState &confirmSt, bool &contradictory)
  {
   bool buy = (dir == APEX_DIR_BUY);
   contradictory = buy ? (confirmSt.bias == APEX_BIAS_BEARISH) : (confirmSt.bias == APEX_BIAS_BULLISH);
   double s = 0;
   if(d.microBreak)
      s += 0.5;
   else
      if(d.closeBeyondBar1 && d.heldExtreme)
         s += 0.3;
   if(buy ? (entrySt.bosUp || entrySt.bias == APEX_BIAS_BULLISH) : (entrySt.bosDown || entrySt.bias == APEX_BIAS_BEARISH))
      s += 0.3;
   ENUM_APEX_BIAS want = buy ? APEX_BIAS_BULLISH : APEX_BIAS_BEARISH;
   if(confirmSt.bias == want)
      s += 0.2;
   else
      if(!contradictory)
         s += 0.1;
   return ApexClamp(s, 0, 1);
  }

#endif // APEXFLOW_EFFORTVSRESULT_MQH
