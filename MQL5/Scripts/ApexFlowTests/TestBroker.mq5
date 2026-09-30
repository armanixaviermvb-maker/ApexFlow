//+------------------------------------------------------------------+
//| TestBroker.mq5 - micro-account / broker feasibility check          |
//|                                                                   |
//| For each symbol, reads the live broker specification and answers:|
//| "Can an account of X USD open a valid, risk-controlled position?" |
//| Uses the same sizing math as the EA. Places NO orders.            |
//| Run on a chart of the broker you will trade (Exness / Deriv).     |
//+------------------------------------------------------------------+
#property copyright "ApexFlow"
#property version   "1.00"
#property script_show_inputs

#include "../../Experts/ApexFlow/Utils.mqh"

input string InpSymbols      = "XAUUSDm,EURUSDm,USDJPYm,GBPUSDm"; // Symbols (comma separated, exact broker names)
input double InpBalanceUSD   = 3.0;          // Account size to test, in USD
input double InpRiskPercent  = 1.0;          // Risk per trade %
input ENUM_TIMEFRAMES InpAtrTimeframe = PERIOD_M5; // ATR timeframe (EA entry timeframe)
input int    InpAtrPeriod    = 14;           // ATR period
input double InpStopAtr      = 1.5;          // Typical stop distance in ATR

double ReadAtr(const string sym)
  {
   int h = iATR(sym, InpAtrTimeframe, InpAtrPeriod);
   if(h == INVALID_HANDLE)
      return 0;
   double buf[];
   for(int i = 0; i < 50 && BarsCalculated(h) <= 0; i++)
      Sleep(100);
   double v = 0;
   if(CopyBuffer(h, 0, 1, 1, buf) == 1)
      v = buf[0];
   IndicatorRelease(h);
   return v;
  }

void OnStart()
  {
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   bool cent = ApexIsCentCurrency(cur);
   double balanceAcc = cent ? InpBalanceUSD * 100.0 : InpBalanceUSD;
   double budget = balanceAcc * InpRiskPercent / 100.0;
   PrintFormat("[BROKER] account currency=%s%s test balance=%.2f %s risk=%.2f%% budget=%.4f %s leverage=1:%I64d margin_mode=%s",
               cur, (cent ? " (cent)" : ""), balanceAcc, cur, InpRiskPercent, budget, cur,
               AccountInfoInteger(ACCOUNT_LEVERAGE),
               (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "HEDGING" : "NETTING"));
   if(!cent && InpBalanceUSD < 50)
      Print("[BROKER] note: this is a standard (non-cent) account. Small balances usually cannot meet the minimum lot at 1% risk.");

   string list[];
   int n = StringSplit(InpSymbols, ',', list);
   int tradable = 0;
   for(int i = 0; i < n; i++)
     {
      string sym = list[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(sym == "")
         continue;
      if(!SymbolSelect(sym, true))
        {
         PrintFormat("[BROKER] %s: NOT FOUND at this broker (check the exact name/suffix in Market Watch)", sym);
         continue;
        }
      MqlTick tick;
      if(!SymbolInfoTick(sym, tick) || tick.ask <= 0)
        {
         PrintFormat("[BROKER] %s: no quote (market closed or symbol disabled)", sym);
         continue;
        }
      double minVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double maxVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      double atr    = ReadAtr(sym);
      if(atr <= 0)
        {
         PrintFormat("[BROKER] %s: ATR unavailable (open a %s chart once to load history, then rerun)", sym, EnumToString(InpAtrTimeframe));
         continue;
        }
      double dist = InpStopAtr * atr;
      double lossPerLot = ApexLossPerLot(sym, APEX_DIR_BUY, tick.ask, tick.ask - dist);
      double minRisk = lossPerLot * minVol;
      double vol = ApexCalcVolume(budget, lossPerLot, minVol, maxVol, step);
      double margin = 0;
      bool marginOk = OrderCalcMargin(ORDER_TYPE_BUY, sym, minVol, tick.ask, margin);
      double needBalance = (InpRiskPercent > 0) ? minRisk / (InpRiskPercent / 100.0) : 0;
      bool ok = (vol > 0) && marginOk && margin <= balanceAcc * 0.5;
      if(ok)
         tradable++;
      PrintFormat("[BROKER] %s: %s | min_lot=%.2f step=%.2f spread=%.0fpts stops_level=%I64d ATR=%.0fpts stop=%.0fpts " +
                  "loss@min_lot=%.4f %s budget=%.4f -> volume=%.2f margin@min_lot=%.2f needs_balance~%.2f %s",
                  sym, (ok ? "TRADABLE" : "INSUFFICIENT CAPITAL FOR VALID TRADE"), minVol, step,
                  (tick.ask - tick.bid) / point, SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL),
                  atr / point, dist / point, minRisk, cur, budget, vol, margin, needBalance, cur);
     }
   PrintFormat("[BROKER] summary: %d of %d symbols can carry a valid %.1f%%-risk position at %.2f USD. " +
               "The EA refuses the others (it never rounds up to the minimum lot).",
               tradable, n, InpRiskPercent, InpBalanceUSD);
  }
