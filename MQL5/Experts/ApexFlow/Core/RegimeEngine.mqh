//+------------------------------------------------------------------+
//| RegimeEngine.mqh - multi-factor market regime classification      |
//|                                                                   |
//| Five independent votes (EMA alignment, EMA slope, confirmation    |
//| structure, RSI, 20-bar return) plus volatility percentile and     |
//| range width. No single indicator can classify the market.         |
//| Hysteresis: a new trend/range regime must be seen on two          |
//| consecutive updates; moves to TRANSITION/HIGH_VOL are immediate   |
//| because they reduce risk.                                         |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_REGIMEENGINE_MQH
#define APEXFLOW_REGIMEENGINE_MQH

#include "../Types.mqh"
#include "../Utils.mqh"

#define APEX_REGIME_HIGH_VOL_PCT   90.0
#define APEX_REGIME_LOW_VOL_PCT    10.0
#define APEX_REGIME_SLOPE_MIN      0.3
#define APEX_REGIME_RETURN_MIN     1.5
#define APEX_REGIME_RANGE_MAX_ATR  6.0
#define APEX_REGIME_TREND_VOTES    3

int ApexEmaAlignment(const double fast, const double slow, const double longEma)
  {
   if(fast > slow && slow > longEma)
      return 1;
   if(fast < slow && slow < longEma)
      return -1;
   return 0;
  }

//--- Pure classification. `vote` receives -5..+5, `emaAlign` -1..+1.
ENUM_APEX_REGIME ApexClassifyRegime(const SRegimeInputs &in, int &vote, int &emaAlign)
  {
   emaAlign = ApexEmaAlignment(in.emaFastCtx, in.emaSlowCtx, in.emaLongCtx);
   vote = emaAlign;
   if(in.slopeNorm > APEX_REGIME_SLOPE_MIN)
      vote++;
   else
      if(in.slopeNorm < -APEX_REGIME_SLOPE_MIN)
         vote--;
   if(in.confirmBias == APEX_BIAS_BULLISH)
      vote++;
   else
      if(in.confirmBias == APEX_BIAS_BEARISH)
         vote--;
   if(in.rsiCtx > 55)
      vote++;
   else
      if(in.rsiCtx < 45)
         vote--;
   if(in.returnAtr > APEX_REGIME_RETURN_MIN)
      vote++;
   else
      if(in.returnAtr < -APEX_REGIME_RETURN_MIN)
         vote--;

   if(in.atrPercentile >= APEX_REGIME_HIGH_VOL_PCT)
      return APEX_REGIME_HIGH_VOL;
   if(in.atrPercentile <= APEX_REGIME_LOW_VOL_PCT)
      return APEX_REGIME_LOW_VOL;
   if(in.confirmBias == APEX_BIAS_TRANSITION)
      return APEX_REGIME_TRANSITION;
   if(vote >= APEX_REGIME_TREND_VOTES)
      return APEX_REGIME_TREND_UP;
   if(vote <= -APEX_REGIME_TREND_VOTES)
      return APEX_REGIME_TREND_DOWN;
   if(MathAbs(vote) <= 1 && in.rangeWidthAtr <= APEX_REGIME_RANGE_MAX_ATR)
      return APEX_REGIME_RANGE;
   return APEX_REGIME_TRANSITION;
  }

class CRegimeEngine
  {
private:
   SRegimeState      m_state;
   ENUM_APEX_REGIME  m_candidate;
   int               m_candidateCount;
   bool              m_initialized;

public:
                     CRegimeEngine(void) : m_candidate(APEX_REGIME_UNKNOWN), m_candidateCount(0), m_initialized(false)
     {
      ZeroMemory(m_state);
      m_state.regime = APEX_REGIME_UNKNOWN;
     }

   void              Reset(void)
     {
      ZeroMemory(m_state);
      m_state.regime   = APEX_REGIME_UNKNOWN;
      m_candidate      = APEX_REGIME_UNKNOWN;
      m_candidateCount = 0;
      m_initialized    = false;
     }

   //--- Returns true when the confirmed regime changed.
   bool              Update(const SRegimeInputs &in, const datetime now)
     {
      int vote = 0, align = 0;
      ENUM_APEX_REGIME raw = ApexClassifyRegime(in, vote, align);
      m_state.raw           = raw;
      m_state.vote          = vote;
      m_state.emaAlign      = align;
      m_state.atrPercentile = in.atrPercentile;

      ENUM_APEX_REGIME old = m_state.regime;
      if(!m_initialized)
        {
         m_state.regime  = raw;
         m_state.since   = now;
         m_initialized   = true;
         m_candidateCount = 0;
         return true;
        }
      if(raw == m_state.regime)
        {
         m_candidateCount = 0;
         return false;
        }
      if(raw == APEX_REGIME_TRANSITION || raw == APEX_REGIME_HIGH_VOL)
        {
         m_state.regime   = raw;
         m_state.since    = now;
         m_candidateCount = 0;
         return (old != raw);
        }
      if(raw == m_candidate)
         m_candidateCount++;
      else
        {
         m_candidate      = raw;
         m_candidateCount = 1;
        }
      if(m_candidateCount >= 2)
        {
         m_state.regime   = raw;
         m_state.since    = now;
         m_candidateCount = 0;
         return true;
        }
      return false;
     }

   void              State(SRegimeState &out) const { out = m_state; }
   ENUM_APEX_REGIME  Regime(void) const { return m_state.regime; }
   int               Vote(void) const { return m_state.vote; }
  };

#endif // APEXFLOW_REGIMEENGINE_MQH
