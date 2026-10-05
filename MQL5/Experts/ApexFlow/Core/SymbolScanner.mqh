//+------------------------------------------------------------------+
//| SymbolScanner.mqh - automatic symbol selection                    |
//|                                                                   |
//| Scans the broker's symbols a few at a time (timer driven, so the  |
//| terminal stays responsive), and scores every symbol that can      |
//| carry a stop-protected trade within the account's risk limits:    |
//|                                                                   |
//|   35  cost      spread as a share of the target (cheaper = better)|
//|   20  volatility ATR percentile inside the tradable band          |
//|   20  trend     H1 efficiency ratio (clean moves give more setups)|
//|   10  sizing    normal 1x-risk sizing (vs. minimum-lot mode)      |
//|   15  familiar  forex majors / metals the strategies were built on|
//|                                                                   |
//| Hard gates (never scored around): trade mode, fresh quote,        |
//| position size within risk limits, margin, cost filter, synthetic  |
//| indices excluded. Several ApexFlow charts never pick the same     |
//| symbol: each chart claims its symbol in a terminal global variable.|
//+------------------------------------------------------------------+
#ifndef APEXFLOW_SYMBOLSCANNER_MQH
#define APEXFLOW_SYMBOLSCANNER_MQH

#include "../Config.mqh"
#include "../Utils.mqh"

#define APEX_CLAIM_TTL_SEC 300

struct SSymbolScore
  {
   string            symbol;
   bool              tradable;
   double            score;          // 0..100
   double            costPct;        // spread as % of the target distance
   double            minLotRiskPct;  // risk of the broker minimum with a typical stop
   double            atrPercentile;
   double            trend;          // efficiency ratio 0..1
   bool              minLotMode;
   bool              preferred;
   string            reason;         // why not tradable
  };

//====================================================================
// PURE HELPERS (unit-tested)
//====================================================================
bool ApexIsSyntheticSymbol(const string name, const string path)
  {
   string n = name, p = path;
   StringToUpper(n);
   StringToUpper(p);
   string keys[] = {"SYNTHETIC", "DERIVED", "VOLATILITY", "CRASH", "BOOM", "STEP INDEX", "JUMP", "RANGE BREAK", "DRIFT", "DEX "};
   for(int i = 0; i < ArraySize(keys); i++)
      if(StringFind(n, keys[i]) >= 0 || StringFind(p, keys[i]) >= 0)
         return true;
   return false;
  }

bool ApexIsPreferredSymbol(const string name)
  {
   string u = name;
   StringToUpper(u);
   string pref[] = {"XAUUSD", "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF", "NZDUSD", "XAGUSD"};
   for(int i = 0; i < ArraySize(pref); i++)
      if(StringFind(u, pref[i]) == 0)
         return true;
   return false;
  }

bool ApexIsCurrencyCode(const string code)
  {
   string iso[] = {"USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF", "SEK", "NOK", "DKK", "SGD", "HKD",
                   "ZAR", "MXN", "PLN", "HUF", "CZK", "TRY", "CNH", "XAU", "XAG", "XPT", "XPD"
                  };
   for(int i = 0; i < ArraySize(iso); i++)
      if(code == iso[i])
         return true;
   return false;
  }

//--- Forex pair or spot metal, judged from the name (BASEQUOTE + optional suffix) or the symbol path.
bool ApexIsForexOrMetal(const string name, const string path)
  {
   string u = name, p = path;
   StringToUpper(u);
   StringToUpper(p);
   if(StringFind(p, "FOREX") >= 0 || StringFind(p, "METAL") >= 0)
      return true;
   if(StringLen(u) < 6)
      return false;
   return ApexIsCurrencyCode(StringSubstr(u, 0, 3)) && ApexIsCurrencyCode(StringSubstr(u, 3, 3));
  }

