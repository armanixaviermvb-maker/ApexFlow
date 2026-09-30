//+------------------------------------------------------------------+
//| ATRHelper.mqh - ATR-derived measurements                          |
//| Arrays are "series" ordered: index 0 = most recent CLOSED bar.    |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_ATRHELPER_MQH
#define APEXFLOW_ATRHELPER_MQH

#include "../Utils.mqh"

//--- Percentile (0..100) of the latest ATR against the previous `lookback` values.
double ApexATRPercentile(const double &atr[], const int lookback)
  {
   if(ArraySize(atr) < 2)
      return 50.0;
   return ApexPercentileRank(atr, 1, lookback, atr[0]);
  }

//--- ATR expressed in points.
double ApexATRPoints(const double atrValue, const double point)
  {
   if(point <= 0)
      return 0.0;
   return atrValue / point;
  }

//--- True when volatility is expanding: latest ATR above the ATR `bars` ago.
bool ApexATRExpanding(const double &atr[], const int bars)
  {
   if(ArraySize(atr) <= bars)
      return false;
   return atr[0] > atr[bars];
  }

#endif // APEXFLOW_ATRHELPER_MQH
