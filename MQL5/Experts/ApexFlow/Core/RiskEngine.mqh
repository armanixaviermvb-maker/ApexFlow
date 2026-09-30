//+------------------------------------------------------------------+
//| RiskEngine.mqh - every check between a signal and an order        |
//|                                                                   |
//| Signal -> Risk -> Execution validation -> Order. Nothing reaches  |
//| the OrderManager without a valid STradePlan from this engine.     |
//|                                                                   |
//| Sizing is fixed-fractional on equity with a hard cap. There is no |
//| martingale, no loss-based scaling and no target-based scaling:    |
//| RiskPerTradePercent is the only input to the risk budget.         |
//| Volume is always rounded DOWN; if the broker minimum would exceed |
//| the budget the answer is NO TRADE (insufficient_capital).         |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_RISKENGINE_MQH
#define APEXFLOW_RISKENGINE_MQH

#include "../Config.mqh"
#include "../Utils.mqh"
#include "CircuitBreaker.mqh"
#include "NewsFilter.mqh"
#include "../Indicators/ATRHelper.mqh"

//====================================================================
// PURE HELPERS (unit-tested)
//====================================================================

//--- Final stop-loss price, or 0 with `rej` set when no valid stop exists.
double ApexComputeStop(const int dir, const double entry, const double structuralStop,
                       const double atr, const SApexConfig &c, ENUM_APEX_REJECT &rej)
  {
   rej = APEX_REJECT_NONE;
   if(atr <= 0 || entry <= 0 || (dir != APEX_DIR_BUY && dir != APEX_DIR_SELL))
     {
      rej = APEX_REJECT_INVALID_STOP;
      return 0.0;
     }
   double sl = 0.0;
   if(c.stopMode == APEX_STOP_ATR)
      sl = entry - dir * c.stopATRMult * atr;
   else
     {
      if(structuralStop <= 0)
        {
         rej = APEX_REJECT_INVALID_STOP;
         return 0.0;
        }
      sl = structuralStop;
      double d0 = (entry - sl) * dir;
      if(c.stopMode == APEX_STOP_HYBRID && d0 > 0 && d0 < c.minStopATR * atr)
         sl = entry - dir * c.minStopATR * atr;
     }
   double dist = (entry - sl) * dir;
   if(dist <= 0)
     {
      rej = APEX_REJECT_INVALID_STOP;   // stop on the wrong side of entry
      return 0.0;
     }
   if(dist > c.maxStopATR * atr)
     {
      rej = APEX_REJECT_STOP_TOO_WIDE;
      return 0.0;
     }
   if(c.stopMode == APEX_STOP_STRUCTURE && dist < c.minStopATR * atr)
     {
      rej = APEX_REJECT_INVALID_STOP;   // structure too tight: noise would stop it out
      return 0.0;
     }
   return sl;
  }

//--- Take-profit price.
double ApexComputeTakeProfit(const int dir, const double entry, const double sl, const double atr,
                             const SLiquidityState &liq, const SStructureState &st, const SApexConfig &c)
  {
   double r = MathAbs(entry - sl);
   double fixedR = entry + dir * r * c.tpR;
   if(c.tpMode == APEX_TP_ATR && atr > 0)
      return entry + dir * c.tpATR * atr;
   if(c.tpMode == APEX_TP_STRUCTURE)
     {
      double levels[3];
      if(dir == APEX_DIR_BUY)
        {
         levels[0] = liq.pdh;
         levels[1] = liq.sessionHigh;
         levels[2] = st.valid ? st.lastHigh : 0.0;
        }
      else
        {
         levels[0] = liq.pdl;
         levels[1] = liq.sessionLow;
         levels[2] = st.valid ? st.lastLow : 0.0;
        }
      double best = 0.0;
      for(int i = 0; i < 3; i++)
        {
         double lv = levels[i];
         if(lv <= 0)
            continue;
         double dist = (lv - entry) * dir;
         if(dist < r)            // target must be at least 1R away
            continue;
         if(best == 0.0 || MathAbs(lv - entry) < MathAbs(best - entry))
            best = lv;
        }
      if(best > 0)
         return best;
     }
   return fixedR;
  }

