//+------------------------------------------------------------------+
//| StructureEngine.mqh - swings, HH/HL/LH/LL, break of structure,    |
//| structure transitions and liquidity reference levels.             |
//|                                                                   |
//| Input arrays are series of CLOSED bars (index 0 = last closed).   |
//| A swing at index i needs `strength` closed bars on both sides, so |
//| the most recent swing can be at index `strength` at the earliest: |
//| swings are only confirmed after they happened (no repainting).    |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_STRUCTUREENGINE_MQH
#define APEXFLOW_STRUCTUREENGINE_MQH

#include "../Types.mqh"
#include "../Utils.mqh"

//--- Collect up to `maxSwings` swing highs (highs=true) or lows, newest first.
int ApexFindSwings(const MqlRates &rates[], const int count, const int strength,
                   const bool highs, SSwingPoint &out[], const int maxSwings)
  {
   ArrayResize(out, 0);
   int n = MathMin(count, ArraySize(rates));
   int found = 0;
   for(int i = strength; i < n - strength && found < maxSwings; i++)
     {
      double p = highs ? rates[i].high : rates[i].low;
      bool isSwing = true;
      for(int k = 1; k <= strength && isSwing; k++)
        {
         double newer = highs ? rates[i - k].high : rates[i - k].low;
         double older = highs ? rates[i + k].high : rates[i + k].low;
         if(highs)
           {
            // Equal highs on the newer side belong to the newer bar.
            if(newer >= p || older > p)
               isSwing = false;
           }
         else
           {
            if(newer <= p || older < p)
               isSwing = false;
           }
        }
      if(!isSwing)
         continue;
      ArrayResize(out, found + 1);
      out[found].price = p;
      out[found].time  = rates[i].time;
      out[found].index = i;
      found++;
     }
   return found;
  }

//--- Full structure analysis on one timeframe.
void ApexAnalyzeStructure(const MqlRates &rates[], const int count, const int strength,
                          const int rangeBars, SStructureState &s)
  {
   ZeroMemory(s);
   s.bias = APEX_BIAS_NONE;
   int n = MathMin(count, ArraySize(rates));
   if(n < rangeBars + 2 || n < strength * 2 + 3)
      return;

   // Range of bars 1..rangeBars (excludes the last closed bar, used for breakouts).
   s.rangeHigh = rates[1].high;
   s.rangeLow  = rates[1].low;
   for(int i = 2; i <= rangeBars && i < n; i++)
     {
      s.rangeHigh = MathMax(s.rangeHigh, rates[i].high);
      s.rangeLow  = MathMin(s.rangeLow, rates[i].low);
     }

   SSwingPoint sh[], sl[];
   int nh = ApexFindSwings(rates, n, strength, true, sh, 4);
   int nl = ApexFindSwings(rates, n, strength, false, sl, 4);
   if(nh < 2 || nl < 2)
      return;

   s.valid        = true;
   s.lastHigh     = sh[0].price;
   s.prevHigh     = sh[1].price;
   s.lastLow      = sl[0].price;
   s.prevLow      = sl[1].price;
   s.lastHighTime = sh[0].time;
   s.lastLowTime  = sl[0].time;
   s.higherHigh   = (sh[0].price > sh[1].price);
   s.lowerHigh    = (sh[0].price < sh[1].price);
   s.higherLow    = (sl[0].price > sl[1].price);
   s.lowerLow     = (sl[0].price < sl[1].price);

   double close = rates[0].close;
   s.bosUp   = (close > s.lastHigh);
   s.bosDown = (close < s.lastLow);

   if(s.higherHigh && s.higherLow)
      s.bias = APEX_BIAS_BULLISH;
   else
      if(s.lowerHigh && s.lowerLow)
         s.bias = APEX_BIAS_BEARISH;
      else
         s.bias = APEX_BIAS_RANGE;

   // A break against the prevailing structure marks a transition.
   if(s.bias == APEX_BIAS_BULLISH && s.bosDown)
      s.bias = APEX_BIAS_TRANSITION;
   else
      if(s.bias == APEX_BIAS_BEARISH && s.bosUp)
         s.bias = APEX_BIAS_TRANSITION;
  }

//--- Liquidity context around the last closed bar (entry timeframe).
//--- Levels are contextual: a sweep is information, not a reversal signal by itself.
void ApexAnalyzeLiquidity(const MqlRates &rates[], const int count, const SStructureState &st,
                          const double pdh, const double pdl, const datetime sessionStartServer,
                          const double atr, SLiquidityState &l)
  {
   ZeroMemory(l);
   l.pdh = pdh;
   l.pdl = pdl;
   l.roomUpAtr   = 99.0;
   l.roomDownAtr = 99.0;
   int n = MathMin(count, ArraySize(rates));
   if(n < 3 || atr <= 0)
      return;

   // Session range from bars before the last closed bar.
   bool haveSession = false;
   for(int i = 1; i < n; i++)
     {
      if(rates[i].time < sessionStartServer)
         break;
      if(!haveSession)
        {
         l.sessionHigh = rates[i].high;
         l.sessionLow  = rates[i].low;
         haveSession   = true;
        }
      else
        {
         l.sessionHigh = MathMax(l.sessionHigh, rates[i].high);
         l.sessionLow  = MathMin(l.sessionLow, rates[i].low);
        }
     }

   double lows[3], highs[3];
   lows[0]  = pdl;
   lows[1]  = st.valid ? st.lastLow : 0.0;
   lows[2]  = haveSession ? l.sessionLow : 0.0;
   highs[0] = pdh;
   highs[1] = st.valid ? st.lastHigh : 0.0;
   highs[2] = haveSession ? l.sessionHigh : 0.0;

   MqlRates b = rates[0];
   double nearestSupport = 0.0, nearestResistance = 0.0;
   for(int k = 0; k < 3; k++)
     {
      double lo = lows[k];
      if(lo > 0)
        {
         if(b.low < lo && b.close > lo && !l.sweptLow)
           {
            l.sweptLow = true;
            l.sweptLowLevel = lo;
           }
         if(lo <= b.close && (nearestSupport == 0.0 || lo > nearestSupport))
            nearestSupport = lo;
        }
      double hi = highs[k];
      if(hi > 0)
        {
         if(b.high > hi && b.close < hi && !l.sweptHigh)
           {
            l.sweptHigh = true;
            l.sweptHighLevel = hi;
           }
         if(hi >= b.close && (nearestResistance == 0.0 || hi < nearestResistance))
            nearestResistance = hi;
        }
     }
   if(nearestSupport > 0)
     {
      l.roomDownAtr = (b.close - nearestSupport) / atr;
      l.nearSupport = (l.roomDownAtr <= 0.5);
     }
   if(nearestResistance > 0)
     {
      l.roomUpAtr = (nearestResistance - b.close) / atr;
      l.nearResistance = (l.roomUpAtr <= 0.5);
     }
  }

#endif // APEXFLOW_STRUCTUREENGINE_MQH
