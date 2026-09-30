//+------------------------------------------------------------------+
//| StrategyBase.mqh - common interface for strategy modules          |
//|                                                                   |
//| A strategy only answers "is there a valid setup in direction X,   |
//| and where would it be invalidated?". It never sizes, never places |
//| orders and never decides alone: SignalEngine -> RiskEngine ->     |
//| OrderManager is the only path to an order.                        |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_STRATEGYBASE_MQH
#define APEXFLOW_STRATEGYBASE_MQH

#include "../Config.mqh"
#include "../Indicators/IndicatorManager.mqh"

class CStrategyBase
  {
protected:
   void              Begin(const int dir, SSetup &out) const
     {
      out.valid          = false;
      out.dir            = dir;
      out.strategy       = Id();
      out.structuralStop = 0.0;
      out.quality        = 0.0;
      out.note           = "";
      out.score          = -1.0;             // base strategies use the shared score model
      out.target         = 0.0;
      out.gateReject     = APEX_REJECT_NONE;
     }

   bool              Fail(SSetup &out, const string note) const
     {
      out.valid = false;
      out.note  = note;
      return false;
     }

   double            BarRange(const MqlRates &b) const
     {
      return MathMax(b.high - b.low, _Point);
     }

public:
   virtual ENUM_APEX_STRATEGY Id(void) const { return APEX_STRAT_NONE; }

   virtual bool      Evaluate(const int dir, const CTfData &d, const SStructureState &st,
                              const SLiquidityState &liq, const SApexConfig &c, SSetup &out) const
     {
      Begin(dir, out);
      return Fail(out, "base strategy");
     }
  };

#endif // APEXFLOW_STRATEGYBASE_MQH
