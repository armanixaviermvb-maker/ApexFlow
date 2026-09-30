"""Tests for the research layer (stdlib unittest; run: python -m unittest discover -s tests)."""

from __future__ import annotations

import csv
import math
import sys
import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from apexflow_research.journal import Trade, load_signals, load_trades  # noqa: E402
from apexflow_research.metrics import compute_metrics, format_report  # noqa: E402
from apexflow_research.researcher import VALIDATION_GATES, ApexFlowResearcher  # noqa: E402
from apexflow_research.walkforward import tester_ini, walk_forward_windows, write_walk_forward_plan  # noqa: E402

T0 = datetime(2026, 1, 5, 8, 0)


def make_trade(i: int, profit: float, r: float, session="LONDON", strategy="TREND_PULLBACK",
               regime="TREND_UP", direction="BUY") -> Trade:
    open_t = T0 + timedelta(hours=i)
    return Trade(str(i), "EURUSD", direction, strategy, regime, session, open_t, open_t + timedelta(minutes=30),
                 30.0, 1.1, 1.101, 1.099, 0.01, 1.0, profit, r, "take_profit" if profit > 0 else "stop_loss",
                 80, 30, "1.0.0")


class MetricsTest(unittest.TestCase):
    def test_empty(self):
        m = compute_metrics([])
        self.assertEqual(m.total_trades, 0)
        self.assertIsNone(m.profit_factor)

    def test_basic_metrics(self):
        trades = [make_trade(0, 2.0, 2.0), make_trade(1, -1.0, -1.0), make_trade(2, -1.0, -1.0), make_trade(3, 2.0, 2.0)]
        m = compute_metrics(trades, start_balance=10.0)
        self.assertEqual(m.total_trades, 4)
        self.assertEqual(m.winning_trades, 2)
        self.assertEqual(m.losing_trades, 2)
        self.assertAlmostEqual(m.win_rate, 50.0)
        self.assertAlmostEqual(m.net_profit, 2.0)
        self.assertAlmostEqual(m.gross_profit, 4.0)
        self.assertAlmostEqual(m.gross_loss, 2.0)
        self.assertAlmostEqual(m.profit_factor, 2.0)
        self.assertAlmostEqual(m.expectancy, 0.5)
        self.assertAlmostEqual(m.average_r, 0.5)
        self.assertAlmostEqual(m.average_win, 2.0)
        self.assertAlmostEqual(m.average_loss, -1.0)
        # equity 10 -> 12 -> 11 -> 10 -> 12 : max drawdown 2 from peak 12
        self.assertAlmostEqual(m.max_drawdown, 2.0)
        self.assertAlmostEqual(m.max_drawdown_pct, 2.0 / 12.0 * 100)
        self.assertEqual(m.longest_loss_streak, 2)
        self.assertEqual(m.longest_win_streak, 1)
        self.assertIsNone(m.sharpe_r)  # fewer than 30 trades
        self.assertEqual(m.by_session["LONDON"].trades, 4)

    def test_all_wins_profit_factor_inf(self):
        m = compute_metrics([make_trade(0, 1.0, 1.0)])
        self.assertTrue(math.isinf(m.profit_factor))

    def test_sharpe_when_enough_trades(self):
        trades = [make_trade(i, 1.0 if i % 2 else -0.5, 1.0 if i % 2 else -0.5) for i in range(40)]
        m = compute_metrics(trades)
        self.assertIsNotNone(m.sharpe_r)
        self.assertIn("Profit factor", format_report(m))


class WalkForwardTest(unittest.TestCase):
    def test_windows_do_not_overlap_oos(self):
        ws = walk_forward_windows(date(2024, 1, 1), date(2025, 1, 1), is_months=6, oos_months=2)
        # IS Jan-Jul/OOS Jul-Sep, IS Mar-Sep/OOS Sep-Nov, IS May-Nov/OOS Nov-Jan; the next OOS would pass the end.
        self.assertEqual(len(ws), 3)
        for w in ws:
            self.assertEqual(w.is_end, w.oos_start)
            self.assertLess(w.is_start, w.oos_start)
            self.assertLessEqual(w.oos_end, date(2025, 1, 1))
        self.assertEqual(ws[0].oos_start, date(2024, 7, 1))
        self.assertEqual(ws[1].is_start, date(2024, 3, 1))

    def test_invalid_lengths(self):
        with self.assertRaises(ValueError):
            walk_forward_windows(date(2024, 1, 1), date(2025, 1, 1), 0, 1)

    def test_ini_uses_real_ticks_and_test_mode(self):
        ini = tester_ini(symbol="EURUSDm", from_date=date(2024, 1, 1), to_date=date(2024, 7, 1), deposit=3,
                         inputs={"InpRiskPerTradePercent": "1.0"})
        self.assertIn("Model=4", ini)
        self.assertIn("Symbol=EURUSDm", ini)
        self.assertIn("InpTradingMode=0", ini)
        self.assertIn("FromDate=2024.01.01", ini)

    def test_write_plan(self):
        ws = walk_forward_windows(date(2024, 1, 1), date(2024, 12, 1), 6, 2)
        with tempfile.TemporaryDirectory() as d:
            paths = write_walk_forward_plan(d, "XAUUSDm", ws, deposit=300)
            self.assertEqual(len(paths), 2 * len(ws))
            self.assertIn("Optimization=2", paths[0].read_text())
            self.assertIn("Optimization=0", paths[1].read_text())


