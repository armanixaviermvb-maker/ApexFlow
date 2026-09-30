//+------------------------------------------------------------------+
//| OrderFlow.mqh - participation data for the Auction Rejection      |
//| strategy, with explicit labelling of what the data really is.     |
//|                                                                   |
//| IMPORTANT - what this data is NOT:                                |
//| - Forex/CFD tick volume is the number of price updates from ONE   |
//|   broker's feed. It is not traded volume and not centralized      |
//|   institutional order flow.                                       |
//| - An MT5 market book (MarketBookGet) for Forex/CFD shows only the |
//|   broker's own liquidity. It is not a centralized exchange book.  |
//| Every value produced here carries a source label, and the logs    |
//| record it so no proxy can be mistaken for real order flow.        |
//|                                                                   |
//| PROXY mode : tick volume x directional apportioning              |
//|              (candle excursion or tick rule).                     |
//| NATIVE mode: broker real volume when the symbol provides it       |
//|              (exchange instruments), plus a broker-local market   |
//|              book imbalance in live trading when subscribed;      |
//|              falls back to the proxy when unavailable. The        |
//|              Strategy Tester never has market-book history.       |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_ORDERFLOW_MQH
#define APEXFLOW_ORDERFLOW_MQH

#include "../Config.mqh"
#include "../Utils.mqh"

#define APEX_TICKRULE_CACHE 256

//--- Candle-excursion apportioning (pure; unit-tested):
//--- buying push = open -> high, selling push = open -> low, as fractions of the range.
void ApexCandleExcursion(const MqlRates &b, double &buyFrac, double &sellFrac)
  {
   double range = b.high - b.low;
   if(range <= 0)
     {
      buyFrac = 0.5;
      sellFrac = 0.5;
      return;
     }
   buyFrac  = (b.high - b.open) / range;
   sellFrac = (b.open - b.low) / range;
  }

class COrderFlow
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   ENUM_APEX_ORDERFLOW_MODE m_mode;
   ENUM_APEX_EFFORT_SOURCE m_effort;
   bool              m_bookSubscribed;
   // tick-rule cache: bar open time -> up/down tick counts
   datetime          m_cacheTime[APEX_TICKRULE_CACHE];
   int               m_cacheUp[APEX_TICKRULE_CACHE];
   int               m_cacheDown[APEX_TICKRULE_CACHE];
   int               m_cacheNext;

   bool              TickRule(const datetime barTime, int &up, int &down)
     {
      for(int i = 0; i < APEX_TICKRULE_CACHE; i++)
         if(m_cacheTime[i] == barTime && barTime != 0)
           {
            up = m_cacheUp[i];
            down = m_cacheDown[i];
            return (up + down > 0);
           }
      up = 0;
      down = 0;
      MqlTick ticks[];
      ulong from = (ulong)barTime * 1000;
      ulong to   = ((ulong)barTime + (ulong)PeriodSeconds(m_tf)) * 1000 - 1;
      int n = CopyTicksRange(m_symbol, ticks, COPY_TICKS_INFO, from, to);
      if(n <= 1)
         return false;
      for(int k = 1; k < n; k++)
        {
         if(ticks[k].bid > ticks[k - 1].bid)
            up++;
         else
            if(ticks[k].bid < ticks[k - 1].bid)
               down++;
        }
      m_cacheTime[m_cacheNext] = barTime;
      m_cacheUp[m_cacheNext]   = up;
      m_cacheDown[m_cacheNext] = down;
      m_cacheNext = (m_cacheNext + 1) % APEX_TICKRULE_CACHE;
      return (up + down > 0);
     }