//--- |net move| / sum of |bar-to-bar moves| over `bars` closes (series, 0 = newest). 1 = straight line.
double ApexEfficiencyRatio(const MqlRates &r[], const int bars)
  {
   int n = (int)MathMin(bars, ArraySize(r) - 1);
   if(n < 2)
      return 0.0;
   double path = 0;
   for(int i = 0; i < n; i++)
      path += MathAbs(r[i].close - r[i + 1].close);
   if(path <= 0)
      return 0.0;
   return MathAbs(r[0].close - r[n].close) / path;
  }

double ApexOpportunityScore(const double costPct, const double maxCostPct, const double volScore,
                            const double trend, const bool normalSizing, const bool preferred)
  {
   double cost = (maxCostPct > 0) ? ApexClamp(1.0 - costPct / maxCostPct, 0, 1) : ApexClamp(1.0 - costPct / 20.0, 0, 1);
   return 35.0 * cost + 20.0 * ApexClamp(volScore, 0, 1) + 20.0 * ApexClamp(trend, 0, 1) +
          10.0 * (normalSizing ? 1.0 : 0.5) + 15.0 * (preferred ? 1.0 : 0.0);
  }

//====================================================================
// SCANNER
//====================================================================
class CSymbolScanner
  {
private:
   SApexConfig       m_cfg;
   string            m_queue[];
   int               m_next;
   bool              m_active;
   SSymbolScore      m_rows[];

   string            ClaimName(const string sym) const { return "AF." + IntegerToString(m_cfg.magicBase) + ".CLAIM." + sym; }
   string            ClaimTimeName(const string sym) const { return "AF." + IntegerToString(m_cfg.magicBase) + ".CLAIMT." + sym; }

   bool              InUniverse(const string sym) const
     {
      string path = SymbolInfoString(sym, SYMBOL_PATH);
      if(ApexIsSyntheticSymbol(sym, path))
         return false;
      if(m_cfg.autoUniverse == APEX_UNIVERSE_PREFERRED)
         return ApexIsPreferredSymbol(sym);
      if(m_cfg.autoUniverse == APEX_UNIVERSE_FOREX_METALS)
         return ApexIsForexOrMetal(sym, path);
      return true;
     }

   void              Evaluate(const string sym, SSymbolScore &row)
     {
      row.symbol = sym;
      row.tradable = false;
      row.score = 0;
      row.costPct = 0;
      row.minLotRiskPct = 0;
      row.atrPercentile = 0;
      row.trend = 0;
      row.minLotMode = false;
      row.preferred = ApexIsPreferredSymbol(sym);
      row.reason = "";

      if(!SymbolSelect(sym, true))
        {
         row.reason = "cannot select";
         return;
        }
      MqlTick tick;
      if(!SymbolInfoTick(sym, tick) || tick.ask <= 0 || tick.bid <= 0)
        {
         row.reason = "no quote";
         return;
        }
      if((long)TimeTradeServer() - (long)tick.time > 600)
        {
         row.reason = "market closed / stale quote";
         return;
        }
      // Entry-timeframe ATR and its percentile, from closed bars only.
      int period = m_cfg.atrPeriod, look = m_cfg.atrPctLookback;
      int need = look + period + 2;
      MqlRates r[];
      ArraySetAsSeries(r, true);
      if(CopyRates(sym, m_cfg.tfEntry, 1, need, r) != need)
        {
         row.reason = "history loading";
         return;
        }
      double tr[];
      ArrayResize(tr, need - 1);
      for(int i = 0; i < need - 1; i++)
         tr[i] = MathMax(r[i].high, r[i + 1].close) - MathMin(r[i].low, r[i + 1].close);
      double atrs[];
      ArrayResize(atrs, look + 1);
      for(int j = 0; j <= look; j++)
        {
         double s = 0;
         for(int k = 0; k < period; k++)
            s += tr[j + k];
         atrs[j] = s / period;
        }
      double atr = atrs[0];
      if(atr <= 0)
        {
         row.reason = "no volatility";
         return;
        }
      row.atrPercentile = ApexPercentileRank(atrs, 1, look, atr);

      MqlRates h[];
      ArraySetAsSeries(h, true);
      if(CopyRates(sym, m_cfg.tfContext, 1, 25, h) == 25)
         row.trend = ApexEfficiencyRatio(h, 24);

      // Can the account carry a stop-protected trade here?
      double dist = ApexClamp(m_cfg.stopATRMult, m_cfg.minStopATR, m_cfg.maxStopATR) * atr;
      double lossPerLot = ApexLossPerLot(sym, APEX_DIR_BUY, tick.ask, tick.ask - dist);
      double minVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double maxVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(lossPerLot <= 0 || minVol <= 0 || equity <= 0)
        {
         row.reason = "specification unreadable";
         return;
        }
      row.minLotRiskPct = minVol * lossPerLot / equity * 100.0;
      double vol = 0, pct = 0;
      bool minLot = false;
      if(!ApexSizePosition(equity, m_cfg.riskPct, lossPerLot, minVol, maxVol, step,
                           m_cfg.allowMinLotRisk, m_cfg.maxMinLotRiskPct, vol, minLot, pct))
        {
         row.reason = StringFormat("smallest trade risks %.1f%%", row.minLotRiskPct);
         return;
        }
      row.minLotMode = minLot;
      double margin = 0;
      if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, vol, tick.ask, margin) ||
         margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * m_cfg.maxMarginUsePct / 100.0)
        {
         row.reason = "not enough free margin";
         return;
        }
      double targetDist = (m_cfg.tpMode == APEX_TP_ATR) ? m_cfg.tpATR * atr : dist * m_cfg.tpR;
      row.costPct = ApexCostPctOfTarget(tick.ask - tick.bid, tick.ask, tick.ask + targetDist);
      if(m_cfg.maxCostPctOfTarget > 0 && row.costPct > m_cfg.maxCostPctOfTarget)
        {
         row.reason = StringFormat("spread %.0f%% of target", row.costPct);
         return;
        }
      double volScore = ApexVolatilityScore(row.atrPercentile, m_cfg.atrPctMin, m_cfg.atrPctMax);
      row.score = ApexOpportunityScore(row.costPct, m_cfg.maxCostPctOfTarget, volScore, row.trend, !minLot, row.preferred);
      row.tradable = true;
     }