class ResearcherTest(unittest.TestCase):
    def test_needs_minimum_sample(self):
        r = ApexFlowResearcher(min_trades=30)
        self.assertEqual(r.generate([make_trade(i, 1, 1) for i in range(10)]), [])

    def test_finds_clearly_better_group_with_pending_gates(self):
        trades = []
        for i in range(60):  # London: consistently positive
            trades.append(make_trade(i, 1.0, 1.0 if i % 3 else 0.5, session="LONDON"))
        for i in range(60, 120):  # New York: consistently negative
            trades.append(make_trade(i, -1.0, -1.0 if i % 3 else -0.5, session="NEW_YORK"))
        hyps = ApexFlowResearcher(min_trades=30).generate(trades)
        groups = {h.group for h in hyps}
        self.assertIn("LONDON", groups)
        self.assertIn("NEW_YORK", groups)
        for h in hyps:
            self.assertEqual(h.status, "proposed")
            self.assertEqual(tuple(h.gates), VALIDATION_GATES)
            self.assertTrue(all(v == "pending" for v in h.gates.values()))
            self.assertFalse(h.approved)

    def test_no_hypothesis_without_edge(self):
        trades = [make_trade(i, 1.0 if i % 2 else -1.0, 1.0 if i % 2 else -1.0,
                             session="LONDON" if i % 4 < 2 else "NEW_YORK") for i in range(80)]
        hyps = ApexFlowResearcher(min_trades=30).generate(trades)
        self.assertEqual([h for h in hyps if h.dimension == "session"], [])


class JournalTest(unittest.TestCase):
    def test_roundtrip_csv(self):
        header = ("trade_id,symbol,direction,strategy,regime,session,open_time,close_time,duration_min,entry,exit,"
                  "initial_sl,volume,risk_money,profit,r_multiple,exit_reason,buy_score,sell_score,strategy_version,mode")
        row = ("123,EURUSDm,BUY,TREND_PULLBACK,TREND_UP,LONDON,2026.01.05 08:00:00,2026.01.05 08:30:00,30.0,"
               "1.10000,1.10200,1.09900,0.01,1.00,2.00,2.000,take_profit,82.0,31.0,1.0.0,TEST")
        sig_header = ("time,symbol,timeframe,session,regime,decision,strategy,buy_score,sell_score,"
                      "buy_trend,buy_structure,buy_momentum,buy_liquidity,buy_volatility,buy_session,buy_confirmation,"
                      "sell_trend,sell_structure,sell_momentum,sell_liquidity,sell_volatility,sell_session,sell_confirmation,"
                      "spread_points,atr,atr_percentile,entry,sl,tp,volume,risk_money,risk_pct,status,reject_reason,detail,"
                      "strategy_version,mode")
        sig_row = ("2026.01.05 08:00:00,EURUSDm,PERIOD_M5,LONDON,TREND_UP,NO_TRADE,NONE,55.0,40.0,"
                   + ",".join(["1"] * 14) + ",12,0.0005,40,,,,,,,NO_TRADE,score_below_threshold,BUY 55 < 70,1.0.0,TEST")
        with tempfile.TemporaryDirectory() as d:
            tp = Path(d) / "trades.csv"
            tp.write_text(header + "\r\n" + row + "\r\n", encoding="latin-1")
            sp = Path(d) / "signals.csv"
            sp.write_text(sig_header + "\r\n" + sig_row + "\r\n", encoding="latin-1")
            trades = load_trades(tp)
            self.assertEqual(len(trades), 1)
            self.assertAlmostEqual(trades[0].r_multiple, 2.0)
            self.assertEqual(trades[0].open_time, datetime(2026, 1, 5, 8, 0))
            sigs = load_signals(sp)
            self.assertEqual(sigs[0].reject_reason, "score_below_threshold")
            self.assertAlmostEqual(sigs[0].atr_percentile, 40.0)
            # header columns must match what TradeLogger.mqh writes
            with open(sp, newline="", encoding="latin-1") as fh:
                self.assertEqual(len(next(csv.reader(fh))), 37)


if __name__ == "__main__":
    unittest.main()