public:
                     COrderFlow(void) : m_symbol(""), m_tf(PERIOD_M5), m_mode(APEX_OF_PROXY),
                     m_effort(APEX_EFFORT_CANDLE), m_bookSubscribed(false), m_cacheNext(0)
     {
      for(int i = 0; i < APEX_TICKRULE_CACHE; i++)
        {
         m_cacheTime[i] = 0;
         m_cacheUp[i] = 0;
         m_cacheDown[i] = 0;
        }
     }

   void              Init(const SApexConfig &c)
     {
      m_symbol = c.symbol;
      m_tf     = c.tfEntry;
      m_mode   = c.arOrderFlow;
      m_effort = c.arEffortSource;
      m_bookSubscribed = false;
      if(!c.enableAuction)
         return;
      if(m_mode == APEX_OF_NATIVE && !MQLInfoInteger(MQL_TESTER))
        {
         m_bookSubscribed = MarketBookAdd(m_symbol);
         ApexLog(APEX_LOG_INFO, "ORDERFLOW_MODE",
                 StringFormat("SYMBOL=%s MODE=NATIVE MARKET_BOOK=%s NOTE=broker-local book, not centralized order flow",
                              m_symbol, (m_bookSubscribed ? "SUBSCRIBED" : "UNAVAILABLE")));
        }
      else
         ApexLog(APEX_LOG_INFO, "ORDERFLOW_MODE",
                 StringFormat("SYMBOL=%s MODE=%s EFFORT=%s NOTE=proxy data (tick volume is not traded volume)",
                              m_symbol, (m_mode == APEX_OF_NATIVE ? "NATIVE->PROXY(tester)" : "PROXY"),
                              EnumToString(m_effort)));
     }

   void              Release(void)
     {
      if(m_bookSubscribed)
         MarketBookRelease(m_symbol);
      m_bookSubscribed = false;
     }

   //--- Broker-local book imbalance in [-1, 1] (+ = more bid volume). NATIVE live only.
   bool              BookImbalance(double &imbalance)
     {
      imbalance = 0;
      if(!m_bookSubscribed)
         return false;
      MqlBookInfo book[];
      if(!MarketBookGet(m_symbol, book) || ArraySize(book) == 0)
         return false;
      double bid = 0, ask = 0;
      for(int i = 0; i < ArraySize(book); i++)
        {
         double v = (book[i].volume_real > 0) ? book[i].volume_real : (double)book[i].volume;
         if(book[i].type == BOOK_TYPE_BUY || book[i].type == BOOK_TYPE_BUY_MARKET)
            bid += v;
         else
            if(book[i].type == BOOK_TYPE_SELL || book[i].type == BOOK_TYPE_SELL_MARKET)
               ask += v;
        }
      if(bid + ask <= 0)
         return false;
      imbalance = (bid - ask) / (bid + ask);
      return true;
     }

   //--- Directional effort per bar for the first `count` bars of `r` (series, 0 = last closed).
   //--- total = participation (real volume in NATIVE mode when available, else tick volume).
   //--- Returns the data label.
   string            BarEfforts(const MqlRates &r[], const int count, double &buyE[], double &sellE[], double &total[])
     {
      int n = (int)MathMin(count, ArraySize(r));
      ArrayResize(buyE, n);
      ArrayResize(sellE, n);
      ArrayResize(total, n);
      bool usedReal = false, usedTick = false, usedCandle = false;
      for(int i = 0; i < n; i++)
        {
         double v = (double)r[i].tick_volume;
         if(m_mode == APEX_OF_NATIVE && r[i].real_volume > 0)
           {
            v = (double)r[i].real_volume;
            usedReal = true;
           }
         double bf = 0.5, sf = 0.5;
         bool haveTick = false;
         if(m_effort == APEX_EFFORT_TICK_RULE)
           {
            int up = 0, down = 0;
            if(TickRule(r[i].time, up, down))
              {
               bf = (double)up / (up + down);
               sf = (double)down / (up + down);
               haveTick = true;
               usedTick = true;
              }
           }
         if(!haveTick)
           {
            ApexCandleExcursion(r[i], bf, sf);
            usedCandle = true;
           }
         total[i] = v;
         buyE[i]  = v * bf;
         sellE[i] = v * sf;
        }
      string label = usedReal ? "NATIVE:BROKER_REAL_VOLUME" : "PROXY:TICK_VOLUME";
      if(usedTick && usedCandle)
         label += "+TICK_RULE(partial,CANDLE_EXCURSION_FALLBACK)";
      else
         if(usedTick)
            label += "+TICK_RULE";
         else
            label += "+CANDLE_EXCURSION";
      return label;
     }

   bool              BookSubscribed(void) const { return m_bookSubscribed; }
  };

#endif // APEXFLOW_ORDERFLOW_MQH
