//+------------------------------------------------------------------+
//| SignalEngine.mqh - independent BUY and SELL scoring, regime-aware |
//| strategy selection and the BUY / SELL / NO_TRADE decision.        |
//|                                                                   |
//| NO_TRADE is the default outcome. A direction is chosen only when: |
//|   - the regime allows that strategy in that direction,            |
//|   - its score reaches the (regime-adjusted) threshold,            |
//|   - it beats the opposite score by the minimum gap,               |
//|   - the strategy module confirms a concrete setup.                |
//| The result is only a proposal: RiskEngine must still approve it.  |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_SIGNALENGINE_MQH
#define APEXFLOW_SIGNALENGINE_MQH

#include "../Config.mqh"
#include "../Utils.mqh"
#include "../Indicators/IndicatorManager.mqh"
#include "../Strategies/TrendPullback.mqh"
#include "../Strategies/Breakout.mqh"
#include "../Strategies/Reversal.mqh"

struct SScoreInputs
  {
   int               vote;            // regime vote -5..+5
   int               ctxEmaAlign;     // context EMA alignment -1..+1
   ENUM_APEX_BIAS    confirmBias;
   ENUM_APEX_BIAS    entryBias;
   bool              confirmBosUp;
   bool              confirmBosDown;
   double            rsiEntry;
   double            closeEntry;
   double            emaFastEntry;
   bool              sweptLow;
   bool              sweptHigh;
   bool              nearSupport;
   bool              nearResistance;
   double            roomUpAtr;
   double            roomDownAtr;
   double            atrPercentile;
   ENUM_APEX_SESSION session;
  };

//====================================================================
// SCORE COMPONENTS (each 0..1, then multiplied by its weight)
//====================================================================
double ApexBiasScore(const ENUM_APEX_BIAS bias, const int dir)
  {
   if(bias == APEX_BIAS_BULLISH)
      return (dir == APEX_DIR_BUY) ? 1.0 : 0.0;
   if(bias == APEX_BIAS_BEARISH)
      return (dir == APEX_DIR_SELL) ? 1.0 : 0.0;
   if(bias == APEX_BIAS_TRANSITION)
      return 0.5;
   if(bias == APEX_BIAS_RANGE)
      return 0.4;
   return 0.3;
  }

//--- RSI quality for a direction: healthy momentum scores high, exhaustion low.
double ApexRsiScore(const double rsi, const int dir)
  {
   double r = (dir == APEX_DIR_BUY) ? rsi : 100.0 - rsi;
   if(r >= 50 && r <= 70)
      return 1.0;
   if(r > 70 && r <= 80)
      return 0.5;
   if(r >= 40 && r < 50)
      return 0.5;
   return 0.1;
  }

double ApexSessionScore(const ENUM_APEX_SESSION s)
  {
   switch(s)
     {
      case APEX_SESSION_OVERLAP:  return 1.0;
      case APEX_SESSION_LONDON:   return 0.8;
      case APEX_SESSION_NEW_YORK: return 0.8;
      case APEX_SESSION_ASIA:     return 0.4;
      default:                    break;
     }
   return 0.0;
  }

double ApexVolatilityScore(const double pct, const double pctMin, const double pctMax)
  {
   if(pct < pctMin || pct > pctMax)
      return 0.0;
   if(pct >= pctMin + 10 && pct <= pctMax - 10)
      return 1.0;
   return 0.6;
  }

