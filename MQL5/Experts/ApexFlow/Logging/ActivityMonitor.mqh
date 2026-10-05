//+------------------------------------------------------------------+
//| ActivityMonitor.mqh - how long since the last entry, and why      |
//|                                                                   |
//| Counts the NO_TRADE / rejection reason of every evaluated bar     |
//| since the last entry and reports the top blockers on the          |
//| dashboard and periodically in the log.                            |
//| It only REPORTS. It never loosens filters or forces a trade:      |
//| any change to selectivity is a human decision (Activity Profile). |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_ACTIVITYMONITOR_MQH
#define APEXFLOW_ACTIVITYMONITOR_MQH

#include "../Config.mqh"
#include "../Utils.mqh"

#define APEX_REJECT_SLOTS 64

class CActivityMonitor
  {
private:
   string            m_symbol;
   long              m_magic;
   datetime          m_lastEntry;     // last validated/executed entry (0 = none seen)
   datetime          m_since;         // start of the current idle period
   datetime          m_lastReport;
   double            m_reportHours;
   int               m_counts[APEX_REJECT_SLOTS];
   int               m_evals;

   void              ResetCounts(void)
     {
      for(int i = 0; i < APEX_REJECT_SLOTS; i++)
         m_counts[i] = 0;
      m_evals = 0;
     }

   //--- Most recent ApexFlow entry on this symbol from broker history (restart-safe).
   datetime          LastEntryFromHistory(void) const
     {
      datetime now = TimeCurrent();
      if(!HistorySelect(now - 60 * 86400, now + 86400))
         return 0;
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0)
            continue;
         if(HistoryDealGetInteger(t, DEAL_MAGIC) != m_magic || HistoryDealGetString(t, DEAL_SYMBOL) != m_symbol)
            continue;
         if(HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN)
            return (datetime)HistoryDealGetInteger(t, DEAL_TIME);
        }
      return 0;
     }

public:
                     CActivityMonitor(void) : m_symbol(""), m_magic(0), m_lastEntry(0), m_since(0),
                     m_lastReport(0), m_reportHours(6), m_evals(0) { ResetCounts(); }

   void              Init(const SApexConfig &c)
     {
      m_symbol      = c.symbol;
      m_magic       = c.magic;
      m_reportHours = c.idleReportHours;
      m_lastEntry   = LastEntryFromHistory();
      m_since       = (m_lastEntry > 0) ? m_lastEntry : TimeCurrent();
      m_lastReport  = TimeCurrent();
      ResetCounts();
     }

   //--- Called once per evaluated bar with the final status and reason.
   //--- VALIDATED (TEST mode: would have traded) and EXECUTED both count as entries.
   void              Record(const string status, const ENUM_APEX_REJECT reason)
     {
      if(status == "EXECUTED" || status == "VALIDATED")
        {
         m_lastEntry = TimeCurrent();
         m_since = m_lastEntry;
         ResetCounts();
         return;
        }
      m_evals++;
      int k = (int)reason;
      if(k >= 0 && k < APEX_REJECT_SLOTS)
         m_counts[k]++;
     }

   double            IdleHours(void) const
     {
      return (TimeCurrent() - m_since) / 3600.0;
     }

   bool              HasEntry(void) const { return m_lastEntry > 0; }

   //--- e.g. "score_below_threshold 52%, outside_session 21%"
   string            TopBlockers(const int topN) const
     {
      if(m_evals == 0)
         return "no bars evaluated yet";
      bool used[APEX_REJECT_SLOTS];
      for(int i = 0; i < APEX_REJECT_SLOTS; i++)
         used[i] = false;
      string s = "";
      for(int n = 0; n < topN; n++)
        {
         int best = -1;
         for(int i = 0; i < APEX_REJECT_SLOTS; i++)
            if(!used[i] && m_counts[i] > 0 && (best < 0 || m_counts[i] > m_counts[best]))
               best = i;
         if(best < 0)
            break;
         used[best] = true;
         if(s != "")
            s += ", ";
         s += StringFormat("%s %.0f%%", ApexRejectToString((ENUM_APEX_REJECT)best), 100.0 * m_counts[best] / m_evals);
        }
      return s;
     }

   //--- Periodic log line while idle (timer path).
   void              MaybeReport(void)
     {
      if(m_reportHours <= 0)
         return;
      datetime now = TimeCurrent();
      if(now - m_lastReport < (long)(m_reportHours * 3600))
         return;
      m_lastReport = now;
      if(now - m_since < (long)(m_reportHours * 3600))
         return; // an entry happened recently
      ApexLog(APEX_LOG_INFO, "IDLE_REPORT",
              StringFormat("SYMBOL=%s IDLE_HOURS=%.1f SINCE=%s BARS_EVALUATED=%d TOP_BLOCKERS=%s NOTE=report only; filters are not loosened automatically",
                           m_symbol, IdleHours(), (m_lastEntry > 0 ? "last_entry" : "ea_start"), m_evals, TopBlockers(4)));
     }
  };

#endif // APEXFLOW_ACTIVITYMONITOR_MQH
