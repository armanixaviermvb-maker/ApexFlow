//+------------------------------------------------------------------+
//| OrderManager.mqh - execution abstraction around CTrade            |
//|                                                                   |
//| - Re-checks the live-trading lock before every new position.      |
//| - Refuses any order without a stop-loss.                          |
//| - Re-validates stop distance and slippage against a fresh price.  |
//| - Verifies every broker response; never assumes success.          |
//| - Counts consecutive failures and trips the ORDER_FAILURES        |
//|   breaker (blocks new entries, management continues).             |
//| Protective operations (modify SL, partial close, close) are       |
//| allowed in every mode because they only reduce exposure.          |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_ORDERMANAGER_MQH
#define APEXFLOW_ORDERMANAGER_MQH

#include <Trade\Trade.mqh>
#include "../Config.mqh"
#include "../Utils.mqh"
#include "../Core/CircuitBreaker.mqh"

class COrderManager
  {
private:
   CTrade            m_trade;
   SApexConfig       m_cfg;
   int               m_failures;
   uint              m_lastRetcode;

   void              RecordFailure(CCircuitBreaker &brk, const uint rc)
     {
      m_failures++;
      if(rc == TRADE_RETCODE_NO_MONEY)
         brk.Trip(APEX_BRK_MARGIN, "broker reported insufficient funds", false);
      if(rc == TRADE_RETCODE_TRADE_DISABLED || rc == TRADE_RETCODE_SERVER_DISABLES_AT ||
         rc == TRADE_RETCODE_CLIENT_DISABLES_AT)
         brk.Trip(APEX_BRK_TRADING_DISABLED, ApexRetcodeText(rc), false);
      if(m_failures >= m_cfg.maxOrderFailures)
         brk.Trip(APEX_BRK_ORDER_FAILURES, StringFormat("%d consecutive trade request failures", m_failures), true);
     }

   void              LogFailure(const string function, const string operation)
     {
      m_lastRetcode = m_trade.ResultRetcode();
      ApexLogError(function, m_cfg.symbol, operation, (long)m_lastRetcode,
                   m_trade.ResultRetcodeDescription() + " (" + ApexRetcodeText(m_lastRetcode) + ")");
     }

   int               SymDigits(void) const
     {
      return (int)SymbolInfoInteger(m_cfg.symbol, SYMBOL_DIGITS);
     }

   double            StopsDistance(void) const
     {
      double point = SymbolInfoDouble(m_cfg.symbol, SYMBOL_POINT);
      long stops  = SymbolInfoInteger(m_cfg.symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long freeze = SymbolInfoInteger(m_cfg.symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      return MathMax((double)stops, (double)freeze) * point;
     }

   //--- Locate the position created by a fill (hedging or netting).
   ulong             FindPositionTicket(const ulong order, const ulong deal) const
     {
      if(deal > 0 && HistoryDealSelect(deal))
        {
         ulong pid = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         if(pid > 0 && PositionSelectByTicket(pid))
            return pid;
        }
      if(order > 0 && PositionSelectByTicket(order))
         return order;
      ulong newest = 0;
      long newestTime = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.magic || PositionGetString(POSITION_SYMBOL) != m_cfg.symbol)
            continue;
         long tm = PositionGetInteger(POSITION_TIME_MSC);
         if(tm > newestTime)
           {
            newestTime = tm;
            newest = t;
           }
        }
      return newest;
     }

public:
                     COrderManager(void) : m_failures(0), m_lastRetcode(0) {}

   void              Init(const SApexConfig &c)
     {
      m_cfg = c;
      m_trade.SetExpertMagicNumber((ulong)c.magic);
      m_trade.SetDeviationInPoints((ulong)c.maxSlippagePoints);
      m_trade.SetTypeFillingBySymbol(c.symbol);
      m_trade.SetMarginMode();
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
     }

   int               Failures(void) const { return m_failures; }
   uint              LastRetcode(void) const { return m_lastRetcode; }
   void              ResetFailures(void) { m_failures = 0; }

   //--- Open a market position from a validated plan.
   //--- `ticket` = 0 with true means "filled but position not visible yet".
   bool              Open(const STradePlan &p, const string comment, CCircuitBreaker &brk,
                          ulong &ticket, string &err)
     {
      ticket = 0;
      err = "";
      string reason = "";
      if(!ConfigOrdersPermitted(m_cfg, reason))
        {
         err = "orders not permitted: " + reason;
         return false;
        }
      if(!p.valid || p.sl <= 0 || p.volume <= 0)
        {
         err = "refused: plan invalid or missing stop-loss";
         ApexLog(APEX_LOG_ERROR, "ORDER_REFUSED", "SYMBOL=" + m_cfg.symbol + " REASON=" + err);
         return false;
        }
      string sym = m_cfg.symbol;
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      uint rc = 0;
      for(int attempt = 0; attempt <= m_cfg.maxOrderRetries; attempt++)
        {
         MqlTick tick;
         if(!SymbolInfoTick(sym, tick) || tick.bid <= 0 || tick.ask <= 0)
           {
            err = "no valid quote";
            return false;
           }
         double price = (p.dir == APEX_DIR_BUY) ? tick.ask : tick.bid;
         double closePx = (p.dir == APEX_DIR_BUY) ? tick.bid : tick.ask;
         if(MathAbs(price - p.entry) > m_cfg.maxSlippagePoints * point && m_cfg.maxSlippagePoints > 0)
           {
            err = StringFormat("price moved %.0f points from plan; entry abandoned", MathAbs(price - p.entry) / point);
            ApexLog(APEX_LOG_INFO, "ORDER_ABANDONED", "SYMBOL=" + sym + " REASON=" + err);
            return false;
           }
         if((closePx - p.sl) * p.dir <= StopsDistance())
           {
            err = "stop-loss too close to current price";
            ApexLog(APEX_LOG_INFO, "ORDER_ABANDONED", "SYMBOL=" + sym + " REASON=" + err);
            return false;
           }
         bool sent = (p.dir == APEX_DIR_BUY) ? m_trade.Buy(p.volume, sym, price, p.sl, p.tp, comment)
                     : m_trade.Sell(p.volume, sym, price, p.sl, p.tp, comment);
         rc = m_trade.ResultRetcode();
         m_lastRetcode = rc;
         if(sent && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED))
           {
            ticket = FindPositionTicket(m_trade.ResultOrder(), m_trade.ResultDeal());
            m_failures = 0;
            ApexLog(APEX_LOG_INFO, "ORDER_FILLED",
                    StringFormat("SYMBOL=%s DIR=%s VOLUME=%.2f PRICE=%s SL=%s TP=%s TICKET=%I64u RETCODE=%u ATTEMPT=%d",
                                 sym, ApexDirToString(p.dir), m_trade.ResultVolume(),
                                 DoubleToString(m_trade.ResultPrice(), SymDigits()), DoubleToString(p.sl, SymDigits()),
                                 DoubleToString(p.tp, SymDigits()), ticket, rc, attempt + 1));
            if(rc == TRADE_RETCODE_DONE_PARTIAL)
               ApexLog(APEX_LOG_INFO, "ORDER_PARTIAL_FILL",
                       StringFormat("SYMBOL=%s REQUESTED=%.2f FILLED=%.2f", sym, p.volume, m_trade.ResultVolume()));
            return true;
           }
         LogFailure("COrderManager::Open", "market " + ApexDirToString(p.dir));
         if(!ApexRetcodeRetryable(rc))
            break;
        }
      err = "order failed: " + ApexRetcodeText(rc);
      RecordFailure(brk, rc);
      return false;
     }

   //--- Move SL/TP. Callers guarantee the new SL never increases risk.
   bool              Modify(const ulong ticket, const double sl, const double tp, CCircuitBreaker &brk, string &err)
     {
      err = "";
      if(!PositionSelectByTicket(ticket))
        {
         err = "position not found";
         return false;
        }
      MqlTick tick;
      if(!SymbolInfoTick(m_cfg.symbol, tick))
        {
         err = "no quote";
         return false;
        }
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double closePx = isBuy ? tick.bid : tick.ask;
      double minDist = StopsDistance();
      if(sl > 0 && ((isBuy && closePx - sl <= minDist) || (!isBuy && sl - closePx <= minDist)))
        {
         err = "new stop inside stops/freeze level";
         return false;
        }
      double curSL = PositionGetDouble(POSITION_SL);
      double freeze = SymbolInfoInteger(m_cfg.symbol, SYMBOL_TRADE_FREEZE_LEVEL) * SymbolInfoDouble(m_cfg.symbol, SYMBOL_POINT);
      if(freeze > 0 && curSL > 0 && MathAbs(closePx - curSL) <= freeze)
        {
         err = "current stop inside freeze level";
         return false;
        }
      bool sent = m_trade.PositionModify(ticket, sl, tp);
      uint rc = m_trade.ResultRetcode();
      m_lastRetcode = rc;
      if(sent && ApexRetcodeSuccess(rc))
         return true;
      LogFailure("COrderManager::Modify", StringFormat("modify #%I64u SL=%s", ticket, DoubleToString(sl, SymDigits())));
      err = "modify failed: " + ApexRetcodeText(rc);
      RecordFailure(brk, rc);
      return false;
     }

   bool              ClosePartial(const ulong ticket, const double volume, CCircuitBreaker &brk, string &err)
     {
      err = "";
      for(int attempt = 0; attempt <= m_cfg.maxOrderRetries; attempt++)
        {
         bool sent = m_trade.PositionClosePartial(ticket, volume);
         uint rc = m_trade.ResultRetcode();
         m_lastRetcode = rc;
         if(sent && ApexRetcodeSuccess(rc))
            return true;
         LogFailure("COrderManager::ClosePartial", StringFormat("partial close #%I64u %.2f", ticket, volume));
         if(!ApexRetcodeRetryable(rc))
            break;
        }
      err = "partial close failed: " + ApexRetcodeText(m_lastRetcode);
      RecordFailure(brk, m_lastRetcode);
      return false;
     }

   bool              Close(const ulong ticket, CCircuitBreaker &brk, string &err)
     {
      err = "";
      for(int attempt = 0; attempt <= m_cfg.maxOrderRetries; attempt++)
        {
         bool sent = m_trade.PositionClose(ticket);
         uint rc = m_trade.ResultRetcode();
         m_lastRetcode = rc;
         if(sent && ApexRetcodeSuccess(rc))
            return true;
         if(rc == TRADE_RETCODE_POSITION_CLOSED)
            return true;
         LogFailure("COrderManager::Close", StringFormat("close #%I64u", ticket));
         if(!ApexRetcodeRetryable(rc))
            break;
        }
      err = "close failed: " + ApexRetcodeText(m_lastRetcode);
      RecordFailure(brk, m_lastRetcode);
      return false;
     }
  };

#endif // APEXFLOW_ORDERMANAGER_MQH