void ApexScoreDirection(const SScoreInputs &in, const SApexConfig &c, const int dir, SScoreBreakdown &s)
  {
   bool buy = (dir == APEX_DIR_BUY);

   double trend = buy ? (in.vote + 5) / 10.0 : (5 - in.vote) / 10.0;

   double structure = 0.7 * ApexBiasScore(in.confirmBias, dir) + 0.3 * ApexBiasScore(in.entryBias, dir);
   if((buy && in.confirmBosUp) || (!buy && in.confirmBosDown))
      structure += 0.2;

   double emaSide = buy ? (in.closeEntry > in.emaFastEntry ? 1.0 : 0.0)
                    : (in.closeEntry < in.emaFastEntry ? 1.0 : 0.0);
   double momentum = 0.6 * ApexRsiScore(in.rsiEntry, dir) + 0.4 * emaSide;

   double liquidity = 0.5;
   if(buy)
     {
      if(in.sweptLow)
         liquidity = 1.0;
      else
         if(in.nearSupport)
            liquidity = 0.8;
         else
            if(in.nearResistance)
               liquidity = 0.2;
      if(in.roomUpAtr < 1.0)
         liquidity = MathMin(liquidity, 0.3);
     }
   else
     {
      if(in.sweptHigh)
         liquidity = 1.0;
      else
         if(in.nearResistance)
            liquidity = 0.8;
         else
            if(in.nearSupport)
               liquidity = 0.2;
      if(in.roomDownAtr < 1.0)
         liquidity = MathMin(liquidity, 0.3);
     }

   double volatility = ApexVolatilityScore(in.atrPercentile, c.atrPctMin, c.atrPctMax);
   double session    = ApexSessionScore(in.session);

   int ctx  = in.ctxEmaAlign * dir;
   int conf = 0;
   if(in.confirmBias == APEX_BIAS_BULLISH)
      conf = dir;
   else
      if(in.confirmBias == APEX_BIAS_BEARISH)
         conf = -dir;
   double confirmation;
   if(ctx < 0 || conf < 0)
      confirmation = 0.0;
   else
     {
      int agree = (ctx > 0 ? 1 : 0) + (conf > 0 ? 1 : 0);
      confirmation = (agree == 2) ? 1.0 : (agree == 1 ? 0.6 : 0.3);
     }

   s.trend        = ApexClamp(trend, 0, 1) * c.wTrend;
   s.structure    = ApexClamp(structure, 0, 1) * c.wStructure;
   s.momentum     = ApexClamp(momentum, 0, 1) * c.wMomentum;
   s.liquidity    = ApexClamp(liquidity, 0, 1) * c.wLiquidity;
   s.volatility   = ApexClamp(volatility, 0, 1) * c.wVolatility;
   s.session      = ApexClamp(session, 0, 1) * c.wSession;
   s.confirmation = ApexClamp(confirmation, 0, 1) * c.wConfirmation;
   s.total        = s.trend + s.structure + s.momentum + s.liquidity +
                    s.volatility + s.session + s.confirmation;
  }

void ApexComputeScores(const SScoreInputs &in, const SApexConfig &c, SScoreBreakdown &buy, SScoreBreakdown &sell)
  {
   ApexScoreDirection(in, c, APEX_DIR_BUY, buy);
   ApexScoreDirection(in, c, APEX_DIR_SELL, sell);
  }

//====================================================================
// REGIME -> STRATEGY PERMISSIONS
//====================================================================
bool ApexStrategyEnabled(const SApexConfig &c, const ENUM_APEX_STRATEGY s)
  {
   if(s == APEX_STRAT_TREND_PULLBACK)
      return c.enableTrendPullback;
   if(s == APEX_STRAT_BREAKOUT)
      return c.enableBreakout;
   if(s == APEX_STRAT_REVERSAL)
      return c.enableReversal;
   return false;
  }

//--- May `strategy` trade in `dir` under `regime`? `extraScore` raises the
//--- threshold in harder regimes (stricter filters, never looser).
bool ApexStrategyAllowed(const SApexConfig &c, const ENUM_APEX_REGIME regime, const int vote,
                         const int dir, const ENUM_APEX_STRATEGY s, int &extraScore)
  {
   extraScore = 0;
   if(!ApexStrategyEnabled(c, s))
      return false;
   bool voteMatches = ((vote > 0 && dir == APEX_DIR_BUY) || (vote < 0 && dir == APEX_DIR_SELL));
   switch(regime)
     {
      case APEX_REGIME_TREND_UP:
         return (dir == APEX_DIR_BUY && (s == APEX_STRAT_TREND_PULLBACK || s == APEX_STRAT_BREAKOUT));
      case APEX_REGIME_TREND_DOWN:
         return (dir == APEX_DIR_SELL && (s == APEX_STRAT_TREND_PULLBACK || s == APEX_STRAT_BREAKOUT));
      case APEX_REGIME_RANGE:
         return (s == APEX_STRAT_REVERSAL || s == APEX_STRAT_BREAKOUT);
      case APEX_REGIME_HIGH_VOL:
         extraScore = 10;
         return (s == APEX_STRAT_TREND_PULLBACK && voteMatches);
      case APEX_REGIME_LOW_VOL:
         extraScore = 5;
         return (s == APEX_STRAT_BREAKOUT || s == APEX_STRAT_REVERSAL);
      case APEX_REGIME_TRANSITION:
         extraScore = 10;
         return (c.allowTransitionEntries && s == APEX_STRAT_TREND_PULLBACK && voteMatches);
      default:
         break;
     }
   return false;
  }

