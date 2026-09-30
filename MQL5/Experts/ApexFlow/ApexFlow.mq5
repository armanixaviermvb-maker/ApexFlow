//+------------------------------------------------------------------+
//| ApexFlow.mq5                                                      |
//| Adaptive, session-aware MetaTrader 5 Expert Advisor.              |
//|                                                                   |
//| No martingale. No loss doubling. No risk escalation.              |
//| No guaranteed returns: every trade can lose.                      |
//|                                                                   |
//| Flow: Session -> Structure -> Regime -> Signal (BUY/SELL scores)  |
//|       -> Risk -> Execution validation -> Order -> Position        |
//|       management -> Journal.                                      |
//| FAST PATH (every tick): price checks, position management.        |
//| ANALYSIS PATH (new entry-timeframe bar): indicators, structure,   |
//| regime, scoring, entry decision.                                  |
//+------------------------------------------------------------------+
#property copyright   "ApexFlow"
#property version     "1.00"
#property description "ApexFlow MT5 - adaptive session-aware EA."
#property description "Defaults to TEST mode. LIVE requires EnableTrading, LIVE mode and ConfirmLiveTrading."
#property description "No martingale, no loss doubling, no guaranteed returns."

#include "Config.mqh"
#include "Utils.mqh"
#include "Indicators/IndicatorManager.mqh"
#include "Core/SessionEngine.mqh"
#include "Core/StructureEngine.mqh"
#include "Core/RegimeEngine.mqh"
#include "Core/SignalEngine.mqh"
#include "Core/CircuitBreaker.mqh"
#include "Core/NewsFilter.mqh"
#include "Core/RiskEngine.mqh"
#include "Execution/OrderManager.mqh"
#include "Execution/PositionManager.mqh"
#include "Execution/Reconciliation.mqh"
#include "UI/Dashboard.mqh"
#include "Logging/TradeLogger.mqh"
#include "Logging/PerformanceStats.mqh"

//====================================================================
// MODULES
//====================================================================
SApexConfig       g_cfg;
CIndicatorManager g_ind;
CSessionEngine    g_session;
CRegimeEngine     g_regime;
CSignalEngine     g_signal;
CCircuitBreaker   g_brk;
CRiskEngine       g_risk;
COrderManager     g_orders;
CPositionManager  g_positions;
CReconciler       g_recon;
CDashboard        g_dash;
CTradeLogger      g_log;
CPerformanceStats g_stats;
CNoNewsFilter     g_newsNone;       // replace with a real INewsFilter implementation later
INewsFilter      *g_news = NULL;

//====================================================================
// RUNTIME STATE (rebuilt from the broker on every start)
//====================================================================
SSessionState     g_ss;
SRegimeState      g_rs;
SStructureState   g_confirmSt;
SStructureState   g_entrySt;
SLiquidityState   g_liq;
SSignalResult     g_sig;
string            g_lastStatus       = "STARTING";
string            g_lastRejectText   = "";
bool              g_ordersPermitted  = false;
string            g_permissionReason = "";
bool              g_permissionKnown  = false;
bool              g_needAnalysis     = true;
bool              g_firstAnalysis    = true;
bool              g_reconNow         = false;
datetime          g_entryInFlightUntil = 0;
datetime          g_lastConfirmBar   = 0;
datetime          g_lastDay          = 0;
double            g_peakEquity       = 0;
int               g_timerTicks       = 0;
int               g_dataFailures     = 0;

//+------------------------------------------------------------------+
//| Order permission (Section 49); logged whenever it changes.        |
//+------------------------------------------------------------------+
void RefreshPermission()
  {
   string reason = "";
   bool permitted = ConfigOrdersPermitted(g_cfg, reason);
   if(!g_permissionKnown || permitted != g_ordersPermitted || reason != g_permissionReason)
     {
      ApexLog(APEX_LOG_INFO, "ORDER_PERMISSION",
              StringFormat("SYMBOL=%s MODE=%s PERMITTED=%s REASON=%s", g_cfg.symbol,
                           ApexModeToString(g_cfg.mode), (permitted ? "YES" : "NO"), reason));
      g_permissionKnown = true;
     }
   g_ordersPermitted  = permitted;
   g_permissionReason = reason;

   // Terminal-level algo trading switched off while DEMO/LIVE expects to trade.
   bool expectTrading = (g_cfg.mode != APEX_MODE_TEST && g_cfg.enableTrading && !MQLInfoInteger(MQL_TESTER));
   bool disabled = expectTrading && (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED));
   g_brk.Set(APEX_BRK_TRADING_DISABLED, disabled, "algo trading disabled in terminal");
  }

