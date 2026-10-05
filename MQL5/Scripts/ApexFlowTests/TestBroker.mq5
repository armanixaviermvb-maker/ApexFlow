//+------------------------------------------------------------------+
//| TestBroker.mq5 - small-account SYMBOL SCANNER (places no orders)   |
//|                                                                   |
//| For every symbol it reads the live broker specification and asks: |
//| "With X USD, can the SMALLEST possible trade (broker minimum lot) |
//| use a normal ATR stop and stay within the risk limit?"            |
//| Works on cent AND standard accounts. Run it on the account you    |
//| will trade, then attach ApexFlow only to symbols marked TRADABLE. |
//+------------------------------------------------------------------+
#property copyright "ApexFlow"
#property version   "2.00"
#property script_show_inputs

#include "../../Experts/ApexFlow/Utils.mqh"

enum ENUM_SCAN_SCOPE
  {
   SCAN_LIST         = 0, // Only the symbols in the list below
   SCAN_MARKET_WATCH = 1, // All symbols in Market Watch
   SCAN_ALL          = 2  // ALL broker symbols (slow, loads history)
  };

input ENUM_SCAN_SCOPE InpScope     = SCAN_ALL;     // What to scan
input string InpSymbols            = "XAUUSDm,EURUSDm,USDJPYm,GBPUSDm,AUDUSDm,USDCADm"; // List (scope = list)
input double InpBalanceUSD         = 10.0;         // Account size to test, in USD
input double InpRiskPercent        = 1.0;          // Normal risk per trade %
input double InpMaxMinLotRiskPct   = 3.0;          // Max risk % for a minimum-lot trade (EA default 3, hard cap 5)
input ENUM_TIMEFRAMES InpAtrTimeframe = PERIOD_M5; // ATR timeframe (EA entry timeframe)
input int    InpAtrPeriod          = 14;           // ATR period
input double InpStopAtr            = 1.5;          // Typical stop distance in ATR
input double InpMaxCostPct         = 10.0;         // Max spread as % of a 2R target (EA cost filter)
input int    InpShowTop            = 40;           // Print at most this many tradable symbols

struct SScanRow
  {
   string            symbol;
   double            minLot;
   double            minLotRiskPct;   // risk of the broker minimum with the typical stop
   double            costPct;         // spread as % of a 2R target
   double            volume;          // volume ApexFlow would use (0 = refused)
   bool              minLotMode;
   bool              tradable;
   string            reason;
  };

//--- ATR from closed bars (no indicator handle, works for many symbols).
double AtrFromRates(const string sym)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int need = InpAtrPeriod + 2;
   int got = 0;
   for(int tries = 0; tries < 10; tries++)
     {
      got = CopyRates(sym, InpAtrTimeframe, 1, need, r);
      if(got == need)
         break;
      Sleep(200);
     }
   if(got != need)
      return 0;
   double sum = 0;
   for(int i = 0; i < InpAtrPeriod; i++)
      sum += MathMax(r[i].high, r[i + 1].close) - MathMin(r[i].low, r[i + 1].close);
   return sum / InpAtrPeriod;
  }

bool Scan(const string sym, const double equityAcc, SScanRow &row)
  {
   row.symbol = sym;
   row.minLot = 0;
   row.minLotRiskPct = 0;
   row.costPct = 0;
   row.tradable = false;
   row.volume = 0;
   row.minLotMode = false;
   row.reason = "";
   if(!SymbolSelect(sym, true))
     {
      row.reason = "not found";
      return false;
     }
   long mode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
   if(mode != SYMBOL_TRADE_MODE_FULL && mode != SYMBOL_TRADE_MODE_LONGONLY && mode != SYMBOL_TRADE_MODE_SHORTONLY)
     {
      row.reason = "not open for trading";
      return false;
     }
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick) || tick.ask <= 0 || tick.bid <= 0)
     {
      row.reason = "no quote";
      return false;
     }
   double atr = AtrFromRates(sym);
   if(atr <= 0)
     {
      row.reason = "no history";
      return false;
     }
   row.minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double dist   = InpStopAtr * atr;
   double lossPerLot = ApexLossPerLot(sym, APEX_DIR_BUY, tick.ask, tick.ask - dist);
   if(lossPerLot <= 0 || row.minLot <= 0)
     {
      row.reason = "specification unreadable";
      return false;
     }
   row.minLotRiskPct = row.minLot * lossPerLot / equityAcc * 100.0;
   row.costPct = 100.0 * (tick.ask - tick.bid) / (2.0 * dist);
   double pct = 0;
   bool ok = ApexSizePosition(equityAcc, InpRiskPercent, lossPerLot, row.minLot, maxVol, step,
                              true, MathMin(InpMaxMinLotRiskPct, APEX_HARD_MAX_MINLOT_RISK_PCT),
                              row.volume, row.minLotMode, pct);
   double margin = 0;
   if(ok && OrderCalcMargin(ORDER_TYPE_BUY, sym, row.volume, tick.ask, margin) && margin > equityAcc * 0.5)
     {
      ok = false;
      row.reason = StringFormat("margin %.2f > 50%% of balance", margin);
     }
   if(ok && row.costPct > InpMaxCostPct)
     {
      ok = false;
      row.reason = StringFormat("spread %.0f%% of target", row.costPct);
     }
   if(!ok && row.reason == "")
      row.reason = StringFormat("smallest trade risks %.1f%%", row.minLotRiskPct);
   row.tradable = ok;
   return ok;
  }

