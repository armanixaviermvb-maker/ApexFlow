//+------------------------------------------------------------------+
//| Reversal.mqh - liquidity sweep and rejection with momentum turn.  |
//| A sweep alone is never enough: RSI must be stretched and turning, |
//| and the candle must reject the swept level.                       |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_REVERSAL_MQH
#define APEXFLOW_REVERSAL_MQH

#include "StrategyBase.mqh"

class CReversal : public CStrategyBase
  {
public:
   virtual ENUM_APEX_STRATEGY Id(void) const { return APEX_STRAT_REVERSAL; }

   virtual bool      Evaluate(const int dir, const CTfData &d, const SStructureState &st,
                              const SLiquidityState &liq, const SApexConfig &c, SSetup &out) const
     {
      Begin(dir, out);
      if(!d.ready || ArraySize(d.rates) < 3 || ArraySize(d.rsi) < 2)
         return Fail(out, "data not ready");
      double atr = d.atr[0];
      if(atr <= 0)
         return Fail(out, "atr unavailable");
      MqlRates b = d.rates[0];
      double range = BarRange(b);

      if(dir == APEX_DIR_BUY)
        {
         if(!liq.sweptLow)
            return Fail(out, "no liquidity sweep below support");
         if(!(d.rsi[1] < 40 || d.rsi[0] < 45))
            return Fail(out, "RSI not stretched");
         if(!(d.rsi[0] > d.rsi[1]))
            return Fail(out, "RSI not turning up");
         if(!(b.close > b.open))
            return Fail(out, "no bullish rejection close");
         double wick = MathMin(b.open, b.close) - b.low;
         if(wick < 0.4 * range)
            return Fail(out, "rejection wick too small");
         out.structuralStop = b.low - c.stopATRBuffer * atr;
         out.quality = ApexClamp(wick / range, 0.0, 1.0);
        }
      else
        {
         if(!liq.sweptHigh)
            return Fail(out, "no liquidity sweep above resistance");
         if(!(d.rsi[1] > 60 || d.rsi[0] > 55))
            return Fail(out, "RSI not stretched");
         if(!(d.rsi[0] < d.rsi[1]))
            return Fail(out, "RSI not turning down");
         if(!(b.close < b.open))
            return Fail(out, "no bearish rejection close");
         double wick = b.high - MathMax(b.open, b.close);
         if(wick < 0.4 * range)
            return Fail(out, "rejection wick too small");
         out.structuralStop = b.high + c.stopATRBuffer * atr;
         out.quality = ApexClamp(wick / range, 0.0, 1.0);
        }
      out.valid = true;
      out.note  = "liquidity sweep with rejection and momentum turn";
      return true;
     }
  };

#endif // APEXFLOW_REVERSAL_MQH