//+------------------------------------------------------------------+
//| Reconciliation: broker positions are the source of truth.         |
//+------------------------------------------------------------------+
void RunReconciliation(const bool startup)
  {
   SClosedTrade closed[];
   ArrayResize(closed, 0);
   int n = g_recon.Run(g_cfg, g_positions, g_brk, g_ind.Atr(APEX_TF_ENTRY), startup, closed);
   for(int i = 0; i < n; i++)
     {
      g_log.LogTradeClosed(closed[i]);
      g_stats.Add(closed[i]);
     }
   if(n > 0)
     {
      g_risk.RefreshHistory();
      g_risk.UpdateLossBreakers(g_brk);
     }
   if(g_entryInFlightUntil > 0 && g_positions.Count() > 0)
      g_entryInFlightUntil = 0;
   g_reconNow = false;
  }

//+------------------------------------------------------------------+
//| Regime inputs from the context and confirmation timeframes.       |
//+------------------------------------------------------------------+
void BuildRegimeInputs(SRegimeInputs &inp)
  {
   ZeroMemory(inp);
   double atrCtx = g_ind.Atr(APEX_TF_CONTEXT);
   double atrCnf = g_ind.Atr(APEX_TF_CONFIRM);
   inp.emaFastCtx = g_ind.data[APEX_TF_CONTEXT].fast[0];
   inp.emaSlowCtx = g_ind.data[APEX_TF_CONTEXT].slow[0];
   inp.emaLongCtx = g_ind.data[APEX_TF_CONTEXT].longEma[0];
   inp.slopeNorm  = (atrCtx > 0) ? (g_ind.data[APEX_TF_CONTEXT].slow[0] - g_ind.data[APEX_TF_CONTEXT].slow[5]) / atrCtx : 0.0;
   inp.rsiCtx     = g_ind.data[APEX_TF_CONTEXT].rsi[0];
   inp.atrPercentile = g_ind.AtrPercentile(APEX_TF_CONFIRM, g_cfg.atrPctLookback);
   double hi = g_ind.data[APEX_TF_CONFIRM].rates[0].high;
   double lo = g_ind.data[APEX_TF_CONFIRM].rates[0].low;
   for(int i = 1; i < 20; i++)
     {
      hi = MathMax(hi, g_ind.data[APEX_TF_CONFIRM].rates[i].high);
      lo = MathMin(lo, g_ind.data[APEX_TF_CONFIRM].rates[i].low);
     }
   inp.returnAtr     = (atrCnf > 0) ? (g_ind.data[APEX_TF_CONFIRM].rates[0].close - g_ind.data[APEX_TF_CONFIRM].rates[20].close) / atrCnf : 0.0;
   inp.rangeWidthAtr = (atrCnf > 0) ? (hi - lo) / atrCnf : 0.0;
   inp.confirmBias   = g_confirmSt.bias;
  }

