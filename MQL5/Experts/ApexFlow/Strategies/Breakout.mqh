//+------------------------------------------------------------------+
//| Breakout.mqh - decisive close beyond the recent range with        |
//| expanding volatility; rejects over-extended breaks.               |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_BREAKOUT_MQH
#define APEXFLOW_BREAKOUT_MQH

#include "StrategyBase.mqh"

class CBreakout : public CStrategyBase
  {
public:
   virtual ENUM_APEX_STRATEGY Id(void) const { return APEX_STRAT_BREAKOUT; }

   virtual bool      Evaluate(const int dir, const CTfData &d, const SStructureState &st,
                              const SLiquidityState &liq, const SApexConfig &c, SSetup &out) const
     {
      Begin(dir, out);
      if(!d.ready || ArraySize(d.rates) < 6)
         return Fail(out, "data not ready");
      if(st.rangeHigh <= 0 || st.rangeLow <= 0)
         return Fail(out, "range unavailable");
      double atr = d.atr[0];
      if(atr <= 0)
         return Fail(out, "atr unavailable");
      MqlRates b = d.rates[0];
      double range = BarRange(b);
      double body  = MathAbs(b.close - b.open);
      if(body < 0.5 * atr)
         return Fail(out, "breakout candle too small");
      if(!ApexATRExpanding(d.atr, 5))
         return Fail(out, "volatility not expanding");

      if(dir == APEX_DIR_BUY)
        {
         if(!(b.close > st.rangeHigh))
            return Fail(out, "no close above range high");
         double closeLoc = (b.close - b.low) / range;
         if(closeLoc < 0.7)
            return Fail(out, "weak close location");
         if(b.close - st.rangeHigh > 1.0 * atr)
            return Fail(out, "breakout over-extended");
         out.structuralStop = MathMin(b.low, st.rangeHigh) - c.stopATRBuffer * atr;
         out.quality = ApexClamp(0.5 + 0.5 * closeLoc, 0.0, 1.0);
        }
      else
        {
         if(!(b.close < st.rangeLow))
            return Fail(out, "no close below range low");
         double closeLoc = (b.high - b.close) / range;
         if(closeLoc < 0.7)
            return Fail(out, "weak close location");
         if(st.rangeLow - b.close > 1.0 * atr)
            return Fail(out, "breakout over-extended");
         out.structuralStop = MathMax(b.high, st.rangeLow) + c.stopATRBuffer * atr;
         out.quality = ApexClamp(0.5 + 0.5 * closeLoc, 0.0, 1.0);
        }
      out.valid = true;
      out.note  = "range breakout with expanding ATR";
      return true;
     }
  };

#endif // APEXFLOW_BREAKOUT_MQH
