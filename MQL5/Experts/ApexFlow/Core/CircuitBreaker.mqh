//+------------------------------------------------------------------+
//| CircuitBreaker.mqh - entry kill-switches                          |
//|                                                                   |
//| Any active breaker blocks NEW entries. Existing positions are     |
//| still managed. "Auto" breakers clear when the condition clears;   |
//| "latched" breakers stay until a new trading day or an explicit    |
//| reset.                                                            |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_CIRCUITBREAKER_MQH
#define APEXFLOW_CIRCUITBREAKER_MQH

#include "../Types.mqh"
#include "../Utils.mqh"

class CCircuitBreaker
  {
private:
   bool              m_active[APEX_BRK_COUNT];
   bool              m_latched[APEX_BRK_COUNT];
   string            m_reason[APEX_BRK_COUNT];
   datetime          m_since[APEX_BRK_COUNT];
   string            m_symbol;

public:
                     CCircuitBreaker(void) : m_symbol("")
     {
      for(int i = 0; i < APEX_BRK_COUNT; i++)
        {
         m_active[i]  = false;
         m_latched[i] = false;
         m_reason[i]  = "";
         m_since[i]   = 0;
        }
     }

   void              Init(const string symbol) { m_symbol = symbol; }

   void              Trip(const int id, const string reason, const bool latched)
     {
      if(id < 0 || id >= APEX_BRK_COUNT)
         return;
      if(!m_active[id])
        {
         m_active[id] = true;
         m_since[id]  = TimeCurrent();
         ApexLog(APEX_LOG_ERROR, "CIRCUIT_BREAKER_TRIPPED",
                 StringFormat("SYMBOL=%s BREAKER=%s LATCHED=%s REASON=%s", m_symbol,
                              ApexBreakerToString(id), (latched ? "YES" : "NO"), reason));
        }
      m_latched[id] = m_latched[id] || latched;
      m_reason[id]  = reason;
     }

   void              Clear(const int id, const string why)
     {
      if(id < 0 || id >= APEX_BRK_COUNT || !m_active[id])
         return;
      m_active[id]  = false;
      m_latched[id] = false;
      ApexLog(APEX_LOG_INFO, "CIRCUIT_BREAKER_CLEARED",
              StringFormat("SYMBOL=%s BREAKER=%s WHY=%s", m_symbol, ApexBreakerToString(id), why));
     }

   //--- Auto breaker: follows the condition, unless it has been latched.
   void              Set(const int id, const bool condition, const string reason)
     {
      if(condition)
         Trip(id, reason, false);
      else
         if(m_active[id] && !m_latched[id])
            Clear(id, "condition cleared");
     }

   bool              Active(const int id) const { return (id >= 0 && id < APEX_BRK_COUNT && m_active[id]); }

   bool              AnyActive(void) const
     {
      for(int i = 0; i < APEX_BRK_COUNT; i++)
         if(m_active[i])
            return true;
      return false;
     }

   string            Describe(void) const
     {
      string s = "";
      for(int i = 0; i < APEX_BRK_COUNT; i++)
        {
         if(!m_active[i])
            continue;
         if(s != "")
            s += ", ";
         s += ApexBreakerToString(i);
        }
      return s;
     }

   string            Reason(const int id) const
     {
      if(id < 0 || id >= APEX_BRK_COUNT)
         return "";
      return m_reason[id];
     }

   //--- New trading day: release day-scoped latched breakers.
   void              OnNewDay(void)
     {
      Clear(APEX_BRK_ORDER_FAILURES, "new trading day");
      Clear(APEX_BRK_DAILY_LOSS, "new trading day");
      Clear(APEX_BRK_ACCOUNT_DAILY_LOSS, "new trading day");
     }
  };

#endif // APEXFLOW_CIRCUITBREAKER_MQH
