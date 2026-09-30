//+------------------------------------------------------------------+
//| Utils.mqh - pure helpers: time/DST, price & volume normalization, |
//| statistics, trade retcodes and structured logging.                |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_UTILS_MQH
#define APEXFLOW_UTILS_MQH

#include "Types.mqh"

//====================================================================
// LOGGING
//====================================================================
ENUM_APEX_LOG_LEVEL g_apexLogLevel = APEX_LOG_INFO;

string ApexLevelName(const ENUM_APEX_LOG_LEVEL lvl)
  {
   if(lvl == APEX_LOG_ERROR)
      return "ERROR";
   if(lvl == APEX_LOG_DEBUG)
      return "DEBUG";
   return "INFO";
  }

//--- One structured line: [APEXFLOW] LEVEL=.. EVENT=.. key=value ...
void ApexLog(const ENUM_APEX_LOG_LEVEL lvl, const string event, const string detail)
  {
   if(lvl > g_apexLogLevel)
      return;
   if(lvl != APEX_LOG_ERROR && MQLInfoInteger(MQL_OPTIMIZATION))
      return;
   PrintFormat("%s LEVEL=%s EVENT=%s %s", APEX_LOG_TAG, ApexLevelName(lvl), event, detail);
  }

//--- Section 41: timestamp, function, symbol, operation, retcode, description.
void ApexLogError(const string function, const string symbol, const string operation,
                  const long retcode, const string description)
  {
   PrintFormat("%s LEVEL=ERROR EVENT=OPERATION_FAILED TIME=%s FUNCTION=%s SYMBOL=%s OPERATION=%s RETCODE=%I64d DESCRIPTION=%s",
               APEX_LOG_TAG, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
               function, symbol, operation, retcode, description);
  }

//====================================================================
// MATH
//====================================================================
double ApexClamp(const double v, const double lo, const double hi)
  {
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
  }

//--- Percentile rank (0..100) of `value` among values[from .. from+count-1]:
//--- share of values strictly below `value`.
double ApexPercentileRank(const double &values[], const int from, const int count, const double value)
  {
   int n = 0, below = 0;
   int size = ArraySize(values);
   for(int i = from; i < from + count && i < size; i++)
     {
      n++;
      if(values[i] < value)
         below++;
     }
   if(n == 0)
      return 50.0;
   return 100.0 * below / n;
  }

//====================================================================
// TIME & DAYLIGHT SAVING
// All DST rules are computed from UTC, so they are independent of the
// broker server clock.
//====================================================================
datetime ApexMakeTime(const int year, const int month, const int day, const int hour, const int minute)
  {
   MqlDateTime t;
   ZeroMemory(t);
   t.year = year;
   t.mon  = month;
   t.day  = day;
   t.hour = hour;
   t.min  = minute;
   t.sec  = 0;
   return StructToTime(t);
  }

int ApexDayOfWeek(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.day_of_week; // 0 = Sunday
  }

int ApexYear(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.year;
  }

int ApexMinuteOfDay(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t, s);
   return s.hour * 60 + s.min;
  }

datetime ApexDayStart(const datetime t)
  {
   long v = (long)t;
   return (datetime)(v - v % 86400);
  }

//--- 00:00 of the n-th Sunday (n >= 1) of a month.
datetime ApexNthSunday(const int year, const int month, const int n)
  {
   datetime first = ApexMakeTime(year, month, 1, 0, 0);
   int dow = ApexDayOfWeek(first);
   int firstSunday = 1 + ((7 - dow) % 7);
   return ApexMakeTime(year, month, firstSunday + 7 * (n - 1), 0, 0);
  }

//--- 00:00 of the last Sunday of a month.
datetime ApexLastSunday(const int year, const int month)
  {
   int ny = year, nm = month + 1;
   if(nm > 12)
     {
      nm = 1;
      ny++;
     }
   datetime lastDay = ApexMakeTime(ny, nm, 1, 0, 0) - 86400;
   int dow = ApexDayOfWeek(lastDay);
   return lastDay - dow * 86400;
  }

//--- EU summer time: last Sunday of March 01:00 UTC to last Sunday of October 01:00 UTC.
bool ApexIsEuDst(const datetime utc)
  {
   int y = ApexYear(utc);
   datetime start = ApexLastSunday(y, 3) + 3600;
   datetime end   = ApexLastSunday(y, 10) + 3600;
   return (utc >= start && utc < end);
  }

