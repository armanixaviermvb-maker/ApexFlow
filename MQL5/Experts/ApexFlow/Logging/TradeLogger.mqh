//+------------------------------------------------------------------+
//| TradeLogger.mqh - structured journal of signals and trades        |
//|                                                                   |
//| Experts log: one structured line per event (Section 53 format).   |
//| CSV (Common\Files\ApexFlow\): every signal evaluation, including  |
//| rejected ones with the reason, and every closed trade. These are  |
//| the inputs of the Python research layer.                          |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_TRADELOGGER_MQH
#define APEXFLOW_TRADELOGGER_MQH

#include "../Config.mqh"
#include "../Utils.mqh"

class CTradeLogger
  {
private:
   SApexConfig       m_cfg;
   bool              m_files;
   string            m_signalFile;
   string            m_tradeFile;
   string            m_auctionFile;
   int               m_digits;

   string            Csv(const string s) const
     {
      string t = s;
      StringReplace(t, ",", ";");
      StringReplace(t, "\n", " ");
      StringReplace(t, "\r", " ");
      return t;
     }

   string            Ts(const datetime t) const { return TimeToString(t, TIME_DATE | TIME_SECONDS); }
   string            P(const double v) const { return DoubleToString(v, m_digits); }
   string            N(const double v, const int d) const { return DoubleToString(v, d); }

   bool              AppendLine(const string file, const string header, const string line)
     {
      int h = FileOpen(file, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_COMMON);
      if(h == INVALID_HANDLE)
        {
         ApexLogError("CTradeLogger::AppendLine", m_cfg.symbol, "open " + file, GetLastError(), "journal file unavailable");
         return false;
        }
      if(FileSize(h) == 0)
         FileWriteString(h, header + "\r\n");
      FileSeek(h, 0, SEEK_END);
      FileWriteString(h, line + "\r\n");
      FileClose(h);
      return true;
     }

   string            ScoreCols(const SScoreBreakdown &s) const
     {
      return N(s.trend, 1) + "," + N(s.structure, 1) + "," + N(s.momentum, 1) + "," + N(s.liquidity, 1) + "," +
             N(s.volatility, 1) + "," + N(s.session, 1) + "," + N(s.confirmation, 1);
     }

public:
                     CTradeLogger(void) : m_files(false), m_signalFile(""), m_tradeFile(""), m_auctionFile(""), m_digits(5) {}

   //--- File-name suffix: optional journal tag (A/B runs) + "_tester" in the Strategy Tester.
   static string     Suffix(const SApexConfig &c)
     {
      string sfx = (c.journalTag != "") ? "_" + c.journalTag : "";
      if(MQLInfoInteger(MQL_TESTER))
         sfx += "_tester";
      return sfx;
     }

   void              Init(const SApexConfig &c)
     {
      m_cfg    = c;
      m_digits = (int)SymbolInfoInteger(c.symbol, SYMBOL_DIGITS);
      m_files  = c.writeJournalCSV && !MQLInfoInteger(MQL_OPTIMIZATION);
      string tag = Suffix(c);
      m_signalFile  = "ApexFlow\\signals_" + c.symbol + "_" + IntegerToString(c.magic) + tag + ".csv";
      m_tradeFile   = "ApexFlow\\trades_" + c.symbol + "_" + IntegerToString(c.magic) + tag + ".csv";
      m_auctionFile = "ApexFlow\\auction_" + c.symbol + "_" + IntegerToString(c.magic) + tag + ".csv";
      // Each Strategy Tester run starts with fresh journals (live journals are appended).
      if(m_files && MQLInfoInteger(MQL_TESTER))
        {
         FileDelete(m_signalFile, FILE_COMMON);
         FileDelete(m_tradeFile, FILE_COMMON);
         FileDelete(m_auctionFile, FILE_COMMON);
        }
     }

   //--- One signal evaluation (new entry-timeframe bar).
   void              LogSignal(const SSignalResult &s, const STradePlan &p, const string status,
                               const ENUM_APEX_REJECT rej, const string detail, const double atrPct)
     {
      bool actionable = (s.decision != APEX_DECISION_NO_TRADE);
      string line = StringFormat("TIME=%s SYMBOL=%s TF=%s SESSION=%s REGIME=%s BUY_SCORE=%.0f SELL_SCORE=%.0f DECISION=%s STRATEGY=%s",
                                 Ts(s.time), m_cfg.symbol, EnumToString(m_cfg.tfEntry), ApexSessionToString(s.session),
                                 ApexRegimeToString(s.regime), s.buy.total, s.sell.total,
                                 ApexDecisionToString(s.decision), ApexStrategyToString(s.strategy));
      if(p.valid)
         line += StringFormat(" RISK=%.2f%% ENTRY=%s SL=%s TP=%s VOLUME=%.2f", p.riskPct, P(p.entry), P(p.sl), P(p.tp), p.volume);
      line += " STATUS=" + status;
      if(rej != APEX_REJECT_NONE)
         line += " REJECT=" + ApexRejectToString(rej) + " DETAIL=" + detail;
      ApexLog(actionable ? APEX_LOG_INFO : APEX_LOG_DEBUG, "SIGNAL", line);

      if(!m_files || (!actionable && !m_cfg.logRejected))
         return;
      string header = "time,symbol,timeframe,session,regime,decision,strategy,buy_score,sell_score," +
                      "buy_trend,buy_structure,buy_momentum,buy_liquidity,buy_volatility,buy_session,buy_confirmation," +
                      "sell_trend,sell_structure,sell_momentum,sell_liquidity,sell_volatility,sell_session,sell_confirmation," +
                      "spread_points,atr,atr_percentile,entry,sl,tp,volume,risk_money,risk_pct,status,reject_reason,detail," +
                      "strategy_version,mode";
      string row = Ts(s.time) + "," + m_cfg.symbol + "," + EnumToString(m_cfg.tfEntry) + "," +
                   ApexSessionToString(s.session) + "," + ApexRegimeToString(s.regime) + "," +
                   ApexDecisionToString(s.decision) + "," + ApexStrategyToString(s.strategy) + "," +
                   N(s.buy.total, 1) + "," + N(s.sell.total, 1) + "," + ScoreCols(s.buy) + "," + ScoreCols(s.sell) + "," +
                   N(s.spreadPoints, 1) + "," + P(s.atr) + "," + N(atrPct, 1) + "," +
                   (p.valid ? P(p.entry) : "") + "," + (p.valid ? P(p.sl) : "") + "," + (p.valid ? P(p.tp) : "") + "," +
                   (p.valid ? N(p.volume, 2) : "") + "," + (p.valid ? N(p.riskMoney, 2) : "") + "," +
                   (p.valid ? N(p.riskPct, 3) : "") + "," + status + "," +
                   (rej != APEX_REJECT_NONE ? ApexRejectToString(rej) : "") + "," + Csv(detail) + "," +
                   m_cfg.strategyVersion + "," + ApexModeToString(m_cfg.mode);
      AppendLine(m_signalFile, header, row);
     }

   void              LogTradeOpened(const ulong ticket, const STradePlan &p, const SSignalResult &s)
     {
      ApexLog(APEX_LOG_INFO, "TRADE_OPENED",
              StringFormat("TRADE_ID=%I64u SYMBOL=%s DIR=%s STRATEGY=%s REGIME=%s SESSION=%s ENTRY=%s SL=%s TP=%s VOLUME=%.2f RISK=%.2f (%.2f%%) BUY_SCORE=%.0f SELL_SCORE=%.0f VERSION=%s",
                           ticket, m_cfg.symbol, ApexDirToString(p.dir), ApexStrategyToString(p.strategy),
                           ApexRegimeToString(s.regime), ApexSessionToString(s.session), P(p.entry), P(p.sl), P(p.tp),
                           p.volume, p.riskMoney, p.riskPct, s.buy.total, s.sell.total, m_cfg.strategyVersion) +
              (p.minLotMode ? " MIN_LOT_MODE=YES (broker minimum above 1x risk, within the min-lot limit)" : ""));
     }

   void              LogTradeClosed(const SClosedTrade &t)
     {
      double minutes = (t.closeTime > t.openTime) ? (double)(t.closeTime - t.openTime) / 60.0 : 0;
      ApexLog(APEX_LOG_INFO, "TRADE_CLOSED",
              StringFormat("TRADE_ID=%I64u SYMBOL=%s DIR=%s STRATEGY=%s PROFIT=%.2f R=%.2f MAE=%.2fR MFE=%.2fR EXIT=%s DURATION_MIN=%.0f",
                           t.ticket, t.symbol, ApexDirToString(t.dir), ApexStrategyToString(t.strategy),
                           t.profit, t.rMultiple, t.maeR, t.mfeR, t.exitReason, minutes));
      if(!m_files)
         return;
      string header = "trade_id,symbol,direction,strategy,regime,session,open_time,close_time,duration_min," +
                      "entry,exit,initial_sl,volume,risk_money,profit,r_multiple,mae_r,mfe_r,exit_reason,buy_score,sell_score," +
                      "strategy_version,mode";
      string row = IntegerToString((long)t.ticket) + "," + t.symbol + "," + ApexDirToString(t.dir) + "," +
                   ApexStrategyToString(t.strategy) + "," + ApexRegimeToString(t.regime) + "," +
                   ApexSessionToString(t.session) + "," + Ts(t.openTime) + "," + Ts(t.closeTime) + "," +
                   N(minutes, 1) + "," + P(t.entry) + "," + P(t.exitPrice) + "," + P(t.initialSL) + "," +
                   N(t.volume, 2) + "," + N(t.riskMoney, 2) + "," + N(t.profit, 2) + "," + N(t.rMultiple, 3) + "," +
                   N(t.maeR, 3) + "," + N(t.mfeR, 3) + "," + t.exitReason + "," + N(t.buyScore, 1) + "," + N(t.sellScore, 1) + "," +
                   m_cfg.strategyVersion + "," + ApexModeToString(m_cfg.mode);
      AppendLine(m_tradeFile, header, row);
     }

   //--- AUCTION_REJECTION candidates (a swing leg exists) for both directions.
   //--- `status`/`finalReject` describe the overall decision of this bar.
   void              LogAuction(const SSignalResult &s, const string status, const ENUM_APEX_REJECT finalReject)
     {
      LogAuctionSide(s, s.arBuy, status, finalReject);
      LogAuctionSide(s, s.arSell, status, finalReject);
     }

private:
   void              LogAuctionSide(const SSignalResult &s, const SAuctionDiag &d, const string status,
                                    const ENUM_APEX_REJECT finalReject)
     {
      if(!d.evaluated)
         return;
      bool passed = (d.reject == APEX_REJECT_NONE);
      ApexLog(passed ? APEX_LOG_INFO : APEX_LOG_DEBUG, "AUCTION_CANDIDATE",
              StringFormat("TIME=%s SYMBOL=%s SESSION=%s REGIME=%s DIR=%s SWING_HIGH=%s SWING_LOW=%s ZONE=%s-%s-%s " +
                           "LOCATION=%s EFFORT_X=%.2f RESULT=%.2f ABSORPTION=%.0f DOMINANCE=%.0f AR_SCORE=%.0f " +
                           "GATE=%s DECISION=%s SOURCE=%s",
                           Ts(s.time), m_cfg.symbol, ApexSessionToString(s.session), ApexRegimeToString(s.regime),
                           ApexDirToString(d.dir), P(d.swingHigh), P(d.swingLow), P(d.fibStart), P(d.fibMid), P(d.fibEnd),
                           d.locationStatus, d.effortRatio, d.resultRatio, d.absorptionScore, d.dominanceScore, d.total,
                           (passed ? "passed" : ApexRejectToString(d.reject)), ApexDecisionToString(s.decision), d.source));
      if(!m_files)
         return;
      string header = "time,symbol,session,regime,direction,swing_high,swing_low,fib_zone_start,fib_zone_mid,fib_zone_end," +
                      "pullback_extreme,location_status,participation,participation_baseline,effort_ratio,price_displacement_atr," +
                      "result_ratio,effort_result_ratio,environment_score,location_score,absorption_score,dominance_shift_score," +
                      "structure_score,session_score,volatility_score,ar_score,ar_buy_score,ar_sell_score,final_buy_score," +
                      "final_sell_score,decision,decision_strategy,status,gate_reject,final_reject,participation_source," +
                      "strategy_version";
      string row = Ts(s.time) + "," + m_cfg.symbol + "," + ApexSessionToString(s.session) + "," +
                   ApexRegimeToString(s.regime) + "," + ApexDirToString(d.dir) + "," + P(d.swingHigh) + "," +
                   P(d.swingLow) + "," + P(d.fibStart) + "," + P(d.fibMid) + "," + P(d.fibEnd) + "," + P(d.extreme) + "," +
                   Csv(d.locationStatus) + "," + N(d.participation, 2) + "," + N(d.baseline, 2) + "," +
                   N(d.effortRatio, 3) + "," + N(d.displacementATR, 3) + "," + N(d.resultRatio, 3) + "," +
                   N(d.effortResultRatio, 3) + "," + N(d.environmentScore, 3) + "," + N(d.locationScore, 3) + "," +
                   N(d.absorptionScore, 1) + "," + N(d.dominanceScore, 1) + "," + N(d.structureScore, 3) + "," +
                   N(d.sessionScore, 3) + "," + N(d.volatilityScore, 3) + "," + N(d.total, 1) + "," +
                   N(s.arBuy.total, 1) + "," + N(s.arSell.total, 1) + "," + N(s.buy.total, 1) + "," +
                   N(s.sell.total, 1) + "," + ApexDecisionToString(s.decision) + "," +
                   ApexStrategyToString(s.strategy) + "," + status + "," +
                   (d.reject != APEX_REJECT_NONE ? ApexRejectToString(d.reject) : "") + "," +
                   (finalReject != APEX_REJECT_NONE ? ApexRejectToString(finalReject) : "") + "," +
                   Csv(d.source) + "," + m_cfg.strategyVersion;
      AppendLine(m_auctionFile, header, row);
     }
  };

#endif // APEXFLOW_TRADELOGGER_MQH