//+------------------------------------------------------------------+
//| Entry decision: Signal -> Risk -> Execution. Never bypassed.      |
//+------------------------------------------------------------------+
void ProcessDecision()
  {
   STradePlan plan;
   ZeroMemory(plan);
   ENUM_APEX_REJECT rej = APEX_REJECT_NONE;
   string detail = "";
   string status = "";
   double atrPct = g_ind.AtrPercentile(APEX_TF_ENTRY, g_cfg.atrPctLookback);

   if(g_sig.decision == APEX_DECISION_NO_TRADE)
     {
      status = "NO_TRADE";
      rej = g_sig.reject;
      detail = g_sig.detail;
     }
   else
      if(TimeCurrent() < g_entryInFlightUntil)
        {
         status = "REJECTED";
         rej = APEX_REJECT_ENTRY_IN_FLIGHT;
         detail = "previous entry not yet visible at broker";
        }
      else
         if(!g_risk.Evaluate(g_sig, g_ss, g_liq, g_entrySt, atrPct, g_brk, g_news, plan, rej, detail))
            status = "REJECTED";
         else
            if(!g_ordersPermitted)
              {
               status = "VALIDATED";   // passed every check; orders blocked by mode/lock
               detail = "not sent: " + g_permissionReason;
              }
            else
              {
               ulong ticket = 0;
               string err = "";
               string comment = "AF " + StringSubstr(ApexStrategyToString(plan.strategy), 0, 12) + " " + g_cfg.strategyVersion;
               if(g_orders.Open(plan, comment, g_brk, ticket, err))
                 {
                  status = "EXECUTED";
                  if(ticket > 0)
                     g_positions.Register(ticket, plan, g_sig, g_orders, g_brk);
                  else
                    {
                     g_entryInFlightUntil = TimeCurrent() + 30;
                     g_reconNow = true;
                    }
                  g_log.LogTradeOpened(ticket, plan, g_sig);
                 }
               else
                 {
                  status = "ORDER_FAILED";
                  rej = APEX_REJECT_ORDER_FAILED;
                  detail = err;
                 }
              }

   g_lastStatus = status;
   g_lastRejectText = (rej != APEX_REJECT_NONE) ? ApexRejectToString(rej) : "";
   g_log.LogSignal(g_sig, plan, status, rej, detail, atrPct);
  }

//+------------------------------------------------------------------+
//| ANALYSIS PATH                                                     |
//+------------------------------------------------------------------+
void RunAnalysis(const bool newBar)
  {
   if(!g_ind.RefreshAll())
     {
      g_needAnalysis = true;
      g_dataFailures++;
      g_brk.Set(APEX_BRK_MARKET_DATA, g_dataFailures >= 3, "indicator or rate data unavailable");
      return;
     }
   g_dataFailures = 0;
   g_brk.Set(APEX_BRK_MARKET_DATA, false, "");
   g_needAnalysis = false;

   datetime now = TimeCurrent();
   g_session.Evaluate(now, g_ss);
   int depth = g_ind.Depth();
   ApexAnalyzeStructure(g_ind.data[APEX_TF_CONFIRM].rates, depth, g_cfg.swingStrength, 20, g_confirmSt);
   ApexAnalyzeStructure(g_ind.data[APEX_TF_ENTRY].rates, depth, g_cfg.swingStrength, 20, g_entrySt);
   ApexAnalyzeLiquidity(g_ind.data[APEX_TF_ENTRY].rates, depth, g_entrySt, g_ind.PrevDayHigh(), g_ind.PrevDayLow(),
                        g_ss.sessionStartServer, g_ind.Atr(APEX_TF_ENTRY), g_liq);

   datetime confirmBar = g_ind.data[APEX_TF_CONFIRM].lastRefresh;
   if(confirmBar != g_lastConfirmBar)
     {
      g_lastConfirmBar = confirmBar;
      ENUM_APEX_REGIME old = g_regime.Regime();
      SRegimeInputs inp;
      BuildRegimeInputs(inp);
      if(g_regime.Update(inp, now))
         ApexLog(APEX_LOG_INFO, "REGIME_CHANGE",
                 StringFormat("SYMBOL=%s FROM=%s TO=%s VOTE=%d ATR_PCT=%.0f STRUCTURE=%s", g_cfg.symbol,
                              ApexRegimeToString(old), ApexRegimeToString(g_regime.Regime()), g_regime.Vote(),
                              inp.atrPercentile, ApexBiasToString(g_confirmSt.bias)));
      g_regime.State(g_rs);
     }

   g_signal.Evaluate(g_cfg, g_ind, g_confirmSt, g_entrySt, g_liq, g_rs, g_ss, g_sig);
   MqlTick tick;
   if(SymbolInfoTick(g_cfg.symbol, tick))
      g_sig.spreadPoints = (tick.ask - tick.bid) / SymbolInfoDouble(g_cfg.symbol, SYMBOL_POINT);

   // Entries are decided only on a bar that closed while the EA was running,
   // never on the first evaluation after a (re)start.
   if(newBar && !g_firstAnalysis)
     {
      g_risk.RefreshHistory();
      ProcessDecision();
     }
   else
      g_lastStatus = "ANALYZED";
   g_firstAnalysis = false;
  }

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
string Money(const double v)
  {
   string cur = AccountInfoString(ACCOUNT_CURRENCY);
   string s = DoubleToString(v, 2) + " " + cur;
   if(ApexIsCentCurrency(cur))
      s += StringFormat(" (%.2f)", v / 100.0);
   return s;
  }