//====================================================================
// DECISION (pure; used by the engine and by tests)
//====================================================================
void ApexDecide(const SApexConfig &c, const ENUM_APEX_REGIME regime, const int vote,
                const SScoreBreakdown &buy, const SScoreBreakdown &sell,
                const SSetup &setups[], const int setupCount, SSignalResult &r)
  {
   r.decision       = APEX_DECISION_NO_TRADE;
   r.dir            = APEX_DIR_NONE;
   r.strategy       = APEX_STRAT_NONE;
   r.regime         = regime;
   r.buy            = buy;
   r.sell           = sell;
   r.structuralStop = 0.0;
   r.requiredScore  = c.minSignalScore;
   r.reject         = APEX_REJECT_NONE;
   r.detail         = "";

   bool anyAllowed = false;
   int  stageReached = 0;  // 1 score low, 2 gap small, 3 no setup
   string stageDetail = "";
   int bestIdx[2];
   double bestScore[2];
   double bestReq[2];
   bestIdx[0] = -1;
   bestIdx[1] = -1;
   bestScore[0] = -1;
   bestScore[1] = -1;
   bestReq[0] = 0;
   bestReq[1] = 0;

   for(int side = 0; side < 2; side++)
     {
      int dir = (side == 0) ? APEX_DIR_BUY : APEX_DIR_SELL;
      double score = (side == 0) ? buy.total : sell.total;
      double opp   = (side == 0) ? sell.total : buy.total;
      for(int si = 1; si < APEX_STRAT_COUNT; si++)
        {
         ENUM_APEX_STRATEGY s = (ENUM_APEX_STRATEGY)si;
         int extra = 0;
         if(!ApexStrategyAllowed(c, regime, vote, dir, s, extra))
            continue;
         anyAllowed = true;
         double req = c.minSignalScore + extra;
         if(s == APEX_STRAT_REVERSAL)
            req = MathMax(req, (double)c.reversalMinScore + extra);
         req = MathMin(req, 100.0);

         if(score < req)
           {
            if(stageReached < 1)
              {
               stageReached = 1;
               stageDetail = StringFormat("%s %s score %.0f < %.0f", ApexDirToString(dir),
                                          ApexStrategyToString(s), score, req);
              }
            continue;
           }
         if(score - opp < c.minScoreGap)
           {
            if(stageReached < 2)
              {
               stageReached = 2;
               stageDetail = StringFormat("%s score %.0f vs %.0f gap < %d", ApexDirToString(dir),
                                          score, opp, c.minScoreGap);
              }
            continue;
           }
         int idx = -1;
         for(int k = 0; k < setupCount; k++)
            if(setups[k].dir == dir && setups[k].strategy == s)
              {
               idx = k;
               break;
              }
         if(idx < 0 || !setups[idx].valid)
           {
            if(stageReached < 3)
              {
               stageReached = 3;
               stageDetail = StringFormat("%s %s: %s", ApexDirToString(dir), ApexStrategyToString(s),
                                          (idx < 0 ? "not evaluated" : setups[idx].note));
              }
            continue;
           }
         double rank = score + setups[idx].quality; // quality breaks ties between strategies
         if(rank > bestScore[side])
           {
            bestScore[side] = rank;
            bestIdx[side]   = idx;
            bestReq[side]   = req;
           }
        }
     }

   if(!anyAllowed)
     {
      if(regime == APEX_REGIME_UNKNOWN)
         r.reject = APEX_REJECT_DATA_NOT_READY;
      else
         if(regime == APEX_REGIME_TRANSITION)
            r.reject = APEX_REJECT_REGIME_TRANSITION;
         else
            r.reject = APEX_REJECT_REGIME_BLOCKED;
      r.detail = "regime " + ApexRegimeToString(regime) + " allows no enabled strategy";
      return;
     }
   if(bestIdx[0] >= 0 && bestIdx[1] >= 0)
     {
      r.reject = APEX_REJECT_SCORE_GAP;
      r.detail = "conflicting BUY and SELL setups";
      return;
     }
   int side = (bestIdx[0] >= 0) ? 0 : ((bestIdx[1] >= 0) ? 1 : -1);
   if(side < 0)
     {
      if(stageReached == 1)
         r.reject = APEX_REJECT_SCORE_BELOW_THRESHOLD;
      else
         if(stageReached == 2)
            r.reject = APEX_REJECT_SCORE_GAP;
         else
            r.reject = APEX_REJECT_NO_SETUP;
      r.detail = stageDetail;
      return;
     }
   int k = bestIdx[side];
   r.dir            = setups[k].dir;
   r.decision       = (r.dir == APEX_DIR_BUY) ? APEX_DECISION_BUY : APEX_DECISION_SELL;
   r.strategy       = setups[k].strategy;
   r.structuralStop = setups[k].structuralStop;
   r.requiredScore  = bestReq[side];
   r.detail         = setups[k].note;
  }

