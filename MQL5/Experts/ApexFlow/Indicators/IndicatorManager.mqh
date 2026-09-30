//+------------------------------------------------------------------+
//| IndicatorManager.mqh - indicator handles and cached market data   |
//|                                                                   |
//| Handles are created once in Init(). Refresh() copies CLOSED bars  |
//| only (start position 1), so the analysis path never sees the      |
//| forming bar and cannot look ahead.                                |
//| All cached arrays are series: index 0 = most recent closed bar.   |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_INDICATORMANAGER_MQH
#define APEXFLOW_INDICATORMANAGER_MQH

#include "../Config.mqh"
#include "../Utils.mqh"
#include "ATRHelper.mqh"

//--- Cached data for one timeframe.
class CTfData
  {
public:
   ENUM_TIMEFRAMES   tf;
   int               hFast;
   int               hSlow;
   int               hLong;
   int               hRsi;
   int               hAtr;
   double            fast[];
   double            slow[];
   double            longEma[];
   double            rsi[];
   double            atr[];
   MqlRates          rates[];
   datetime          lastBarTime;   // open time of the forming bar at last check
   datetime          lastRefresh;   // open time of the newest closed bar in the cache
   bool              ready;

                     CTfData(void) : tf(PERIOD_CURRENT), hFast(INVALID_HANDLE), hSlow(INVALID_HANDLE),
                     hLong(INVALID_HANDLE), hRsi(INVALID_HANDLE), hAtr(INVALID_HANDLE),
                     lastBarTime(0), lastRefresh(0), ready(false) {}
  };

