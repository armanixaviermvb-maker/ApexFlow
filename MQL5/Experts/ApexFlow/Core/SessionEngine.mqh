//+------------------------------------------------------------------+
//| SessionEngine.mqh - timezone and DST aware session detection      |
//|                                                                   |
//| Server time -> UTC -> each market's local time (London, New York, |
//| Tokyo) using the real DST rules of that market. Session hours are |
//| configured in local market time, so "08:00 London" is correct in  |
//| both summer and winter regardless of the broker's clock.          |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_SESSIONENGINE_MQH
#define APEXFLOW_SESSIONENGINE_MQH

#include "../Config.mqh"
#include "../Utils.mqh"

//--- Server GMT offset (seconds) for a manual configuration at server time `server`.
int ApexManualServerOffsetSec(const int gmtHours, const ENUM_APEX_DST_RULE rule, const datetime server)
  {
   int base = gmtHours * 3600;
   datetime utcGuess = server - base;
   bool dst = false;
   if(rule == APEX_DST_EU)
      dst = ApexIsEuDst(utcGuess);
   else
      if(rule == APEX_DST_US)
         dst = ApexIsUsDst(utcGuess);
   return base + (dst ? 3600 : 0);
  }

//--- Pure session classification from a UTC time. Used by the engine and by tests.
void ApexClassifySession(const SApexConfig &c, const datetime utc, SSessionState &s)
  {
   s.utcTime    = utc;
   s.londonDst  = ApexIsEuDst(utc);
   s.newYorkDst = ApexIsUsDst(utc);

   int lonMin = ApexMinuteOfDay(utc + ApexLondonOffsetSec(utc));
   int nyMin  = ApexMinuteOfDay(utc + ApexNewYorkOffsetSec(utc));
   int tkMin  = ApexMinuteOfDay(utc + ApexTokyoOffsetSec());

   // Forex is closed at the weekend (Saturday, and Sunday before the Asian open).
   int dowUtc = ApexDayOfWeek(utc);
   bool weekend = (dowUtc == 6 || (dowUtc == 0 && ApexMinuteOfDay(utc) < 21 * 60));

   bool inLondon = !weekend && ApexInWindow(lonMin, c.londonStartMin, c.londonEndMin);
   bool inNY     = !weekend && ApexInWindow(nyMin, c.newYorkStartMin, c.newYorkEndMin);
   bool inAsia   = !weekend && ApexInWindow(tkMin, c.asiaStartMin, c.asiaEndMin);

   if(inLondon && inNY)
      s.session = APEX_SESSION_OVERLAP;
   else
      if(inNY)
         s.session = APEX_SESSION_NEW_YORK;
      else
         if(inLondon)
            s.session = APEX_SESSION_LONDON;
         else
            if(inAsia)
               s.session = APEX_SESSION_ASIA;
            else
               s.session = APEX_SESSION_OUTSIDE;

   // Entries are allowed while at least one ENABLED window stays open for
   // longer than the no-entry buffer.
   int best = -1;
   if(inLondon && inNY && c.enableOverlap)
      best = MathMax(best, MathMin(ApexMinutesToWindowEnd(lonMin, c.londonStartMin, c.londonEndMin),
                                   ApexMinutesToWindowEnd(nyMin, c.newYorkStartMin, c.newYorkEndMin)));
   if(inLondon && c.enableLondon && !(inNY && !c.enableOverlap))
      best = MathMax(best, ApexMinutesToWindowEnd(lonMin, c.londonStartMin, c.londonEndMin));
   if(inNY && c.enableNewYork && !(inLondon && !c.enableOverlap))
      best = MathMax(best, ApexMinutesToWindowEnd(nyMin, c.newYorkStartMin, c.newYorkEndMin));
   if(inAsia && c.enableAsia && s.session == APEX_SESSION_ASIA)
      best = MathMax(best, ApexMinutesToWindowEnd(tkMin, c.asiaStartMin, c.asiaEndMin));

   s.minutesToEnd   = best;
   s.endingSoon     = (best >= 0 && best <= c.noEntryBeforeEndMin);
   s.entriesAllowed = (best > c.noEntryBeforeEndMin);

   // Start of the current session (UTC) for session high/low tracking.
   int since = 0;
   if(s.session == APEX_SESSION_LONDON)
      since = ApexMinutesSinceWindowStart(lonMin, c.londonStartMin, c.londonEndMin);
   else
      if(s.session == APEX_SESSION_NEW_YORK || s.session == APEX_SESSION_OVERLAP)
         since = ApexMinutesSinceWindowStart(nyMin, c.newYorkStartMin, c.newYorkEndMin);
      else
         if(s.session == APEX_SESSION_ASIA)
            since = ApexMinutesSinceWindowStart(tkMin, c.asiaStartMin, c.asiaEndMin);
   // For the overlap, use the London open so the session range covers the whole European day.
   if(s.session == APEX_SESSION_OVERLAP)
      since = ApexMinutesSinceWindowStart(lonMin, c.londonStartMin, c.londonEndMin);
   s.sessionStartServer = utc - since * 60; // converted to server time by the caller
  }

