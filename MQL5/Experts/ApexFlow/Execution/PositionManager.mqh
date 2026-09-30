//+------------------------------------------------------------------+
//| PositionManager.mqh - position state machine and profit           |
//| protection (break-even, partial close, trailing, adverse regime). |
//|                                                                   |
//| States: NEW -> OPEN -> PROTECTING -> PARTIAL_EXIT -> TRAILING     |
//|         -> CLOSING -> CLOSED                                      |
//| Invariant: a stop-loss only ever moves in the direction that      |
//| REDUCES risk. ApexSLImproves() is the single gate for that.       |
//|                                                                   |
//| Persistence: the initial stop, volume and risk of every position  |
//| are stored in terminal global variables (AF.<ticket>.*), so the   |
//| R-based rules survive terminal restarts.                          |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_POSITIONMANAGER_MQH
#define APEXFLOW_POSITIONMANAGER_MQH

#include "../Config.mqh"
#include "../Utils.mqh"
#include "../Core/CircuitBreaker.mqh"
#include "../Core/RiskEngine.mqh"
#include "OrderManager.mqh"

//====================================================================
// PURE HELPERS (unit-tested)
//====================================================================
double ApexProfitR(const int dir, const double entry, const double price, const double riskDist)
  {
   if(riskDist <= 0)
      return 0.0;
   return (price - entry) * dir / riskDist;
  }

//--- True only if newSL is strictly better (less risk) than curSL by at least minStep.
bool ApexSLImproves(const int dir, const double curSL, const double newSL, const double minStep)
  {
   if(newSL <= 0)
      return false;
   if(curSL <= 0)
      return true;
   double gain = (newSL - curSL) * dir;
   return (gain > 0 && gain >= minStep);
  }

double ApexBreakEvenSL(const int dir, const double entry, const double offsetPrice)
  {
   return entry + dir * offsetPrice;
  }

double ApexAtrTrailSL(const int dir, const double price, const double atr, const double mult)
  {
   if(atr <= 0)
      return 0.0;
   return price - dir * mult * atr;
  }

//--- The looser of two trailing candidates (less aggressive). 0 = unavailable.
double ApexHybridTrailSL(const int dir, const double a, const double b)
  {
   if(a <= 0)
      return b;
   if(b <= 0)
      return a;
   return (dir == APEX_DIR_BUY) ? MathMin(a, b) : MathMax(a, b);
  }

//--- Partial close volume, or 0 if the broker volume rules make it impossible
//--- (the closed part or the remainder would be below the minimum volume).
double ApexPartialCloseVolume(const double initialVol, const double curVol, const double pct,
                              const double minVol, const double step)
  {
   double v = ApexNormalizeVolumeDown(initialVol * pct / 100.0, minVol, 0, step);
   if(v <= 0 || v >= curVol)
      return 0.0;
   if(curVol - v < minVol - 1e-9)
      return 0.0;
   return v;
  }

bool ApexRegimeAgainst(const int dir, const ENUM_APEX_REGIME regime)
  {
   return (dir == APEX_DIR_BUY && regime == APEX_REGIME_TREND_DOWN) ||
          (dir == APEX_DIR_SELL && regime == APEX_REGIME_TREND_UP);
  }

#define APEX_FLAG_BE       1
#define APEX_FLAG_PARTIAL  2
#define APEX_FLAG_TRAILING 4
#define APEX_FLAG_ADVERSE  8