void AddRow(string &labels[], string &values[], color &colors[], int &n, const string l, const string v, const color c)
  {
   ArrayResize(labels, n + 1);
   ArrayResize(values, n + 1);
   ArrayResize(colors, n + 1);
   labels[n] = l;
   values[n] = v;
   colors[n] = c;
   n++;
  }

void UpdateDashboard()
  {
   if(!g_dash.Enabled())
      return;
   string labels[], values[];
   color colors[];
   int n = 0;
   color text = C'215,220,230', muted = C'140,150,170', good = clrLimeGreen, bad = clrTomato, warn = clrGold;
   bool live = (g_cfg.mode == APEX_MODE_LIVE);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyPnl = g_risk.DailyPnL();
   double dd = (g_peakEquity > 0) ? (g_peakEquity - equity) / g_peakEquity * 100.0 : 0.0;
   double balMain = ApexToMainCurrency(balance);
   double progress = (g_cfg.targetBalance > g_cfg.startingBalance) ?
                     (balMain - g_cfg.startingBalance) / (g_cfg.targetBalance - g_cfg.startingBalance) * 100.0 : 0.0;

   AddRow(labels, values, colors, n, "APEXFLOW  " + APEX_CODE_VERSION, "", clrDeepSkyBlue);
   if(live)
      AddRow(labels, values, colors, n, "!!! LIVE MODE - REAL MONEY AT RISK !!!", "", clrRed);
   AddRow(labels, values, colors, n, "MODE:", ApexModeToString(g_cfg.mode), live ? clrRed : (g_cfg.mode == APEX_MODE_DEMO ? warn : good));
   AddRow(labels, values, colors, n, "SYMBOL:", g_cfg.symbol + "  #" + IntegerToString(g_cfg.magic), text);
   AddRow(labels, values, colors, n, "SESSION:", ApexSessionToString(g_ss.session) + (g_ss.entriesAllowed ? "" : " (no entries)"), text);
   AddRow(labels, values, colors, n, "REGIME:", ApexRegimeToString(g_rs.regime) + StringFormat(" (vote %+d)", g_rs.vote), text);
   AddRow(labels, values, colors, n, "BUY SCORE:", StringFormat("%.0f", g_sig.buy.total), g_sig.decision == APEX_DECISION_BUY ? good : text);
   AddRow(labels, values, colors, n, "SELL SCORE:", StringFormat("%.0f", g_sig.sell.total), g_sig.decision == APEX_DECISION_SELL ? good : text);
   string decision = ApexDecisionToString(g_sig.decision);
   if(g_lastStatus != "" && g_lastStatus != "NO_TRADE" && g_lastStatus != "ANALYZED")
      decision += " / " + g_lastStatus;
   if(g_lastRejectText != "")
      decision += " (" + g_lastRejectText + ")";
   AddRow(labels, values, colors, n, "DECISION:", decision, g_sig.decision == APEX_DECISION_NO_TRADE ? muted : good);
   AddRow(labels, values, colors, n, "BALANCE:", Money(balance), text);
   AddRow(labels, values, colors, n, "EQUITY:", Money(equity), text);
   AddRow(labels, values, colors, n, "DAILY P/L:", Money(dailyPnl), dailyPnl < 0 ? bad : text);
   AddRow(labels, values, colors, n, "DRAWDOWN:", StringFormat("%.2f%% (from peak since start)", dd), dd > 0 ? warn : text);

   string posText = "NONE";
   string strategy = ApexStrategyToString(g_sig.strategy);
   SPositionTrack t;
   if(g_positions.Get(0, t) && PositionSelectByTicket(t.ticket))
     {
      MqlTick tick;
      SymbolInfoTick(g_cfg.symbol, tick);
      double px = (t.dir == APEX_DIR_BUY) ? tick.bid : tick.ask;
      posText = StringFormat("%s %.2f %s %+.2fR", ApexDirToString(t.dir), PositionGetDouble(POSITION_VOLUME),
                             ApexPosStateToString(t.state), ApexProfitR(t.dir, t.entry, px, t.riskDist));
      if(g_positions.Count() > 1)
         posText += StringFormat(" (+%d more)", g_positions.Count() - 1);
      strategy = ApexStrategyToString(t.strategy);
     }
   AddRow(labels, values, colors, n, "OPEN POSITION:", posText, text);
   AddRow(labels, values, colors, n, "RISK:", StringFormat("%.2f%% per trade", g_cfg.riskPct), text);
   double prot = g_positions.ProtectedProfit();
   AddRow(labels, values, colors, n, "PROTECTED PROFIT:", prot > 0 ? Money(prot) : "N/A", prot > 0 ? good : muted);
   AddRow(labels, values, colors, n, "STRATEGY:", strategy, text);
   AddRow(labels, values, colors, n, "START / TARGET:", StringFormat("%.2f / %.2f (milestone only)", g_cfg.startingBalance, g_cfg.targetBalance), muted);
   AddRow(labels, values, colors, n, "PROGRESS:", StringFormat("%.1f%%", progress), muted);
   AddRow(labels, values, colors, n, "ORDERS:", (g_ordersPermitted ? "PERMITTED" : "BLOCKED") + " - " + g_permissionReason,
          g_ordersPermitted ? (live ? clrRed : good) : warn);
   AddRow(labels, values, colors, n, "VERSION:", APEX_CODE_VERSION + " / strategy " + g_cfg.strategyVersion, muted);

   string system = "READY";
   color sysColor = good;
   if(!g_risk.MicroFeasible())
     {
      system = "INSUFFICIENT CAPITAL FOR VALID TRADE";
      sysColor = bad;
     }
   else
      if(g_brk.AnyActive())
        {
         system = "BLOCKED: " + g_brk.Describe();
         sysColor = bad;
        }
      else
         if(!g_ind.Ready())
           {
            system = "LOADING DATA";
            sysColor = warn;
           }
         else
            if(!g_ss.entriesAllowed)
              {
               system = "READY - WAITING FOR SESSION";
               sysColor = muted;
              }
   AddRow(labels, values, colors, n, "SYSTEM:", system, sysColor);
   if(!g_risk.MicroFeasible())
      AddRow(labels, values, colors, n, "", StringFormat("needs ~%s equity at %.2f%% risk", Money(g_risk.MicroRequiredEquity()), g_cfg.riskPct), bad);

   g_dash.Render(labels, values, colors, n, live);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   ConfigLoad(g_cfg);
   g_apexLogLevel = g_cfg.logLevel;

   string error = "", warnings = "";
   if(!ConfigValidate(g_cfg, error, warnings))
     {
      PrintFormat("%s EVENT=INIT_FAILED REASON=%s", APEX_LOG_TAG, error);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(warnings != "")
      ApexLog(APEX_LOG_INFO, "CONFIG_WARNING", "DETAIL=" + warnings);

   if(!SymbolSelect(g_cfg.symbol, true))
     {
      PrintFormat("%s EVENT=INIT_FAILED REASON=symbol_not_found SYMBOL=%s ERROR=%d", APEX_LOG_TAG, g_cfg.symbol, GetLastError());
      return INIT_PARAMETERS_INCORRECT;
     }
   double minVol = SymbolInfoDouble(g_cfg.symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(g_cfg.symbol, SYMBOL_VOLUME_STEP);
   double tick   = SymbolInfoDouble(g_cfg.symbol, SYMBOL_TRADE_TICK_SIZE);
   double point  = SymbolInfoDouble(g_cfg.symbol, SYMBOL_POINT);
   if(minVol <= 0 || step <= 0 || tick <= 0 || point <= 0)
     {
      PrintFormat("%s EVENT=INIT_FAILED REASON=symbol_specification_unreadable SYMBOL=%s", APEX_LOG_TAG, g_cfg.symbol);
      return INIT_FAILED;
     }
   ApexLog(APEX_LOG_INFO, "BROKER_SPEC",
           StringFormat("SYMBOL=%s VOL_MIN=%.2f VOL_MAX=%.2f VOL_STEP=%.2f TICK_SIZE=%g TICK_VALUE=%g STOPS_LEVEL=%I64d FREEZE_LEVEL=%I64d CONTRACT=%g DIGITS=%I64d CURRENCY=%s LEVERAGE=%I64d MARGIN_MODE=%s",
                        g_cfg.symbol, minVol, SymbolInfoDouble(g_cfg.symbol, SYMBOL_VOLUME_MAX), step, tick,
                        SymbolInfoDouble(g_cfg.symbol, SYMBOL_TRADE_TICK_VALUE),
                        SymbolInfoInteger(g_cfg.symbol, SYMBOL_TRADE_STOPS_LEVEL),
                        SymbolInfoInteger(g_cfg.symbol, SYMBOL_TRADE_FREEZE_LEVEL),
                        SymbolInfoDouble(g_cfg.symbol, SYMBOL_TRADE_CONTRACT_SIZE),
                        SymbolInfoInteger(g_cfg.symbol, SYMBOL_DIGITS), AccountInfoString(ACCOUNT_CURRENCY),
                        AccountInfoInteger(ACCOUNT_LEVERAGE),
                        (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "HEDGING" : "NETTING")));

   ConfigTrackChanges(g_cfg);

   g_brk.Init(g_cfg.symbol);
   if(!g_ind.Init(g_cfg))
      return INIT_FAILED;
   g_session.Init(g_cfg);
   g_regime.Reset();
   g_orders.Init(g_cfg);
   g_positions.Init(g_cfg);
   g_log.Init(g_cfg);
   g_stats.Init(g_cfg.symbol, g_cfg.magic, AccountInfoDouble(ACCOUNT_BALANCE));
   g_news = GetPointer(g_newsNone);
   g_risk.Init(g_cfg);

   ZeroMemory(g_ss);
   ZeroMemory(g_rs);
   ZeroMemory(g_confirmSt);
   ZeroMemory(g_entrySt);
   ZeroMemory(g_liq);
   ZeroMemory(g_sig);
   g_rs.regime = APEX_REGIME_UNKNOWN;
   g_needAnalysis = true;
   g_firstAnalysis = true;
   g_lastConfirmBar = 0;

   // Restart recovery: rebuild state from the positions that actually exist.
   RunReconciliation(true);
   g_risk.UpdateLossBreakers(g_brk);

   g_lastDay    = ApexDayStart(TimeCurrent());
   g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   RefreshPermission();

   bool showDash = g_cfg.showDashboard && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
   g_dash.Init("APEXFLOW_" + IntegerToString(g_cfg.magic) + "_", g_cfg.dashboardFontSize, showDash);

   if(!EventSetTimer(1))
      ApexLogError("OnInit", g_cfg.symbol, "EventSetTimer", GetLastError(), "timer unavailable");

   ApexLog(APEX_LOG_INFO, "INIT",
           StringFormat("VERSION=%s STRATEGY_VERSION=%s SYMBOL=%s MAGIC=%I64d MODE=%s RISK=%.2f%% TF=%s/%s/%s TRACKED=%d",
                        APEX_CODE_VERSION, g_cfg.strategyVersion, g_cfg.symbol, g_cfg.magic, ApexModeToString(g_cfg.mode),
                        g_cfg.riskPct, EnumToString(g_cfg.tfContext), EnumToString(g_cfg.tfConfirm),
                        EnumToString(g_cfg.tfEntry), g_positions.Count()));
   if(g_cfg.mode == APEX_MODE_LIVE)
      ApexLog(APEX_LOG_INFO, "LIVE_MODE_SELECTED", "real-money orders are possible once every safeguard passes");
   UpdateDashboard();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_dash.Destroy();
   g_ind.Release();
   g_news = NULL;
   if(!MQLInfoInteger(MQL_TESTER))
      g_stats.Publish("_live");
   ApexLog(APEX_LOG_INFO, "DEINIT", StringFormat("SYMBOL=%s REASON=%d", g_cfg.symbol, reason));
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- FAST PATH
   MqlTick tick;
   bool priceOk = SymbolInfoTick(g_cfg.symbol, tick) && tick.bid > 0 && tick.ask > 0 && tick.ask >= tick.bid;
   g_brk.Set(APEX_BRK_INVALID_PRICE, !priceOk, "invalid bid/ask");
   if(!priceOk)
      return;

   if(g_reconNow)
      RunReconciliation(false);

   g_positions.Manage(g_orders, g_brk, g_ind.Atr(APEX_TF_ENTRY), g_entrySt, g_rs.regime);

   //--- ANALYSIS PATH (new entry bar only)
   bool newBar = g_ind.IsNewBar(APEX_TF_ENTRY);
   if(newBar || g_needAnalysis)
      RunAnalysis(newBar);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   g_timerTicks++;
   RefreshPermission();

   if(g_timerTicks % 60 == 1)
      g_brk.Set(APEX_BRK_CLOCK, !g_session.UpdateAutoOffset(), "server clock offset could not be determined");

   datetime day = ApexDayStart(TimeCurrent());
   if(day != g_lastDay)
     {
      g_lastDay = day;
      g_brk.OnNewDay();
      g_orders.ResetFailures();
      g_risk.RefreshHistory();
      ApexLog(APEX_LOG_INFO, "NEW_TRADING_DAY", "SYMBOL=" + g_cfg.symbol + " DATE=" + TimeToString(day, TIME_DATE));
     }

   if(g_reconNow || g_timerTicks % 5 == 0)
      RunReconciliation(false);
   if(g_timerTicks % 30 == 0)
      g_risk.RefreshHistory();
   g_risk.UpdateLossBreakers(g_brk);
   if(g_timerTicks % 60 == 2 && g_ind.Ready())
      g_risk.CheckMicroAccount(g_ind.Atr(APEX_TF_ENTRY));

   // Stale data: no fresh quote for too long while the clock moves on.
   MqlTick tick;
   if(SymbolInfoTick(g_cfg.symbol, tick) && tick.time > 0)
     {
      long age = (long)TimeTradeServer() - (long)tick.time;
      g_brk.Set(APEX_BRK_STALE_DATA, age > g_cfg.staleDataSeconds, StringFormat("last quote %I64d s old", age));
      if(g_ind.Ready() && g_sig.atr > 0)
        {
         double spread = tick.ask - tick.bid;
         g_brk.Set(APEX_BRK_ABNORMAL_SPREAD, spread > 3.0 * g_sig.atr * g_cfg.maxSpreadPctATR / 100.0,
                   StringFormat("spread %.1f%% of ATR", 100.0 * spread / g_sig.atr));
        }
     }

   g_peakEquity = MathMax(g_peakEquity, AccountInfoDouble(ACCOUNT_EQUITY));
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == g_cfg.symbol)
      g_reconNow = true;
  }

//+------------------------------------------------------------------+
//| Strategy Tester: report + custom optimization criterion.          |
//+------------------------------------------------------------------+
double OnTester()
  {
   RunReconciliation(false);
   g_stats.Publish("_tester");
   PrintFormat("%s REPORT tester: profit=%.2f equity_dd_rel=%.2f%% trades=%.0f profit_factor=%.2f",
               APEX_LOG_TAG, TesterStatistics(STAT_PROFIT), TesterStatistics(STAT_EQUITY_DDREL_PERCENT),
               TesterStatistics(STAT_TRADES), TesterStatistics(STAT_PROFIT_FACTOR));
   return g_stats.Criterion();
  }
//+------------------------------------------------------------------+