//====================================================================
// ENGINE
//====================================================================
class CSignalEngine
  {
private:
   CTrendPullback    m_pullback;
   CBreakout         m_breakout;
   CReversal         m_reversal;

public:
   void              Evaluate(const SApexConfig &c, CIndicatorManager &ind,
                              const SStructureState &confirmSt, const SStructureState &entrySt,
                              const SLiquidityState &liq, const SRegimeState &reg,
                              const SSessionState &ss, SSignalResult &r)
     {
      ZeroMemory(r);
      r.time    = TimeCurrent();
      r.session = ss.session;
      r.regime  = reg.regime;
      r.atr     = ind.Atr(APEX_TF_ENTRY);

      if(!ind.Ready())
        {
         r.decision = APEX_DECISION_NO_TRADE;
         r.reject   = APEX_REJECT_DATA_NOT_READY;
         r.detail   = "indicator data not ready";
         return;
        }

      SScoreInputs in;
      ZeroMemory(in);
      in.vote           = reg.vote;
      in.ctxEmaAlign    = reg.emaAlign;
      in.confirmBias    = confirmSt.bias;
      in.entryBias      = entrySt.bias;
      in.confirmBosUp   = confirmSt.bosUp;
      in.confirmBosDown = confirmSt.bosDown;
      in.rsiEntry       = ind.data[APEX_TF_ENTRY].rsi[0];
      in.closeEntry     = ind.data[APEX_TF_ENTRY].rates[0].close;
      in.emaFastEntry   = ind.data[APEX_TF_ENTRY].fast[0];
      in.sweptLow       = liq.sweptLow;
      in.sweptHigh      = liq.sweptHigh;
      in.nearSupport    = liq.nearSupport;
      in.nearResistance = liq.nearResistance;
      in.roomUpAtr      = liq.roomUpAtr;
      in.roomDownAtr    = liq.roomDownAtr;
      in.atrPercentile  = ind.AtrPercentile(APEX_TF_ENTRY, c.atrPctLookback);
      in.session        = ss.session;

      SScoreBreakdown buy, sell;
      ZeroMemory(buy);
      ZeroMemory(sell);
      ApexComputeScores(in, c, buy, sell);

      // Evaluate every enabled strategy in both directions, independently.
      SSetup setups[6];
      int n = 0;
      for(int side = 0; side < 2; side++)
        {
         int dir = (side == 0) ? APEX_DIR_BUY : APEX_DIR_SELL;
         if(c.enableTrendPullback)
            m_pullback.Evaluate(dir, ind.data[APEX_TF_ENTRY], entrySt, liq, c, setups[n++]);
         if(c.enableBreakout)
            m_breakout.Evaluate(dir, ind.data[APEX_TF_ENTRY], entrySt, liq, c, setups[n++]);
         if(c.enableReversal)
            m_reversal.Evaluate(dir, ind.data[APEX_TF_ENTRY], entrySt, liq, c, setups[n++]);
        }

      ApexDecide(c, reg.regime, reg.vote, buy, sell, setups, n, r);
      r.session = ss.session;
      r.atr     = ind.Atr(APEX_TF_ENTRY);
      r.time    = TimeCurrent();
     }
  };

#endif // APEXFLOW_SIGNALENGINE_MQH