void OnStart()
  {
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   bool cent = ApexIsCentCurrency(cur);
   double equityAcc = cent ? InpBalanceUSD * 100.0 : InpBalanceUSD;
   PrintFormat("[SCAN] account=%s (%s) test balance=%.2f USD = %.2f %s, risk %.1f%% (min-lot limit %.1f%%), stop %.1f x ATR(%s)",
               (cent ? "CENT" : "STANDARD"), cur, InpBalanceUSD, equityAcc, cur, InpRiskPercent,
               InpMaxMinLotRiskPct, InpStopAtr, EnumToString(InpAtrTimeframe));

   string names[];
   int n = 0;
   if(InpScope == SCAN_LIST)
      n = StringSplit(InpSymbols, ',', names);
   else
     {
      bool watchOnly = (InpScope == SCAN_MARKET_WATCH);
      n = SymbolsTotal(watchOnly);
      ArrayResize(names, n);
      for(int i = 0; i < n; i++)
         names[i] = SymbolName(i, watchOnly);
     }

   SScanRow rows[];
   int tradable = 0, scanned = 0;
   for(int i = 0; i < n; i++)
     {
      string sym = names[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(sym == "")
         continue;
      if(IsStopped())
         break;
      SScanRow row;
      Scan(sym, equityAcc, row);
      scanned++;
      int k = ArraySize(rows);
      ArrayResize(rows, k + 1);
      rows[k] = row;
      if(row.tradable)
         tradable++;
      if(InpScope == SCAN_LIST)
         PrintFormat("[SCAN] %-12s %s | min lot %.2f risks %.2f%% | spread %.0f%% of target | %s",
                     sym, (row.tradable ? (row.minLotMode ? "TRADABLE (min-lot mode)" : "TRADABLE") : "NOT TRADABLE"),
                     row.minLot, row.minLotRiskPct, row.costPct,
                     (row.tradable ? StringFormat("volume %.2f", row.volume) : row.reason));
     }

   // Sort: tradable first, then lowest min-lot risk.
   int total = ArraySize(rows);
   for(int a = 0; a < total; a++)
      for(int b = a + 1; b < total; b++)
        {
         bool swap = (!rows[a].tradable && rows[b].tradable) ||
                     (rows[a].tradable == rows[b].tradable && rows[b].minLotRiskPct < rows[a].minLotRiskPct);
         if(swap)
           {
            SScanRow t = rows[a];
            rows[a] = rows[b];
            rows[b] = t;
           }
        }
   if(InpScope != SCAN_LIST)
     {
      int shown = 0;
      for(int i = 0; i < total && rows[i].tradable && shown < InpShowTop; i++)
        {
         shown++;
         PrintFormat("[SCAN] #%d %-14s TRADABLE%s | min lot %.2f risks %.2f%% | spread %.0f%% of target | volume %.2f",
                     shown, rows[i].symbol, (rows[i].minLotMode ? " (min-lot mode)" : ""), rows[i].minLot,
                     rows[i].minLotRiskPct, rows[i].costPct, rows[i].volume);
        }
     }
   PrintFormat("[SCAN] summary: %d of %d symbols can take a stop-protected trade at %.2f USD within %.1f%% risk. " +
               "Attach ApexFlow only to TRADABLE symbols; symbols outside the tested set must be backtested first.",
               tradable, scanned, InpBalanceUSD, InpMaxMinLotRiskPct);
  }