//====================================================================
// ENGINE
//====================================================================
class CRiskEngine
  {
private:
   SApexConfig       m_cfg;
   datetime          m_dayStart;
   double            m_dayStartBalance;
   double            m_realizedMine;
   double            m_realizedFamily;
   int               m_consecutiveLosses;
   datetime          m_lossResetTime;
   string            m_gvReset;
   bool              m_microChecked;
   bool              m_microFeasible;
   double            m_microMinRisk;
   double            m_microBudget;
   double            m_microRequiredEquity;
   string            m_microDetail;

   bool              IsMine(const long magic, const string symbol) const
     {
      return (magic == m_cfg.magic && symbol == m_cfg.symbol);
     }

   bool              Reject(ENUM_APEX_REJECT &rej, string &detail, const ENUM_APEX_REJECT r, const string d) const
     {
      rej = r;
      detail = d;
      return false;
     }

public:
                     CRiskEngine(void) : m_dayStart(0), m_dayStartBalance(0), m_realizedMine(0), m_realizedFamily(0),
                     m_consecutiveLosses(0), m_lossResetTime(0), m_gvReset(""), m_microChecked(false),
                     m_microFeasible(true), m_microMinRisk(0), m_microBudget(0), m_microRequiredEquity(0),
                     m_microDetail("") {}

   void              Init(const SApexConfig &c)
     {
      m_cfg = c;
      m_gvReset = "AF." + IntegerToString(c.magic) + ".LSRESET";
      if(c.resetLossStreak)
        {
         GlobalVariableSet(m_gvReset, (double)TimeCurrent());
         ApexLog(APEX_LOG_INFO, "LOSS_STREAK_RESET", "SYMBOL=" + c.symbol + " manual reset requested");
        }
      if(GlobalVariableCheck(m_gvReset))
         m_lossResetTime = (datetime)(long)GlobalVariableGet(m_gvReset);
      RefreshHistory();
     }

   //--- Rebuild today's realized P/L and the loss streak from broker history.
   //--- Returns true when a new trading day started.
   bool              RefreshHistory(void)
     {
      datetime now = TimeCurrent();
      datetime day = ApexDayStart(now);
      bool newDay = (m_dayStart != 0 && day != m_dayStart);
      m_dayStart = day;

      m_realizedMine = 0;
      m_realizedFamily = 0;
      double realizedAll = 0;

      ulong    ids[];
      double   pnl[];
      datetime closeT[];
      int      np = 0;

      if(!HistorySelect(day - 30 * 86400, now + 86400))
        {
         ApexLogError("CRiskEngine::RefreshHistory", m_cfg.symbol, "HistorySelect", GetLastError(), "history unavailable");
         return newDay;
        }
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0)
            continue;
         long type = HistoryDealGetInteger(t, DEAL_TYPE);
         if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
            continue; // balance, credit, bonus... are not trading results
         double v = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) +
                    HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_FEE);
         datetime dt  = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
         long magic   = HistoryDealGetInteger(t, DEAL_MAGIC);
         string sym   = HistoryDealGetString(t, DEAL_SYMBOL);
         long entry   = HistoryDealGetInteger(t, DEAL_ENTRY);
         bool mine    = IsMine(magic, sym);
         if(dt >= day)
           {
            realizedAll += v;
            if(ApexIsFamilyMagic(magic, m_cfg.magicBase))
               m_realizedFamily += v;
            if(mine)
               m_realizedMine += v;
           }
         if(!mine)
            continue;
         ulong pid = (ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID);
         int k = -1;
         for(int j = 0; j < np; j++)
            if(ids[j] == pid)
              {
               k = j;
               break;
              }
         if(k < 0)
           {
            np++;
            ArrayResize(ids, np);
            ArrayResize(pnl, np);
            ArrayResize(closeT, np);
            k = np - 1;
            ids[k] = pid;
            pnl[k] = 0;
            closeT[k] = 0;
           }
         pnl[k] += v;
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
            closeT[k] = dt;
        }
      m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE) - realizedAll;
      if(m_dayStartBalance <= 0)
         m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Consecutive losses: fully closed positions, newest first.
      datetime boundary = (m_cfg.lossStreakReset == APEX_RESET_NEW_DAY) ? day : m_lossResetTime;
      int streak = 0;
      bool used[];
      ArrayResize(used, np);
      for(int j = 0; j < np; j++)
         used[j] = false;
      while(true)
        {
         int newest = -1;
         for(int j = 0; j < np; j++)
           {
            if(used[j] || closeT[j] == 0 || closeT[j] < boundary)
               continue;
            if(PositionSelectByTicket(ids[j]))
               continue; // still open (partially closed)
            if(newest < 0 || closeT[j] > closeT[newest])
               newest = j;
           }
         if(newest < 0)
            break;
         used[newest] = true;
         if(pnl[newest] < 0)
            streak++;
         else
            break;
        }
      m_consecutiveLosses = streak;
      return newDay;
     }

   //--- Scan open positions (fast, no history access).
   void              ScanPositions(const int dir, int &mine, int &family, bool &opposite,
                                   bool &usdConflict, bool &foreignOnSymbol,
                                   double &floatMine, double &floatFamily) const
     {
      mine = 0;
      family = 0;
      opposite = false;
      usdConflict = false;
      foreignOnSymbol = false;
      floatMine = 0;
      floatFamily = 0;
      int newExposure = ApexUsdExposure(m_cfg.symbol, dir);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0)
            continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         string sym = PositionGetString(POSITION_SYMBOL);
         int pdir   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? APEX_DIR_BUY : APEX_DIR_SELL;
         double pl  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(sym == m_cfg.symbol && !IsMine(magic, sym))
            foreignOnSymbol = true;
         if(!ApexIsFamilyMagic(magic, m_cfg.magicBase))
            continue;
         family++;
         floatFamily += pl;
         if(IsMine(magic, sym))
           {
            mine++;
            floatMine += pl;
            if(dir != APEX_DIR_NONE && pdir != dir)
               opposite = true;
           }
         else
            if(m_cfg.blockCorrelatedSameDir && sym != m_cfg.symbol && dir != APEX_DIR_NONE)
              {
               int e = ApexUsdExposure(sym, pdir);
               if(e != 0 && e == newExposure)
                  usdConflict = true;
              }
        }
     }

   double            DayStartBalance(void) const { return m_dayStartBalance; }
   int               ConsecutiveLosses(void) const { return m_consecutiveLosses; }

   //--- Today's P/L for this chart (realized + floating).
   double            DailyPnL(void) const
     {
      int a, b;
      bool c1, c2, c3;
      double fm, ff;
      ScanPositions(APEX_DIR_NONE, a, b, c1, c2, c3, fm, ff);
      return m_realizedMine + fm;
     }

   //--- Update the loss-limit breakers. Called on timer and before entries.
   void              UpdateLossBreakers(CCircuitBreaker &brk) const
     {
      int a, b;
      bool c1, c2, c3;
      double fm, ff;
      ScanPositions(APEX_DIR_NONE, a, b, c1, c2, c3, fm, ff);
      double base = MathMax(m_dayStartBalance, 1e-9);
      double lossMine = -(m_realizedMine + fm) / base * 100.0;
      double lossFamily = -(m_realizedFamily + ff) / base * 100.0;
      if(lossMine >= m_cfg.maxDailyLossPct)
         brk.Trip(APEX_BRK_DAILY_LOSS, StringFormat("daily loss %.2f%% >= %.2f%%", lossMine, m_cfg.maxDailyLossPct), true);
      if(lossFamily >= m_cfg.maxAccountDailyLossPct)
         brk.Trip(APEX_BRK_ACCOUNT_DAILY_LOSS, StringFormat("account daily loss %.2f%% >= %.2f%%", lossFamily, m_cfg.maxAccountDailyLossPct), true);
      if(m_consecutiveLosses >= m_cfg.maxConsecutiveLosses)
         brk.Trip(APEX_BRK_LOSS_STREAK, StringFormat("%d consecutive losses", m_consecutiveLosses), false);
      else
         brk.Set(APEX_BRK_LOSS_STREAK, false, "");
     }

   //--- Can this broker/symbol carry a valid, risk-controlled position at all?
   bool              CheckMicroAccount(const double atr)
     {
      if(atr <= 0)
         return m_microFeasible;
      MqlTick tick;
      if(!SymbolInfoTick(m_cfg.symbol, tick) || tick.ask <= 0)
         return m_microFeasible;
      double k = ApexClamp(m_cfg.stopATRMult, m_cfg.minStopATR, m_cfg.maxStopATR);
      double dist = k * atr;
      double lossPerLot = ApexLossPerLot(m_cfg.symbol, APEX_DIR_BUY, tick.ask, tick.ask - dist);
      double minVol = SymbolInfoDouble(m_cfg.symbol, SYMBOL_VOLUME_MIN);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_microBudget  = equity * m_cfg.riskPct / 100.0;
      m_microMinRisk = lossPerLot * minVol;
      m_microRequiredEquity = (m_cfg.riskPct > 0) ? m_microMinRisk / (m_cfg.riskPct / 100.0) : 0;
      bool feasible = (lossPerLot > 0 && minVol > 0 && m_microMinRisk <= m_microBudget);
      double margin = 0;
      if(feasible && OrderCalcMargin(ORDER_TYPE_BUY, m_cfg.symbol, minVol, tick.ask, margin))
         if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * m_cfg.maxMarginUsePct / 100.0)
            feasible = false;
      m_microDetail = StringFormat("min_lot=%.2f typical_stop=%.1fxATR min_risk=%.2f budget=%.2f needs_equity=%.2f %s",
                                   minVol, k, m_microMinRisk, m_microBudget, m_microRequiredEquity,
                                   AccountInfoString(ACCOUNT_CURRENCY));
      if(!m_microChecked || feasible != m_microFeasible)
         ApexLog(feasible ? APEX_LOG_INFO : APEX_LOG_ERROR, "MICRO_ACCOUNT_CHECK",
                 "SYMBOL=" + m_cfg.symbol + " RESULT=" + (feasible ? "TRADABLE" : "INSUFFICIENT_CAPITAL_FOR_VALID_TRADE") +
                 " " + m_microDetail);
      m_microChecked  = true;
      m_microFeasible = feasible;
      return feasible;
     }

   bool              MicroFeasible(void) const { return m_microFeasible; }
   double            MicroRequiredEquity(void) const { return m_microRequiredEquity; }
   string            MicroDetail(void) const { return m_microDetail; }

   //--- Full pre-trade validation. Returns true with a complete plan, or
   //--- false with the rejection reason. Never "adjusts" a trade to force it.
   bool              Evaluate(const SSignalResult &sig, const SSessionState &ss, const SLiquidityState &liq,
                              const SStructureState &entrySt, const double atrPercentile,
                              CCircuitBreaker &brk, INewsFilter *news,
                              STradePlan &plan, ENUM_APEX_REJECT &rej, string &detail)
     {
      ZeroMemory(plan);
      rej = APEX_REJECT_NONE;
      detail = "";
      if(sig.decision == APEX_DECISION_NO_TRADE)
         return Reject(rej, detail, sig.reject, sig.detail);
      int dir = sig.dir;
      string sym = m_cfg.symbol;

      //--- 1. circuit breakers and clock
      UpdateLossBreakers(brk);
      if(brk.AnyActive())
         return Reject(rej, detail, APEX_REJECT_CIRCUIT_BREAKER, brk.Describe());
      if(!ss.valid)
         return Reject(rej, detail, APEX_REJECT_CIRCUIT_BREAKER, "session clock invalid");

      //--- 2. session
      if(!ss.entriesAllowed)
         return Reject(rej, detail, ss.endingSoon ? APEX_REJECT_SESSION_ENDING : APEX_REJECT_OUTSIDE_SESSION,
                       ApexSessionToString(ss.session));

      //--- 3. news
      string newsReason = "";
      if(news != NULL && news.BlocksEntries(sym, ss.serverTime, newsReason))
         return Reject(rej, detail, APEX_REJECT_NEWS, newsReason);

      //--- 4. exposure
      int mine, family;
      bool opposite, usdConflict, foreign;
      double fm, ff;
      ScanPositions(dir, mine, family, opposite, usdConflict, foreign, fm, ff);
      if(opposite)
         return Reject(rej, detail, APEX_REJECT_OPPOSITE_POSITION, "close the existing position first (no flip-flopping)");
      if(mine >= m_cfg.maxOpenPositions)
         return Reject(rej, detail, APEX_REJECT_MAX_POSITIONS, StringFormat("%d open", mine));
      if(family >= m_cfg.maxAccountOpenPositions)
         return Reject(rej, detail, APEX_REJECT_ACCOUNT_MAX_POSITIONS, StringFormat("%d open across ApexFlow", family));
      if(usdConflict)
         return Reject(rej, detail, APEX_REJECT_CORRELATION, "same-direction USD exposure already open");
      if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && (foreign || mine > 0))
         return Reject(rej, detail, APEX_REJECT_MAX_POSITIONS, "netting account: symbol already has a position");

      //--- 5. broker trade mode
      long tradeMode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
      if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
         return Reject(rej, detail, APEX_REJECT_BROKER_CONSTRAINT, "symbol not open for new positions");
      if((tradeMode == SYMBOL_TRADE_MODE_LONGONLY && dir == APEX_DIR_SELL) ||
         (tradeMode == SYMBOL_TRADE_MODE_SHORTONLY && dir == APEX_DIR_BUY))
         return Reject(rej, detail, APEX_REJECT_BROKER_CONSTRAINT, "direction not allowed by broker");

      //--- 6. price, spread, volatility
      MqlTick tick;
      if(!SymbolInfoTick(sym, tick) || tick.bid <= 0 || tick.ask <= 0 || tick.ask < tick.bid)
         return Reject(rej, detail, APEX_REJECT_CIRCUIT_BREAKER, "invalid price");
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double atr = sig.atr;
      double spread = tick.ask - tick.bid;
      double spreadPts = (point > 0) ? spread / point : 0;
      if(m_cfg.maxSpreadPoints > 0 && spreadPts > m_cfg.maxSpreadPoints)
         return Reject(rej, detail, APEX_REJECT_SPREAD_TOO_HIGH, StringFormat("spread %.0f > %d points", spreadPts, m_cfg.maxSpreadPoints));
      if(atr > 0 && spread > atr * m_cfg.maxSpreadPctATR / 100.0)
         return Reject(rej, detail, APEX_REJECT_SPREAD_TOO_HIGH, StringFormat("spread %.1f%% of ATR", 100.0 * spread / atr));
      double atrPts = ApexATRPoints(atr, point);
      if(atr <= 0 || (m_cfg.minATRPoints > 0 && atrPts < m_cfg.minATRPoints) ||
         (m_cfg.maxATRPoints > 0 && atrPts > m_cfg.maxATRPoints))
         return Reject(rej, detail, APEX_REJECT_VOLATILITY, StringFormat("ATR %.0f points", atrPts));
      if(atrPercentile < m_cfg.atrPctMin || atrPercentile > m_cfg.atrPctMax)
         return Reject(rej, detail, APEX_REJECT_VOLATILITY, StringFormat("ATR percentile %.0f", atrPercentile));

      //--- 7. stop loss (mandatory) and take profit
      double entry = (dir == APEX_DIR_BUY) ? tick.ask : tick.bid;
      ENUM_APEX_REJECT stopRej = APEX_REJECT_NONE;
      double sl = ApexComputeStop(dir, entry, sig.structuralStop, atr, m_cfg, stopRej);
      if(sl <= 0)
         return Reject(rej, detail, stopRej, "no valid stop-loss");
      sl = ApexNormalizePrice(sym, sl);
      double stopsLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;
      double closePrice = (dir == APEX_DIR_BUY) ? tick.bid : tick.ask;
      double slGap = (closePrice - sl) * dir;
      if(slGap <= stopsLevel || slGap <= 2.0 * spread)
         return Reject(rej, detail, APEX_REJECT_INVALID_STOP,
                       StringFormat("stop %.1f pts from price (stops level %.0f, spread %.0f)", slGap / point, stopsLevel / point, spreadPts));
      double tp = ApexNormalizePrice(sym, ApexComputeTakeProfit(dir, entry, sl, atr, liq, entrySt, m_cfg));
      double tpGap = (tp - closePrice) * dir;
      if(tpGap <= stopsLevel)
         return Reject(rej, detail, APEX_REJECT_INVALID_STOP, "take-profit inside broker stops level");

      //--- 8. position size
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney = equity * m_cfg.riskPct / 100.0;
      double lossPerLot = ApexLossPerLot(sym, dir, entry, sl);
      double minVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double maxVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(lossPerLot <= 0 || minVol <= 0 || step <= 0)
         return Reject(rej, detail, APEX_REJECT_BROKER_CONSTRAINT, "cannot read contract specification");
      double volume = ApexCalcVolume(riskMoney, lossPerLot, minVol, maxVol, step);
      if(volume <= 0)
         return Reject(rej, detail, APEX_REJECT_INSUFFICIENT_CAPITAL,
                       StringFormat("min lot %.2f risks %.2f > budget %.2f %s", minVol, minVol * lossPerLot,
                                    riskMoney, AccountInfoString(ACCOUNT_CURRENCY)));
      double volLimit = SymbolInfoDouble(sym, SYMBOL_VOLUME_LIMIT);
      if(volLimit > 0 && volume > volLimit)
         return Reject(rej, detail, APEX_REJECT_BROKER_CONSTRAINT, "symbol volume limit");

      //--- 9. margin
      double margin = 0;
      ENUM_ORDER_TYPE type = (dir == APEX_DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!OrderCalcMargin(type, sym, volume, entry, margin))
         return Reject(rej, detail, APEX_REJECT_BROKER_CONSTRAINT, "margin calculation failed");
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * m_cfg.maxMarginUsePct / 100.0)
        {
         brk.Set(APEX_BRK_MARGIN, true, StringFormat("needs %.2f of %.2f free", margin, freeMargin));
         return Reject(rej, detail, APEX_REJECT_INSUFFICIENT_MARGIN, StringFormat("margin %.2f > %.0f%% of free %.2f", margin, m_cfg.maxMarginUsePct, freeMargin));
        }
      brk.Set(APEX_BRK_MARGIN, false, "");

      //--- 10. final risk sanity (can only be <= budget by construction)
      double actualRisk = volume * lossPerLot;
      double actualPct = (equity > 0) ? actualRisk / equity * 100.0 : 999.0;
      if(actualPct > m_cfg.riskPct + 1e-6 || actualPct > APEX_HARD_MAX_RISK_PCT)
         return Reject(rej, detail, APEX_REJECT_RISK_LIMIT, StringFormat("risk %.3f%% exceeds limit", actualPct));

      plan.valid      = true;
      plan.dir        = dir;
      plan.strategy   = sig.strategy;
      plan.entry      = entry;
      plan.sl         = sl;
      plan.tp         = tp;
      plan.volume     = volume;
      plan.riskMoney  = actualRisk;
      plan.riskPct    = actualPct;
      plan.lossPerLot = lossPerLot;
      return true;
     }
  };

#endif // APEXFLOW_RISKENGINE_MQH