public:
                     CSymbolScanner(void) : m_next(0), m_active(false) {}

   void              SetConfig(const SApexConfig &c) { m_cfg = c; }
   bool              Active(void) const { return m_active; }
   int               Total(void) const { return ArraySize(m_queue); }
   int               Done(void) const { return m_next; }

   //--- Build the candidate list (cheap checks only) and start scanning.
   void              Begin(const SApexConfig &c)
     {
      m_cfg = c;
      ArrayResize(m_queue, 0);
      ArrayResize(m_rows, 0);
      m_next = 0;
      int total = SymbolsTotal(false);
      for(int i = 0; i < total; i++)
        {
         string sym = SymbolName(i, false);
         if(sym == "" || !InUniverse(sym) || IsClaimedByOther(sym))
            continue;
         long mode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
         if(mode != SYMBOL_TRADE_MODE_FULL)
            continue;
         int k = ArraySize(m_queue);
         ArrayResize(m_queue, k + 1);
         m_queue[k] = sym;
        }
      m_active = (ArraySize(m_queue) > 0);
      ApexLog(APEX_LOG_INFO, "AUTO_SYMBOL_SCAN_STARTED",
              StringFormat("CANDIDATES=%d UNIVERSE=%s", ArraySize(m_queue), EnumToString(c.autoUniverse)));
     }

   //--- Evaluate up to `count` symbols. Returns true when the scan is complete.
   bool              Step(const int count)
     {
      if(!m_active)
         return true;
      for(int i = 0; i < count && m_next < ArraySize(m_queue); i++, m_next++)
        {
         SSymbolScore row;
         Evaluate(m_queue[m_next], row);
         int k = ArraySize(m_rows);
         ArrayResize(m_rows, k + 1);
         m_rows[k] = row;
        }
      if(m_next >= ArraySize(m_queue))
         m_active = false;
      return !m_active;
     }

   bool              Best(SSymbolScore &best) const
     {
      int b = -1;
      for(int i = 0; i < ArraySize(m_rows); i++)
         if(m_rows[i].tradable && !IsClaimedByOther(m_rows[i].symbol) && (b < 0 || m_rows[i].score > m_rows[b].score))
            b = i;
      if(b < 0)
         return false;
      best = m_rows[b];
      return true;
     }

   //--- Score of a symbol in the last scan (-1 = not tradable / not scanned).
   double            ScoreOf(const string sym) const
     {
      for(int i = 0; i < ArraySize(m_rows); i++)
         if(m_rows[i].symbol == sym)
            return m_rows[i].tradable ? m_rows[i].score : -1.0;
      return -1.0;
     }

   //--- e.g. "EURUSDc 84, GBPUSDc 77, USDJPYc 71 | 12 tradable of 58"
   string            Summary(const int topN) const
     {
      bool used[];
      int n = ArraySize(m_rows), tradable = 0;
      ArrayResize(used, n);
      for(int i = 0; i < n; i++)
        {
         used[i] = false;
         if(m_rows[i].tradable)
            tradable++;
        }
      string s = "";
      for(int t = 0; t < topN; t++)
        {
         int b = -1;
         for(int i = 0; i < n; i++)
            if(!used[i] && m_rows[i].tradable && (b < 0 || m_rows[i].score > m_rows[b].score))
               b = i;
         if(b < 0)
            break;
         used[b] = true;
         s += (s == "" ? "" : ", ") + StringFormat("%s %.0f", m_rows[b].symbol, m_rows[b].score);
        }
      return (s == "" ? "none" : s) + StringFormat(" | %d tradable of %d", tradable, n);
     }

   //--- Most common reason symbols were rejected (for the "nothing tradable" case).
   string            TopRejectReason(void) const
     {
      string reasons[];
      int counts[];
      for(int i = 0; i < ArraySize(m_rows); i++)
        {
         if(m_rows[i].tradable)
            continue;
         string key = m_rows[i].reason;
         string group = (StringFind(key, "smallest trade") == 0) ? "smallest trade too risky" : key;
         int k = -1;
         for(int j = 0; j < ArraySize(reasons); j++)
            if(reasons[j] == group)
               k = j;
         if(k < 0)
           {
            k = ArraySize(reasons);
            ArrayResize(reasons, k + 1);
            ArrayResize(counts, k + 1);
            reasons[k] = group;
            counts[k] = 0;
           }
         counts[k]++;
        }
      int b = -1;
      for(int j = 0; j < ArraySize(reasons); j++)
         if(b < 0 || counts[j] > counts[b])
            b = j;
      return (b < 0) ? "none" : StringFormat("%s (%d symbols)", reasons[b], counts[b]);
     }

   //--- Chart claims so several ApexFlow charts never trade the same symbol.
   bool              IsClaimedByOther(const string sym) const
     {
      string n = ClaimName(sym), t = ClaimTimeName(sym);
      if(!GlobalVariableCheck(n) || !GlobalVariableCheck(t))
         return false;
      if((long)GlobalVariableGet(n) == ChartID())
         return false;
      return ((long)TimeCurrent() - (long)GlobalVariableGet(t) < APEX_CLAIM_TTL_SEC);
     }

   void              Claim(const SApexConfig &c, const string sym)
     {
      m_cfg = c;
      GlobalVariableSet(ClaimName(sym), (double)ChartID());
      GlobalVariableSet(ClaimTimeName(sym), (double)TimeCurrent());
     }

   void              ReleaseClaim(const SApexConfig &c, const string sym)
     {
      m_cfg = c;
      if(GlobalVariableCheck(ClaimName(sym)) && (long)GlobalVariableGet(ClaimName(sym)) == ChartID())
        {
         GlobalVariableDel(ClaimName(sym));
         GlobalVariableDel(ClaimTimeName(sym));
        }
     }
  };

#endif // APEXFLOW_SYMBOLSCANNER_MQH