class CIndicatorManager
  {
private:
   string            m_symbol;
   int               m_depth;
   double            m_pdh;
   double            m_pdl;
   double            m_todayHigh;
   double            m_todayLow;

   bool              CopySeries(const int handle, double &buffer[])
     {
      ArraySetAsSeries(buffer, true);
      if(handle == INVALID_HANDLE)
         return false;
      if(BarsCalculated(handle) < m_depth + 1)
         return false;
      int copied = CopyBuffer(handle, 0, 1, m_depth, buffer);
      return (copied == m_depth);
     }

public:
   CTfData           data[APEX_TF_COUNT];

                     CIndicatorManager(void) : m_symbol(""), m_depth(0), m_pdh(0), m_pdl(0),
                     m_todayHigh(0), m_todayLow(0) {}

   int               Depth(void) const { return m_depth; }
   double            PrevDayHigh(void) const { return m_pdh; }
   double            PrevDayLow(void) const { return m_pdl; }

   bool              Init(const SApexConfig &c)
     {
      m_symbol = c.symbol;
      m_depth  = MathMax(c.atrPctLookback + 25, 120);
      data[APEX_TF_CONTEXT].tf = c.tfContext;
      data[APEX_TF_CONFIRM].tf = c.tfConfirm;
      data[APEX_TF_ENTRY].tf   = c.tfEntry;
      for(int i = 0; i < APEX_TF_COUNT; i++)
        {
         ENUM_TIMEFRAMES tf = data[i].tf;
         data[i].hFast = iMA(m_symbol, tf, c.fastEMA, 0, MODE_EMA, PRICE_CLOSE);
         data[i].hSlow = iMA(m_symbol, tf, c.slowEMA, 0, MODE_EMA, PRICE_CLOSE);
         data[i].hLong = iMA(m_symbol, tf, c.contextEMA, 0, MODE_EMA, PRICE_CLOSE);
         data[i].hRsi  = iRSI(m_symbol, tf, c.rsiPeriod, PRICE_CLOSE);
         data[i].hAtr  = iATR(m_symbol, tf, c.atrPeriod);
         if(data[i].hFast == INVALID_HANDLE || data[i].hSlow == INVALID_HANDLE ||
            data[i].hLong == INVALID_HANDLE || data[i].hRsi == INVALID_HANDLE ||
            data[i].hAtr == INVALID_HANDLE)
           {
            ApexLogError("CIndicatorManager::Init", m_symbol, "create indicator handles " + EnumToString(tf),
                         GetLastError(), "indicator handle creation failed");
            return false;
           }
         ArraySetAsSeries(data[i].rates, true);
        }
      return true;
     }

   void              Release(void)
     {
      for(int i = 0; i < APEX_TF_COUNT; i++)
        {
         if(data[i].hFast != INVALID_HANDLE) IndicatorRelease(data[i].hFast);
         if(data[i].hSlow != INVALID_HANDLE) IndicatorRelease(data[i].hSlow);
         if(data[i].hLong != INVALID_HANDLE) IndicatorRelease(data[i].hLong);
         if(data[i].hRsi  != INVALID_HANDLE) IndicatorRelease(data[i].hRsi);
         if(data[i].hAtr  != INVALID_HANDLE) IndicatorRelease(data[i].hAtr);
         data[i].hFast = INVALID_HANDLE;
         data[i].hSlow = INVALID_HANDLE;
         data[i].hLong = INVALID_HANDLE;
         data[i].hRsi  = INVALID_HANDLE;
         data[i].hAtr  = INVALID_HANDLE;
         data[i].ready = false;
        }
     }

   //--- True once per new bar on the given timeframe (cheap: one iTime call).
   bool              IsNewBar(const int slot)
     {
      datetime t = iTime(m_symbol, data[slot].tf, 0);
      if(t == 0)
         return false;
      if(t != data[slot].lastBarTime)
        {
         data[slot].lastBarTime = t;
         return true;
        }
      return false;
     }

   //--- Copy closed-bar data for one timeframe.
   bool              Refresh(const int slot)
     {
      data[slot].ready = false;
      ArraySetAsSeries(data[slot].rates, true);
      int copied = CopyRates(m_symbol, data[slot].tf, 1, m_depth, data[slot].rates);
      if(copied != m_depth)
         return false;
      if(!CopySeries(data[slot].hFast, data[slot].fast))
         return false;
      if(!CopySeries(data[slot].hSlow, data[slot].slow))
         return false;
      if(!CopySeries(data[slot].hLong, data[slot].longEma))
         return false;
      if(!CopySeries(data[slot].hRsi, data[slot].rsi))
         return false;
      if(!CopySeries(data[slot].hAtr, data[slot].atr))
         return false;
      data[slot].lastRefresh = data[slot].rates[0].time;
      data[slot].ready = true;
      return true;
     }

   //--- Previous completed day high/low and today's range so far.
   bool              RefreshDaily(void)
     {
      MqlRates d1[];
      ArraySetAsSeries(d1, true);
      if(CopyRates(m_symbol, PERIOD_D1, 0, 2, d1) != 2)
         return false;
      m_todayHigh = d1[0].high;
      m_todayLow  = d1[0].low;
      m_pdh       = d1[1].high;
      m_pdl       = d1[1].low;
      return true;
     }

   bool              RefreshAll(void)
     {
      bool ok = true;
      for(int i = 0; i < APEX_TF_COUNT; i++)
         if(!Refresh(i))
            ok = false;
      if(!RefreshDaily())
         ok = false;
      return ok;
     }

   bool              Ready(void) const
     {
      for(int i = 0; i < APEX_TF_COUNT; i++)
         if(!data[i].ready)
            return false;
      return true;
     }

   //--- Convenience accessors (shift 0 = last closed bar).
   double            Atr(const int slot, const int shift = 0) const
     {
      if(!data[slot].ready || shift >= ArraySize(data[slot].atr))
         return 0.0;
      return data[slot].atr[shift];
     }

   double            AtrPercentile(const int slot, const int lookback) const
     {
      if(!data[slot].ready)
         return 50.0;
      return ApexATRPercentile(data[slot].atr, lookback);
     }
  };

#endif // APEXFLOW_INDICATORMANAGER_MQH
