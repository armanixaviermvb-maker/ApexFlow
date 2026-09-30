//+------------------------------------------------------------------+
//| NewsFilter.mqh - extension point for a future news filter         |
//|                                                                   |
//| The first implementation needs no external API: CNoNewsFilter     |
//| never blocks. A future implementation (e.g. based on the MT5      |
//| economic calendar, which is unavailable in the Strategy Tester)   |
//| can implement INewsFilter and be swapped in OnInit.               |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_NEWSFILTER_MQH
#define APEXFLOW_NEWSFILTER_MQH

interface INewsFilter
  {
   //--- true = block new entries now; `reason` explains why.
   bool              BlocksEntries(const string symbol, const datetime serverTime, string &reason);
   string            Name(void);
  };

class CNoNewsFilter : public INewsFilter
  {
public:
   bool              BlocksEntries(const string symbol, const datetime serverTime, string &reason)
     {
      reason = "";
      return false;
     }
   string            Name(void) { return "none"; }
  };

#endif // APEXFLOW_NEWSFILTER_MQH