//====================================================================
// MANAGER
//====================================================================
class CPositionManager
  {
private:
   SApexConfig       m_cfg;
   SPositionTrack    m_pos[];

   string            Gv(const ulong ticket, const string key) const
     {
      return "AF." + IntegerToString((long)ticket) + "." + key;
     }

   void              SaveTrack(const int i) const
     {
      ulong t = m_pos[i].ticket;
      int flags = (m_pos[i].beDone ? APEX_FLAG_BE : 0) | (m_pos[i].partialDone ? APEX_FLAG_PARTIAL : 0) |
                  (m_pos[i].trailing ? APEX_FLAG_TRAILING : 0) | (m_pos[i].adverseHandled ? APEX_FLAG_ADVERSE : 0);
      GlobalVariableSet(Gv(t, "ISL"), m_pos[i].initialSL);
      GlobalVariableSet(Gv(t, "IVOL"), m_pos[i].initialVolume);
      GlobalVariableSet(Gv(t, "RISK"), m_pos[i].riskMoney);
      GlobalVariableSet(Gv(t, "STR"), (double)m_pos[i].strategy);
      GlobalVariableSet(Gv(t, "REG"), (double)m_pos[i].regime);
      GlobalVariableSet(Gv(t, "SES"), (double)m_pos[i].session);
      GlobalVariableSet(Gv(t, "BS"), m_pos[i].buyScore);
      GlobalVariableSet(Gv(t, "SS"), m_pos[i].sellScore);
      GlobalVariableSet(Gv(t, "FLG"), (double)flags);
      GlobalVariableSet(Gv(t, "ST"), (double)m_pos[i].state);
     }

   double            LoadGv(const ulong ticket, const string key, const double fallback) const
     {
      string name = Gv(ticket, key);
      if(GlobalVariableCheck(name))
         return GlobalVariableGet(name);
      return fallback;
     }

   void              DeleteGvs(const ulong ticket) const
     {
      GlobalVariablesDeleteAll("AF." + IntegerToString((long)ticket) + ".");
     }

   int               Append(const SPositionTrack &t)
     {
      int n = ArraySize(m_pos);
      ArrayResize(m_pos, n + 1);
      m_pos[n] = t;
      return n;
     }

   void              RemoveAt(const int i)
     {
      int n = ArraySize(m_pos);
      for(int k = i; k < n - 1; k++)
         m_pos[k] = m_pos[k + 1];
      ArrayResize(m_pos, n - 1);
     }

   void              SetState(const int i, const ENUM_APEX_POS_STATE s, const string why)
     {
      if(m_pos[i].state == s)
         return;
      ApexLog(APEX_LOG_INFO, "POSITION_STATE",
              StringFormat("SYMBOL=%s TICKET=%I64u FROM=%s TO=%s WHY=%s", m_cfg.symbol, m_pos[i].ticket,
                           ApexPosStateToString(m_pos[i].state), ApexPosStateToString(s), why));
      m_pos[i].state = s;
     }

public:
   void              Init(const SApexConfig &c) { m_cfg = c; ArrayResize(m_pos, 0); }

   int               Count(void) const { return ArraySize(m_pos); }

   int               Find(const ulong ticket) const
     {
      for(int i = 0; i < ArraySize(m_pos); i++)
         if(m_pos[i].ticket == ticket)
            return i;
      return -1;
     }

   void              Tickets(ulong &out[]) const
     {
      int n = ArraySize(m_pos);
      ArrayResize(out, n);
      for(int i = 0; i < n; i++)
         out[i] = m_pos[i].ticket;
     }

   bool              Get(const int i, SPositionTrack &out) const
     {
      if(i < 0 || i >= ArraySize(m_pos))
         return false;
      out = m_pos[i];
      return true;
     }

   //--- Track a position ApexFlow just opened.
   bool              Register(const ulong ticket, const STradePlan &p, const SSignalResult &sig,
                              COrderManager &om, CCircuitBreaker &brk)
     {
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         return false;
      if(Find(ticket) >= 0)
         return true;
      SPositionTrack t;
      ZeroMemory(t);
      t.ticket        = ticket;
      t.dir           = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? APEX_DIR_BUY : APEX_DIR_SELL;
      t.entry         = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl       = PositionGetDouble(POSITION_SL);
      t.initialSL     = (sl > 0) ? sl : p.sl;
      t.initialVolume = PositionGetDouble(POSITION_VOLUME);
      t.riskDist      = MathAbs(t.entry - t.initialSL);
      double lpl      = ApexLossPerLot(m_cfg.symbol, t.dir, t.entry, t.initialSL);
      t.riskMoney     = (lpl > 0) ? lpl * t.initialVolume : p.riskMoney;
      t.state         = APEX_POS_NEW;
      t.openTime      = (datetime)PositionGetInteger(POSITION_TIME);
      t.strategy      = sig.strategy;
      t.regime        = sig.regime;
      t.session       = sig.session;
      t.buyScore      = sig.buy.total;
      t.sellScore     = sig.sell.total;
      int i = Append(t);

      // Every position must carry a stop-loss. Repair it, or close the position.
      if(sl <= 0)
        {
         string err = "";
         ApexLog(APEX_LOG_ERROR, "POSITION_WITHOUT_SL", StringFormat("SYMBOL=%s TICKET=%I64u repairing", m_cfg.symbol, ticket));
         if(!om.Modify(ticket, p.sl, p.tp, brk, err))
           {
            ApexLog(APEX_LOG_ERROR, "POSITION_WITHOUT_SL", StringFormat("SYMBOL=%s TICKET=%I64u repair failed (%s): closing", m_cfg.symbol, ticket, err));
            m_pos[i].closeReason = "missing_stop_loss";
            SetState(i, APEX_POS_CLOSING, "no stop-loss");
            om.Close(ticket, brk, err);
            SaveTrack(i);
            return true;
           }
        }
      SetState(i, APEX_POS_OPEN, "fill confirmed with stop-loss");
      SaveTrack(i);
      return true;
     }

   //--- Rebuild tracking for a position found at the broker (restart recovery).
   void              Adopt(const ulong ticket, const double atr, const bool startup)
     {
      if(!PositionSelectByTicket(ticket) || Find(ticket) >= 0)
         return;
      SPositionTrack t;
      ZeroMemory(t);
      t.ticket   = ticket;
      t.dir      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? APEX_DIR_BUY : APEX_DIR_SELL;
      t.entry    = PositionGetDouble(POSITION_PRICE_OPEN);
      t.openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double sl  = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);

      double isl = LoadGv(ticket, "ISL", 0);
      bool fromGv = (isl > 0);
      if(fromGv)
         t.initialSL = isl;
      else
        {
         if(sl > 0 && (t.entry - sl) * t.dir > 0)
            t.initialSL = sl;       // stop still on the loss side: best estimate of 1R
         else
           {
            double dist = (atr > 0) ? m_cfg.stopATRMult * atr : 0;
            t.initialSL = (dist > 0) ? t.entry - t.dir * dist : sl;
           }
        }
      t.riskDist      = MathAbs(t.entry - t.initialSL);
      t.initialVolume = LoadGv(ticket, "IVOL", vol);
      double lpl      = ApexLossPerLot(m_cfg.symbol, t.dir, t.entry, t.initialSL);
      t.riskMoney     = LoadGv(ticket, "RISK", (lpl > 0) ? lpl * t.initialVolume : 0);
      t.strategy      = (ENUM_APEX_STRATEGY)(int)LoadGv(ticket, "STR", 0);
      t.regime        = (ENUM_APEX_REGIME)(int)LoadGv(ticket, "REG", 0);
      t.session       = (ENUM_APEX_SESSION)(int)LoadGv(ticket, "SES", 0);
      t.buyScore      = LoadGv(ticket, "BS", 0);
      t.sellScore     = LoadGv(ticket, "SS", 0);
      int flags       = (int)LoadGv(ticket, "FLG", 0);
      t.beDone        = ((flags & APEX_FLAG_BE) != 0) || (sl > 0 && (sl - t.entry) * t.dir >= 0);
      t.partialDone   = ((flags & APEX_FLAG_PARTIAL) != 0) || (vol < t.initialVolume - 1e-9);
      t.trailing      = ((flags & APEX_FLAG_TRAILING) != 0);
      t.adverseHandled = ((flags & APEX_FLAG_ADVERSE) != 0);
      t.state         = (ENUM_APEX_POS_STATE)(int)LoadGv(ticket, "ST", (double)APEX_POS_OPEN);
      if(t.state == APEX_POS_NEW || t.state == APEX_POS_CLOSED)
         t.state = APEX_POS_OPEN;
      int i = Append(t);
      SaveTrack(i);
      ApexLog(startup ? APEX_LOG_INFO : APEX_LOG_ERROR, startup ? "POSITION_RECOVERED" : "RECONCILE_ADOPTED",
              StringFormat("SYMBOL=%s TICKET=%I64u DIR=%s ENTRY=%s INITIAL_SL=%s SOURCE=%s STATE=%s",
                           m_cfg.symbol, ticket, ApexDirToString(t.dir),
                           DoubleToString(t.entry, (int)SymbolInfoInteger(m_cfg.symbol, SYMBOL_DIGITS)),
                           DoubleToString(t.initialSL, (int)SymbolInfoInteger(m_cfg.symbol, SYMBOL_DIGITS)),
                           (fromGv ? "saved_state" : "estimated"), ApexPosStateToString(t.state)));
     }

   //--- Tick path: profit protection for every tracked position.
   void              Manage(COrderManager &om, CCircuitBreaker &brk, const double atr,
                            const SStructureState &entrySt, const ENUM_APEX_REGIME regime)
     {
      string sym = m_cfg.symbol;
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      double minVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      MqlTick tick;
      if(!SymbolInfoTick(sym, tick) || tick.bid <= 0 || tick.ask <= 0)
         return;

      for(int i = 0; i < ArraySize(m_pos); i++)
        {
         if(m_pos[i].state == APEX_POS_CLOSING || m_pos[i].state == APEX_POS_CLOSED)
            continue;
         ulong ticket = m_pos[i].ticket;
         if(!PositionSelectByTicket(ticket))
            continue; // closure is handled by reconciliation
         int dir = m_pos[i].dir;
         double curSL = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         double vol = PositionGetDouble(POSITION_VOLUME);
         double closePx = (dir == APEX_DIR_BUY) ? tick.bid : tick.ask;
         double r = ApexProfitR(dir, m_pos[i].entry, closePx, m_pos[i].riskDist);
         m_pos[i].maxR = MathMax(m_pos[i].maxR, r);

         // Throttle requests per position in live trading (real milliseconds).
         // The Strategy Tester runs faster than real time, so no throttle there.
         uint nowMs = GetTickCount();
         if(!MQLInfoInteger(MQL_TESTER) && m_pos[i].lastModifyMs != 0 && nowMs - m_pos[i].lastModifyMs < 1000)
            continue;

         string err = "";
         //--- adverse regime: evaluate the open trade before anything else
         if(!m_pos[i].adverseHandled && ApexRegimeAgainst(dir, regime) && m_cfg.adverseAction != APEX_ADVERSE_NONE)
           {
            m_pos[i].adverseHandled = true;
            ApexLog(APEX_LOG_INFO, "ADVERSE_REGIME",
                    StringFormat("SYMBOL=%s TICKET=%I64u DIR=%s REGIME=%s R=%.2f ACTION=%s", sym, ticket,
                                 ApexDirToString(dir), ApexRegimeToString(regime), r, EnumToString(m_cfg.adverseAction)));
            if(m_cfg.adverseAction == APEX_ADVERSE_CLOSE)
              {
               m_pos[i].closeReason = "regime_reversal";
               SetState(i, APEX_POS_CLOSING, "regime turned against position");
               m_pos[i].lastModifyMs = nowMs;
               if(!om.Close(ticket, brk, err))
                  SetState(i, APEX_POS_OPEN, "close failed: " + err);
               SaveTrack(i);
               continue;
              }
            SaveTrack(i);
           }

         double newSL = 0;
         string why = "";
         bool markBe = false, markTrail = false;

         //--- break-even (also used by the TIGHTEN adverse action when in profit)
         bool wantBe = (!m_pos[i].beDone && r >= m_cfg.beTriggerR) ||
                       (!m_pos[i].beDone && m_pos[i].adverseHandled && m_cfg.adverseAction == APEX_ADVERSE_TIGHTEN &&
                        ApexRegimeAgainst(dir, regime) && r >= 0.5);
         if(wantBe)
           {
            double be = ApexNormalizePrice(sym, ApexBreakEvenSL(dir, m_pos[i].entry, m_cfg.beOffsetPoints * point));
            if(ApexSLImproves(dir, curSL, be, point))
              {
               newSL = be;
               why = "break_even";
               markBe = true;
              }
            else
               m_pos[i].beDone = true; // stop already at or beyond break-even
           }

         //--- partial close
         if(m_cfg.enablePartial && !m_pos[i].partialDone && r >= m_cfg.partialR)
           {
            double pv = ApexPartialCloseVolume(m_pos[i].initialVolume, vol, m_cfg.partialPct, minVol, step);
            if(pv <= 0)
              {
               m_pos[i].partialDone = true;
               ApexLog(APEX_LOG_INFO, "PARTIAL_SKIPPED",
                       StringFormat("SYMBOL=%s TICKET=%I64u VOLUME=%.2f MIN=%.2f STEP=%.2f reason=broker_volume_rules",
                                    sym, ticket, vol, minVol, step));
               SaveTrack(i);
              }
            else
              {
               m_pos[i].lastModifyMs = nowMs;
               if(om.ClosePartial(ticket, pv, brk, err))
                 {
                  m_pos[i].partialDone = true;
                  SetState(i, APEX_POS_PARTIAL_EXIT, StringFormat("closed %.2f at %.2fR", pv, r));
                  SaveTrack(i);
                 }
               continue; // one request per position per pass
              }
           }

         //--- trailing
         if(m_cfg.enableTrailing && r >= m_cfg.trailStartR)
           {
            double atrSL = ApexAtrTrailSL(dir, closePx, atr, m_cfg.trailATRMult);
            double structSL = 0;
            if(entrySt.valid)
              {
               double lvl = (dir == APEX_DIR_BUY) ? entrySt.lastLow - m_cfg.stopATRBuffer * atr
                            : entrySt.lastHigh + m_cfg.stopATRBuffer * atr;
               if((closePx - lvl) * dir > 0)
                  structSL = lvl;
              }
            double cand = 0;
            if(m_cfg.trailMode == APEX_TRAIL_ATR)
               cand = atrSL;
            else
               if(m_cfg.trailMode == APEX_TRAIL_STRUCTURE)
                  cand = structSL;
               else
                  cand = ApexHybridTrailSL(dir, atrSL, structSL);
            cand = (cand > 0) ? ApexNormalizePrice(sym, cand) : 0;
            double ref = (newSL > 0) ? newSL : curSL;
            double minStep = MathMax(point, 0.1 * m_pos[i].riskDist); // avoid spamming tiny moves
            if(ApexSLImproves(dir, ref, cand, minStep))
              {
               newSL = cand;
               why = "trailing";
               markTrail = true;
              }
           }

         if(newSL > 0 && ApexSLImproves(dir, curSL, newSL, 0))
           {
            m_pos[i].lastModifyMs = nowMs;
            if(om.Modify(ticket, newSL, tp, brk, err))
              {
               ApexLog(APEX_LOG_INFO, "SL_MOVED",
                       StringFormat("SYMBOL=%s TICKET=%I64u REASON=%s OLD_SL=%s NEW_SL=%s R=%.2f", sym, ticket, why,
                                    DoubleToString(curSL, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
                                    DoubleToString(newSL, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)), r));
               if(markBe)
                 {
                  m_pos[i].beDone = true;
                  if(m_pos[i].state == APEX_POS_OPEN)
                     SetState(i, APEX_POS_PROTECTING, "break-even reached");
                 }
               if(markTrail)
                 {
                  m_pos[i].trailing = true;
                  SetState(i, APEX_POS_TRAILING, "trailing active");
                 }
               SaveTrack(i);
              }
            else
               ApexLog(APEX_LOG_DEBUG, "SL_MOVE_DEFERRED", StringFormat("SYMBOL=%s TICKET=%I64u REASON=%s", sym, ticket, err));
           }
        }
     }

   //--- Money currently locked in by the stop (>0 only when SL is beyond entry).
   double            ProtectedProfit(void) const
     {
      double total = 0;
      for(int i = 0; i < ArraySize(m_pos); i++)
        {
         if(!PositionSelectByTicket(m_pos[i].ticket))
            continue;
         double sl = PositionGetDouble(POSITION_SL);
         if(sl <= 0 || (sl - m_pos[i].entry) * m_pos[i].dir <= 0)
            continue;
         ENUM_ORDER_TYPE type = (m_pos[i].dir == APEX_DIR_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double p = 0;
         if(OrderCalcProfit(type, m_cfg.symbol, PositionGetDouble(POSITION_VOLUME), m_pos[i].entry, sl, p))
            total += p;
        }
      return total;
     }

   //--- A tracked position is gone at the broker: build the closed-trade record.
   bool              HandleClosed(const ulong ticket, SClosedTrade &ct)
     {
      int i = Find(ticket);
      if(i < 0)
         return false;
      ZeroMemory(ct);
      ct.ticket    = ticket;
      ct.symbol    = m_cfg.symbol;
      ct.dir       = m_pos[i].dir;
      ct.strategy  = m_pos[i].strategy;
      ct.regime    = m_pos[i].regime;
      ct.session   = m_pos[i].session;
      ct.openTime  = m_pos[i].openTime;
      ct.entry     = m_pos[i].entry;
      ct.initialSL = m_pos[i].initialSL;
      ct.volume    = m_pos[i].initialVolume;
      ct.riskMoney = m_pos[i].riskMoney;
      ct.buyScore  = m_pos[i].buyScore;
      ct.sellScore = m_pos[i].sellScore;
      ct.exitReason = "unknown";

      if(HistorySelectByPosition(ticket))
        {
         int n = HistoryDealsTotal();
         long lastReason = -1;
         for(int k = 0; k < n; k++)
           {
            ulong d = HistoryDealGetTicket(k);
            if(d == 0)
               continue;
            ct.profit += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                         HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
            long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
              {
               ct.exitPrice = HistoryDealGetDouble(d, DEAL_PRICE);
               ct.closeTime = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
               lastReason   = HistoryDealGetInteger(d, DEAL_REASON);
              }
           }
         if(lastReason == DEAL_REASON_SL)
            ct.exitReason = m_pos[i].trailing ? "trailing_stop" : (m_pos[i].beDone ? "protected_stop" : "stop_loss");
         else
            if(lastReason == DEAL_REASON_TP)
               ct.exitReason = "take_profit";
            else
               if(lastReason == DEAL_REASON_SO)
                  ct.exitReason = "stop_out";
               else
                  if(lastReason == DEAL_REASON_EXPERT)
                     ct.exitReason = (m_pos[i].closeReason != "") ? m_pos[i].closeReason : "expert";
                  else
                     if(lastReason == DEAL_REASON_CLIENT || lastReason == DEAL_REASON_MOBILE || lastReason == DEAL_REASON_WEB)
                        ct.exitReason = "manual_close";
        }
      if(ct.closeTime == 0)
         ct.closeTime = TimeCurrent();
      ct.rMultiple = (ct.riskMoney > 0) ? ct.profit / ct.riskMoney : 0.0;
      SetState(i, APEX_POS_CLOSED, ct.exitReason);
      DeleteGvs(ticket);
      RemoveAt(i);
      return true;
     }
  };

#endif // APEXFLOW_POSITIONMANAGER_MQH