class CSessionEngine
  {
private:
   SApexConfig       m_cfg;
   int               m_autoOffsetSec;
   bool              m_autoValid;
   bool              m_useAuto;

public:
                     CSessionEngine(void) : m_autoOffsetSec(0), m_autoValid(false), m_useAuto(false) {}

   void              Init(const SApexConfig &c)
     {
      m_cfg = c;
      // In the Strategy Tester TimeGMT() equals the simulated server time,
      // so automatic detection is impossible: use the manual settings.
      m_useAuto = (c.serverTimeMode == APEX_TZ_AUTO && !MQLInfoInteger(MQL_TESTER));
      UpdateAutoOffset();
     }

   //--- Live auto-detection of the server offset (rounded to 15 minutes).
   //--- Returns false when the clock looks wrong (clock circuit breaker).
   bool              UpdateAutoOffset(void)
     {
      if(!m_useAuto)
        {
         m_autoValid = true;
         return true;
        }
      datetime gmt = TimeGMT();
      datetime srv = TimeTradeServer();
      if(gmt <= 0 || srv <= 0)
        {
         m_autoValid = false;
         return false;
        }
      long diff = (long)srv - (long)gmt;
      long rounded = (long)MathRound(diff / 900.0) * 900;
      if(MathAbs((double)rounded) > 14 * 3600 || MathAbs((double)(diff - rounded)) > 300)
        {
         m_autoValid = false;
         return false;
        }
      m_autoOffsetSec = (int)rounded;
      m_autoValid = true;
      return true;
     }

   bool              ClockValid(void) const { return m_autoValid; }
   bool              UsingAuto(void) const { return m_useAuto; }

   int               ServerOffsetSec(const datetime server) const
     {
      if(m_useAuto)
         return m_autoOffsetSec;
      return ApexManualServerOffsetSec(m_cfg.serverGmtOffsetHours, m_cfg.serverDstRule, server);
     }

   datetime          ServerToUtc(const datetime server) const
     {
      return server - ServerOffsetSec(server);
     }

   void              Evaluate(const datetime server, SSessionState &s) const
     {
      ZeroMemory(s);
      s.serverTime      = server;
      s.serverOffsetSec = ServerOffsetSec(server);
      s.valid           = (server > 0 && m_autoValid);
      datetime utc      = server - s.serverOffsetSec;
      ApexClassifySession(m_cfg, utc, s);
      s.serverTime         = server;
      s.sessionStartServer = s.sessionStartServer + s.serverOffsetSec;
      if(!s.valid)
        {
         s.entriesAllowed = false;
        }
     }
  };

#endif // APEXFLOW_SESSIONENGINE_MQH
