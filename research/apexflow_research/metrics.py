"""Performance metrics (mirrors Logging/PerformanceStats.mqh in the EA).

These numbers describe past trades only. They are not a forecast.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from .journal import Trade


@dataclass
class GroupStats:
    trades: int = 0
    wins: int = 0
    net: float = 0.0
    sum_r: float = 0.0

    @property
    def win_rate(self) -> float:
        return 100.0 * self.wins / self.trades if self.trades else 0.0

    @property
    def avg_r(self) -> float:
        return self.sum_r / self.trades if self.trades else 0.0


@dataclass
class Metrics:
    total_trades: int = 0
    winning_trades: int = 0
    losing_trades: int = 0
    win_rate: float = 0.0
    net_profit: float = 0.0
    gross_profit: float = 0.0
    gross_loss: float = 0.0
    profit_factor: float | None = None
    average_win: float = 0.0
    average_loss: float = 0.0
    expectancy: float = 0.0
    average_r: float = 0.0
    max_drawdown: float = 0.0
    max_drawdown_pct: float = 0.0
    sharpe_r: float | None = None
    longest_win_streak: int = 0
    longest_loss_streak: int = 0
    average_duration_min: float = 0.0
    average_mae_r: float = 0.0
    average_mfe_r: float = 0.0
    total_r: float = 0.0
    trades_per_week: float = 0.0
    longest_gap_hours: float = 0.0   # longest time between consecutive entries (includes weekends)
    median_gap_hours: float = 0.0
    by_session: dict[str, GroupStats] = field(default_factory=dict)
    by_strategy: dict[str, GroupStats] = field(default_factory=dict)
    by_regime: dict[str, GroupStats] = field(default_factory=dict)
    by_direction: dict[str, GroupStats] = field(default_factory=dict)


def _add(groups: dict[str, GroupStats], key: str, t: Trade) -> None:
    g = groups.setdefault(key, GroupStats())
    g.trades += 1
    g.wins += 1 if t.is_win else 0
    g.net += t.profit
    g.sum_r += t.r_multiple


def compute_metrics(trades: list[Trade], start_balance: float = 0.0) -> Metrics:
    m = Metrics()
    n = len(trades)
    m.total_trades = n
    if n == 0:
        return m

    equity = peak = start_balance
    cur_w = cur_l = 0
    r_values = []
    for t in sorted(trades, key=lambda x: x.close_time):
        m.net_profit += t.profit
        r_values.append(t.r_multiple)
        m.average_duration_min += t.duration_min
        m.average_mae_r += t.mae_r
        m.average_mfe_r += t.mfe_r
        if t.profit > 0:
            m.winning_trades += 1
            m.gross_profit += t.profit
            cur_w, cur_l = cur_w + 1, 0
        else:
            if t.profit < 0:
                m.losing_trades += 1
                m.gross_loss += -t.profit
            cur_l, cur_w = cur_l + 1, 0
        m.longest_win_streak = max(m.longest_win_streak, cur_w)
        m.longest_loss_streak = max(m.longest_loss_streak, cur_l)
        equity += t.profit
        peak = max(peak, equity)
        dd = peak - equity
        m.max_drawdown = max(m.max_drawdown, dd)
        if peak > 0:
            m.max_drawdown_pct = max(m.max_drawdown_pct, dd / peak * 100.0)
        _add(m.by_session, t.session, t)
        _add(m.by_strategy, t.strategy, t)
        _add(m.by_regime, t.regime, t)
        _add(m.by_direction, t.direction, t)

    m.win_rate = 100.0 * m.winning_trades / n
    if m.gross_loss > 0:
        m.profit_factor = m.gross_profit / m.gross_loss
    elif m.gross_profit > 0:
        m.profit_factor = math.inf
    m.average_win = m.gross_profit / m.winning_trades if m.winning_trades else 0.0
    m.average_loss = -m.gross_loss / m.losing_trades if m.losing_trades else 0.0
    m.expectancy = m.net_profit / n
    m.average_r = sum(r_values) / n
    m.average_duration_min /= n
    m.average_mae_r /= n
    m.average_mfe_r /= n
    m.total_r = sum(r_values)
    opens = sorted(t.open_time for t in trades)
    span_weeks = max((max(t.close_time for t in trades) - opens[0]).total_seconds() / (7 * 86400), 1.0)
    m.trades_per_week = n / span_weeks
    gaps = sorted((b - a).total_seconds() / 3600 for a, b in zip(opens, opens[1:]))
    if gaps:
        m.longest_gap_hours = gaps[-1]
        mid = len(gaps) // 2
        m.median_gap_hours = gaps[mid] if len(gaps) % 2 else (gaps[mid - 1] + gaps[mid]) / 2
    if n >= 30:
        mean = m.average_r
        var = sum((r - mean) ** 2 for r in r_values) / n
        sd = math.sqrt(var)
        m.sharpe_r = mean / sd * math.sqrt(n) if sd > 0 else None
    return m


def format_report(m: Metrics, title: str = "ApexFlow performance") -> str:
    def pf(v: float | None) -> str:
        if v is None:
            return "n/a"
        return "inf" if math.isinf(v) else f"{v:.2f}"

    lines = [
        f"# {title}",
        "",
        "_Past results only. Not a forecast; no profitability is implied._",
        "",
        "| Metric | Value |",
        "|---|---|",
        f"| Total trades | {m.total_trades} |",
        f"| Winning / losing | {m.winning_trades} / {m.losing_trades} |",
        f"| Win rate | {m.win_rate:.1f}% |",
        f"| Net profit | {m.net_profit:.2f} |",
        f"| Gross profit / loss | {m.gross_profit:.2f} / {-m.gross_loss:.2f} |",
        f"| Profit factor | {pf(m.profit_factor)} |",
        f"| Average win / loss | {m.average_win:.2f} / {m.average_loss:.2f} |",
        f"| Expectancy per trade | {m.expectancy:.2f} |",
        f"| Average R | {m.average_r:.3f} |",
        f"| Max drawdown (closed trades) | {m.max_drawdown:.2f} ({m.max_drawdown_pct:.2f}%) |",
        f"| Sharpe (per trade, R) | {pf(m.sharpe_r) if m.sharpe_r is not None else 'n/a (<30 trades)'} |",
        f"| Longest win / loss streak | {m.longest_win_streak} / {m.longest_loss_streak} |",
        f"| Average duration | {m.average_duration_min:.1f} min |",
        f"| Average adverse / favourable excursion | {m.average_mae_r:.2f}R / {m.average_mfe_r:.2f}R |",
        f"| Total R | {m.total_r:+.2f} |",
        f"| Trades per week | {m.trades_per_week:.1f} |",
        f"| Longest / median gap between entries | {m.longest_gap_hours:.0f}h / {m.median_gap_hours:.0f}h |",
    ]
    for name, groups in (
        ("Session", m.by_session),
        ("Strategy", m.by_strategy),
        ("Regime", m.by_regime),
        ("Direction", m.by_direction),
    ):
        lines += ["", f"## By {name.lower()}", "", f"| {name} | Trades | Win rate | Net | Avg R |", "|---|---|---|---|---|"]
        for key in sorted(groups):
            g = groups[key]
            lines.append(f"| {key} | {g.trades} | {g.win_rate:.1f}% | {g.net:.2f} | {g.avg_r:.2f} |")
    return "\n".join(lines) + "\n"


def target_tradeoff(trades: list[Trade], targets: tuple[float, ...] = (0.5, 0.75, 1.0, 1.5, 2.0, 3.0)) -> list[dict]:
    """Estimate win rate and average R if every trade had used a fixed target of T R.

    Uses each trade's MFE/MAE. The journal does not record which came first, so a
    trade that reached BOTH +T and -1R is ambiguous: the optimistic estimate counts
    it as a win, the pessimistic one as a full loss. Trades that never reached +T
    keep their actual result. Costs are already inside the recorded R multiples.
    """
    rows = []
    n = len(trades)
    for t_r in targets:
        opt_r = pes_r = 0.0
        opt_w = pes_w = 0
        for t in trades:
            if t.mfe_r >= t_r:
                ambiguous = t.mae_r <= -1.0
                opt_r += t_r
                opt_w += 1
                if ambiguous:
                    pes_r += -1.0
                else:
                    pes_r += t_r
                    pes_w += 1
            else:
                opt_r += t.r_multiple
                pes_r += t.r_multiple
                opt_w += 1 if t.r_multiple > 0 else 0
                pes_w += 1 if t.r_multiple > 0 else 0
        rows.append({
            "target_r": t_r,
            "win_rate_optimistic": 100.0 * opt_w / n if n else 0.0,
            "win_rate_pessimistic": 100.0 * pes_w / n if n else 0.0,
            "avg_r_optimistic": opt_r / n if n else 0.0,
            "avg_r_pessimistic": pes_r / n if n else 0.0,
        })
    return rows


def format_tradeoff(rows: list[dict]) -> str:
    lines = ["## Target trade-off (estimated from MFE/MAE)", "",
             "Win rate alone is not the goal: pick the target with the best average R you trust.", "",
             "| Target | Win rate (pess. - opt.) | Avg R per trade (pess. - opt.) |", "|---|---|---|"]
    for r in rows:
        lines.append(f"| {r['target_r']:.2f}R | {r['win_rate_pessimistic']:.0f}% - {r['win_rate_optimistic']:.0f}% | "
                     f"{r['avg_r_pessimistic']:+.3f} - {r['avg_r_optimistic']:+.3f} |")
    return "\n".join(lines) + "\n"