//--- US daylight time: 2nd Sunday of March 02:00 EST (07:00 UTC) to
//--- 1st Sunday of November 02:00 EDT (06:00 UTC).
bool ApexIsUsDst(const datetime utc)
  {
   int y = ApexYear(utc);
   datetime start = ApexNthSunday(y, 3, 2) + 7 * 3600;
   datetime end   = ApexNthSunday(y, 11, 1) + 6 * 3600;
   return (utc >= start && utc < end);
  }

int ApexLondonOffsetSec(const datetime utc)   { return ApexIsEuDst(utc) ? 3600 : 0; }
int ApexNewYorkOffsetSec(const datetime utc)  { return ApexIsUsDst(utc) ? -4 * 3600 : -5 * 3600; }
int ApexTokyoOffsetSec()                      { return 9 * 3600; }

//--- Is minute-of-day `m` inside [start, end)? Handles windows crossing midnight.
bool ApexInWindow(const int m, const int start, const int end)
  {
   if(start < end)
      return (m >= start && m < end);
   return (m >= start || m < end);
  }

//--- Minutes until the window closes (assumes m is inside the window).
int ApexMinutesToWindowEnd(const int m, const int start, const int end)
  {
   if(start < end)
      return end - m;
   if(m >= start)
      return 1440 - m + end;
   return end - m;
  }

//--- Minutes since the window opened (assumes m is inside the window).
int ApexMinutesSinceWindowStart(const int m, const int start, const int end)
  {
   if(start < end || m >= start)
      return m - start;
   return 1440 - start + m;
  }

//====================================================================
// PRICE & VOLUME
//====================================================================
double ApexNormalizePrice(const string symbol, const double price)
  {
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double p = price;
   if(tickSize > 0)
      p = MathRound(p / tickSize) * tickSize;
   return NormalizeDouble(p, digits);
  }

//--- Number of decimals implied by a volume step (0.01 -> 2).
int ApexStepDigits(const double step)
  {
   int d = 0;
   while(d < 8)
     {
      double scaled = step * MathPow(10, d);
      if(MathAbs(scaled - MathRound(scaled)) < 1e-7)
         break;
      d++;
     }
   return d;
  }

//--- Round a volume DOWN to the broker step and clamp to the maximum.
//--- Returns 0 when the result is below the broker minimum: we never round
//--- up to the minimum, because that would exceed the risk budget.
double ApexNormalizeVolumeDown(const double volume, const double minVol, const double maxVol, const double step)
  {
   if(volume <= 0 || step <= 0 || minVol <= 0)
      return 0.0;
   double v = MathFloor(volume / step + 1e-9) * step;
   if(maxVol > 0 && v > maxVol)
      v = MathFloor(maxVol / step + 1e-9) * step;
   v = NormalizeDouble(v, ApexStepDigits(step));
   if(v < minVol - 1e-12)
      return 0.0;
   return v;
  }

//--- Money lost per 1.0 lot if price moves from entry to sl.
double ApexLossPerLot(const string symbol, const int dir, const double entry, const double sl)
  {
   ENUM_ORDER_TYPE type = (dir == APEX_DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double profit = 0.0;
   if(OrderCalcProfit(type, symbol, 1.0, entry, sl, profit) && profit < 0)
      return -profit;
   // Fallback: tick arithmetic in deposit currency.
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0)
      tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0)
      return 0.0;
   return MathAbs(entry - sl) / tickSize * tickValue;
  }

//--- Risk-based volume, rounded down to the broker step. 0 = not tradable.
double ApexCalcVolume(const double riskMoney, const double lossPerLot,
                      const double minVol, const double maxVol, const double step)
  {
   if(riskMoney <= 0 || lossPerLot <= 0)
      return 0.0;
   return ApexNormalizeVolumeDown(riskMoney / lossPerLot, minVol, maxVol, step);
  }

//====================================================================
// SHARED SCORE COMPONENTS (0..1)
//====================================================================
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

//====================================================================
// TRADE RETCODES
//====================================================================
bool ApexRetcodeSuccess(const uint code)
  {
   return (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL ||
           code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES);
  }

