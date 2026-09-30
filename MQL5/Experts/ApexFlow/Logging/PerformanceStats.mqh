//+------------------------------------------------------------------+
//| PerformanceStats.mqh - trade statistics for OnTester and reports  |
//|                                                                   |
//| Fed with every closed ApexFlow trade. Produces the Section 45     |
//| metrics overall and per session / strategy / regime / direction.  |
//| Statistics describe the past only; they are not a forecast.       |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_PERFORMANCESTATS_MQH
#define APEXFLOW_PERFORMANCESTATS_MQH

#include "../Types.mqh"
#include "../Utils.mqh"

struct SGroupStat
  {
   int               n;
   int               wins;
   double            net;
   double            sumR;
  };

class CPerformanceStats
  {
private:
   SClosedTrade      m_trades[];
   double            m_startBalance;
   string            m_symbol;
   long              m_magic;

   void              AddGroup(SGroupStat &g, const SClosedTrade &t) const
     {
      g.n++;
      if(t.profit > 0)
         g.wins++;
      g.net  += t.profit;
      g.sumR += t.rMultiple;
     }

   string            GroupLine(const string name, const SGroupStat &g) const
     {
      if(g.n == 0)
         return name + ": no trades";
      return StringFormat("%s: trades=%d win_rate=%.1f%% net=%.2f avg_R=%.2f",
                          name, g.n, 100.0 * g.wins / g.n, g.net, g.sumR / g.n);
     }

public:
                     CPerformanceStats(void) : m_startBalance(0), m_symbol(""), m_magic(0) {}

   void              Init(const string symbol, const long magic, const double startBalance)
     {
      m_symbol = symbol;
      m_magic = magic;
      m_startBalance = startBalance;
      ArrayResize(m_trades, 0);
     }

   void              Add(const SClosedTrade &t)
     {
      int n = ArraySize(m_trades);
      ArrayResize(m_trades, n + 1);
      m_trades[n] = t;
     }

   int               Count(void) const { return ArraySize(m_trades); }

   double            ExpectancyR(void) const
     {
      int n = ArraySize(m_trades);
      if(n == 0)
         return 0.0;
      double s = 0;
      for(int i = 0; i < n; i++)
         s += m_trades[i].rMultiple;
      return s / n;
     }

   //--- Optimization criterion: expectancy (R) weighted by sqrt(trades).
   //--- Returns 0 below 30 trades: too few to mean anything.
   double            Criterion(void) const
     {
      int n = ArraySize(m_trades);
      if(n < 30)
         return 0.0;
      return ExpectancyR() * MathSqrt((double)n);
     }

   //--- Human-readable report lines.
   int               Report(string &lines[]) const
     {
      ArrayResize(lines, 0);
      int n = ArraySize(m_trades);
      int wins = 0, losses = 0;
      double gp = 0, gl = 0, net = 0, sumR = 0, sumR2 = 0, sumWin = 0, sumLoss = 0, sumMinutes = 0;
      int curW = 0, curL = 0, maxW = 0, maxL = 0;
      double equity = m_startBalance, peak = m_startBalance, maxDD = 0, maxDDPct = 0;
      SGroupStat bySession[APEX_SESSION_COUNT], byStrategy[APEX_STRAT_COUNT], byRegime[APEX_REGIME_COUNT], byDir[2];
      for(int k = 0; k < APEX_SESSION_COUNT; k++)
         ZeroMemory(bySession[k]);
      for(int k = 0; k < APEX_STRAT_COUNT; k++)
         ZeroMemory(byStrategy[k]);
      for(int k = 0; k < APEX_REGIME_COUNT; k++)
         ZeroMemory(byRegime[k]);
      ZeroMemory(byDir[0]);
      ZeroMemory(byDir[1]);

      for(int i = 0; i < n; i++)
        {
         double p = m_trades[i].profit;
         net += p;
         sumR += m_trades[i].rMultiple;
         sumR2 += m_trades[i].rMultiple * m_trades[i].rMultiple;
         if(m_trades[i].closeTime > m_trades[i].openTime)
            sumMinutes += (double)(m_trades[i].closeTime - m_trades[i].openTime) / 60.0;
         if(p > 0)
           {
            wins++;
            gp += p;
            sumWin += p;
            curW++;
            curL = 0;
           }
         else
           {
            if(p < 0)
              {
               losses++;
               gl += -p;
               sumLoss += -p;
              }
            curL++;
            curW = 0;
           }
         maxW = (int)MathMax(maxW, curW);
         maxL = (int)MathMax(maxL, curL);
         equity += p;
         peak = MathMax(peak, equity);
         double dd = peak - equity;
         if(dd > maxDD)
            maxDD = dd;
         if(peak > 0 && dd / peak * 100.0 > maxDDPct)
            maxDDPct = dd / peak * 100.0;

         int s = (int)m_trades[i].session;
         if(s >= 0 && s < APEX_SESSION_COUNT)
            AddGroup(bySession[s], m_trades[i]);
         int st = (int)m_trades[i].strategy;
         if(st >= 0 && st < APEX_STRAT_COUNT)
            AddGroup(byStrategy[st], m_trades[i]);
         int rg = (int)m_trades[i].regime;
         if(rg >= 0 && rg < APEX_REGIME_COUNT)
            AddGroup(byRegime[rg], m_trades[i]);
         AddGroup(byDir[m_trades[i].dir == APEX_DIR_BUY ? 0 : 1], m_trades[i]);
        }

      string out[];
      int c = 0;
      ArrayResize(out, 64);
      out[c++] = StringFormat("ApexFlow performance - %s magic %I64d", m_symbol, m_magic);
      out[c++] = "Past results only. Not a forecast; no profitability is implied.";
      out[c++] = StringFormat("Total trades: %d", n);
      out[c++] = StringFormat("Winning trades: %d", wins);
      out[c++] = StringFormat("Losing trades: %d", losses);
      out[c++] = StringFormat("Win rate: %.1f%%", n > 0 ? 100.0 * wins / n : 0.0);
      out[c++] = StringFormat("Net profit: %.2f", net);
      out[c++] = StringFormat("Gross profit: %.2f", gp);
      out[c++] = StringFormat("Gross loss: %.2f", -gl);
      out[c++] = "Profit factor: " + (gl > 0 ? DoubleToString(gp / gl, 2) : (gp > 0 ? "inf" : "n/a"));
      out[c++] = StringFormat("Average win: %.2f", wins > 0 ? sumWin / wins : 0.0);
      out[c++] = StringFormat("Average loss: %.2f", losses > 0 ? -sumLoss / losses : 0.0);
      out[c++] = StringFormat("Expectancy per trade: %.2f", n > 0 ? net / n : 0.0);
      out[c++] = StringFormat("Average R: %.3f", n > 0 ? sumR / n : 0.0);
      out[c++] = StringFormat("Maximum drawdown (closed trades): %.2f (%.2f%%)", maxDD, maxDDPct);
      if(n >= 30)
        {
         double mean = sumR / n;
         double var = sumR2 / n - mean * mean;
         double sd = (var > 0) ? MathSqrt(var) : 0;
         out[c++] = "Sharpe (per trade, R): " + (sd > 0 ? DoubleToString(mean / sd * MathSqrt((double)n), 2) : "n/a");
        }
      else
         out[c++] = "Sharpe (per trade, R): n/a (fewer than 30 trades)";
      out[c++] = StringFormat("Longest winning streak: %d", maxW);
      out[c++] = StringFormat("Longest losing streak: %d", maxL);
      out[c++] = StringFormat("Average trade duration: %.1f min", n > 0 ? sumMinutes / n : 0.0);
      out[c++] = GroupLine("London", bySession[APEX_SESSION_LONDON]);
      out[c++] = GroupLine("New York", bySession[APEX_SESSION_NEW_YORK]);
      out[c++] = GroupLine("Overlap", bySession[APEX_SESSION_OVERLAP]);
      out[c++] = GroupLine("Asia", bySession[APEX_SESSION_ASIA]);
      for(int k = 1; k < APEX_STRAT_COUNT; k++)
         out[c++] = GroupLine("Strategy " + ApexStrategyToString((ENUM_APEX_STRATEGY)k), byStrategy[k]);
      for(int k = 1; k < APEX_REGIME_COUNT; k++)
         out[c++] = GroupLine("Regime " + ApexRegimeToString((ENUM_APEX_REGIME)k), byRegime[k]);
      out[c++] = GroupLine("BUY", byDir[0]);
      out[c++] = GroupLine("SELL", byDir[1]);
      ArrayResize(out, c);
      ArrayResize(lines, c);
      for(int i = 0; i < c; i++)
         lines[i] = out[i];
      return c;
     }

   //--- Print the report and write it to Common\Files\ApexFlow\.
   void              Publish(const string suffix) const
     {
      string lines[];
      int c = Report(lines);
      for(int i = 0; i < c; i++)
         PrintFormat("%s REPORT %s", APEX_LOG_TAG, lines[i]);
      if(MQLInfoInteger(MQL_OPTIMIZATION))
         return;
      string file = "ApexFlow\\report_" + m_symbol + "_" + IntegerToString(m_magic) + suffix + ".txt";
      int h = FileOpen(file, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
      if(h == INVALID_HANDLE)
         return;
      for(int i = 0; i < c; i++)
         FileWriteString(h, lines[i] + "\r\n");
      FileClose(h);
     }
  };

#endif // APEXFLOW_PERFORMANCESTATS_MQH
