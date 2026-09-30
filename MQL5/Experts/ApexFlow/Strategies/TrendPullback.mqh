//+------------------------------------------------------------------+
//| TrendPullback.mqh - continuation entry after a pullback to the    |
//| fast EMA inside an aligned entry-timeframe trend.                 |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_TRENDPULLBACK_MQH
#define APEXFLOW_TRENDPULLBACK_MQH

#include "StrategyBase.mqh"

class CTrendPullback : public CStrategyBase
  {
public:
   virtual ENUM_APEX_STRATEGY Id(void) const { return APEX_STRAT_TREND_PULLBACK; }

   virtual bool      Evaluate(const int dir, const CTfData &d, const SStructureState &st,
                              const SLiquidityState &liq, const SApexConfig &c, SSetup &out) const
     {
      Begin(dir, out);
      if(!d.ready || ArraySize(d.rates) < 6)
         return Fail(out, "data not ready");
      double atr = d.atr[0];
      if(atr <= 0)
         return Fail(out, "atr unavailable");
      MqlRates b = d.rates[0];
      double f = d.fast[0];
      double s = d.slow[0];
      double body = MathAbs(b.close - b.open) / BarRange(b);

      if(dir == APEX_DIR_BUY)
        {
         if(!(f > s))
            return Fail(out, "entry EMAs not bullish");
         bool touched = false;
         double extreme = b.low;
         for(int i = 0; i < 3; i++)
           {
            if(d.rates[i].low <= d.fast[i] + 0.1 * atr)
               touched = true;
            extreme = MathMin(extreme, d.rates[i].low);
           }
         if(!touched)
            return Fail(out, "no pullback to fast EMA");
         if(extreme < s - 0.5 * atr)
            return Fail(out, "pullback too deep");
         if(!(b.close > b.open && b.close > f))
            return Fail(out, "no bullish confirmation close");
         double stopBase = d.rates[0].low;
         for(int i = 1; i < 5; i++)
            stopBase = MathMin(stopBase, d.rates[i].low);
         if(st.valid && st.lastLow < b.close && (b.close - st.lastLow) <= c.maxStopATR * atr)
            stopBase = MathMin(stopBase, st.lastLow);
         out.structuralStop = stopBase - c.stopATRBuffer * atr;
        }
      else
        {
         if(!(f < s))
            return Fail(out, "entry EMAs not bearish");
         bool touched = false;
         double extreme = b.high;
         for(int i = 0; i < 3; i++)
           {
            if(d.rates[i].high >= d.fast[i] - 0.1 * atr)
               touched = true;
            extreme = MathMax(extreme, d.rates[i].high);
           }
         if(!touched)
            return Fail(out, "no pullback to fast EMA");
         if(extreme > s + 0.5 * atr)
            return Fail(out, "pullback too deep");
         if(!(b.close < b.open && b.close < f))
            return Fail(out, "no bearish confirmation close");
         double stopBase = d.rates[0].high;
         for(int i = 1; i < 5; i++)
            stopBase = MathMax(stopBase, d.rates[i].high);
         if(st.valid && st.lastHigh > b.close && (st.lastHigh - b.close) <= c.maxStopATR * atr)
            stopBase = MathMax(stopBase, st.lastHigh);
         out.structuralStop = stopBase + c.stopATRBuffer * atr;
        }
      out.quality = ApexClamp(0.5 + 0.5 * body, 0.0, 1.0);
      out.valid   = true;
      out.note    = "pullback to fast EMA with confirmation close";
      return true;
     }
  };

#endif // APEXFLOW_TRENDPULLBACK_MQH