//--- Transient conditions worth one more attempt with a fresh price.
bool ApexRetcodeRetryable(const uint code)
  {
   return (code == TRADE_RETCODE_REQUOTE || code == TRADE_RETCODE_PRICE_CHANGED ||
           code == TRADE_RETCODE_PRICE_OFF || code == TRADE_RETCODE_TIMEOUT ||
           code == TRADE_RETCODE_CONNECTION || code == TRADE_RETCODE_TOO_MANY_REQUESTS);
  }

string ApexRetcodeText(const uint code)
  {
   switch(code)
     {
      case TRADE_RETCODE_REQUOTE:           return "requote";
      case TRADE_RETCODE_REJECT:            return "request rejected";
      case TRADE_RETCODE_CANCEL:            return "request canceled";
      case TRADE_RETCODE_PLACED:            return "order placed";
      case TRADE_RETCODE_DONE:              return "done";
      case TRADE_RETCODE_DONE_PARTIAL:      return "done partially";
      case TRADE_RETCODE_ERROR:             return "processing error";
      case TRADE_RETCODE_TIMEOUT:           return "timeout";
      case TRADE_RETCODE_INVALID:           return "invalid request";
      case TRADE_RETCODE_INVALID_VOLUME:    return "invalid volume";
      case TRADE_RETCODE_INVALID_PRICE:     return "invalid price";
      case TRADE_RETCODE_INVALID_STOPS:     return "invalid stops";
      case TRADE_RETCODE_TRADE_DISABLED:    return "trade disabled";
      case TRADE_RETCODE_MARKET_CLOSED:     return "market closed";
      case TRADE_RETCODE_NO_MONEY:          return "insufficient funds";
      case TRADE_RETCODE_PRICE_CHANGED:     return "price changed";
      case TRADE_RETCODE_PRICE_OFF:         return "no quotes";
      case TRADE_RETCODE_INVALID_EXPIRATION:return "invalid expiration";
      case TRADE_RETCODE_ORDER_CHANGED:     return "order changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "too many requests";
      case TRADE_RETCODE_NO_CHANGES:        return "no changes";
      case TRADE_RETCODE_SERVER_DISABLES_AT:return "autotrading disabled by server";
      case TRADE_RETCODE_CLIENT_DISABLES_AT:return "autotrading disabled by client";
      case TRADE_RETCODE_LOCKED:            return "request locked";
      case TRADE_RETCODE_FROZEN:            return "order or position frozen";
      case TRADE_RETCODE_INVALID_FILL:      return "invalid filling type";
      case TRADE_RETCODE_CONNECTION:        return "no connection";
      case TRADE_RETCODE_ONLY_REAL:         return "only real accounts";
      case TRADE_RETCODE_LIMIT_ORDERS:      return "pending order limit";
      case TRADE_RETCODE_LIMIT_VOLUME:      return "volume limit";
      case TRADE_RETCODE_INVALID_ORDER:     return "invalid order type";
      case TRADE_RETCODE_POSITION_CLOSED:   return "position already closed";
     }
   return "retcode " + IntegerToString(code);
  }

//====================================================================
// ACCOUNT / SYMBOL
//====================================================================
bool ApexIsCentCurrency(const string currency)
  {
   return (currency == "USC" || currency == "EUC");
  }

//--- Balance expressed in the account's base (non-cent) currency.
double ApexToMainCurrency(const double amount)
  {
   if(ApexIsCentCurrency(AccountInfoString(ACCOUNT_CURRENCY)))
      return amount / 100.0;
   return amount;
  }

//--- USD exposure of a position: +1 long USD, -1 short USD, 0 no USD leg.
//--- Examples: BUY EURUSD -> -1, BUY USDJPY -> +1, BUY XAUUSD -> -1.
int ApexUsdExposure(const string symbol, const int dir)
  {
   string u = symbol;
   StringToUpper(u);
   if(StringLen(u) < 6)
      return 0;
   string base  = StringSubstr(u, 0, 3);
   string quote = StringSubstr(u, 3, 3);
   if(base == "USD")
      return dir;
   if(quote == "USD")
      return -dir;
   return 0;
  }

//--- Is `magic` in the ApexFlow family that starts at `base`?
bool ApexIsFamilyMagic(const long magic, const long base)
  {
   return (magic >= base && magic < base + APEX_MAGIC_FAMILY_SIZE);
  }

#endif // APEXFLOW_UTILS_MQH
