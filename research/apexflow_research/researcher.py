"""ApexFlow Researcher - hypothesis generation from trade history.

Rule-based (no LLM). It reads journals and proposes hypotheses such as
"TREND_PULLBACK during LONDON performed better than average".

It can NEVER change live trading logic. Every hypothesis is created with the
five mandatory validation gates in state "pending":

    1. historical_backtest
    2. out_of_sample
    3. walk_forward
    4. demo_evaluation
    5. human_approval

Only a human can mark the gates as passed, and only then may a new
StrategyVersion be prepared (see research/README.md).
"""

from __future__ import annotations

import json
import math
from collections import Counter
from dataclasses import asdict, dataclass, field
from datetime import timedelta

from .journal import Signal, Trade

VALIDATION_GATES = (
    "historical_backtest",
    "out_of_sample",
    "walk_forward",
    "demo_evaluation",
    "human_approval",
)


@dataclass
class Hypothesis:
    statement: str
    dimension: str
    group: str
    trades: int
    group_avg_r: float
    baseline_avg_r: float
    t_stat: float
    status: str = "proposed"
    gates: dict[str, str] = field(default_factory=lambda: {g: "pending" for g in VALIDATION_GATES})

    @property
    def approved(self) -> bool:
        return all(v == "passed" for v in self.gates.values())


def _mean_sd(values: list[float]) -> tuple[float, float]:
    n = len(values)
    if n == 0:
        return 0.0, 0.0
    mean = sum(values) / n
    var = sum((v - mean) ** 2 for v in values) / (n - 1) if n > 1 else 0.0
    return mean, math.sqrt(var)


class ApexFlowResearcher:
    """Finds groups whose R-multiples differ clearly from the baseline."""

    def __init__(self, min_trades: int = 30, min_edge_r: float = 0.2, min_t: float = 2.0):
        self.min_trades = min_trades
        self.min_edge_r = min_edge_r
        self.min_t = min_t

    def _dimensions(self, trades: list[Trade], signals: list[Signal] | None) -> dict[str, dict[str, list[float]]]:
        dims: dict[str, dict[str, list[float]]] = {"session": {}, "strategy": {}, "regime": {}, "direction": {}, "strategy@session": {}}
        for t in trades:
            dims["session"].setdefault(t.session, []).append(t.r_multiple)
            dims["strategy"].setdefault(t.strategy, []).append(t.r_multiple)
            dims["regime"].setdefault(t.regime, []).append(t.r_multiple)
            dims["direction"].setdefault(t.direction, []).append(t.r_multiple)
            dims["strategy@session"].setdefault(f"{t.strategy} during {t.session}", []).append(t.r_multiple)
        if signals:
            dims["atr_percentile"] = {}
            executed = [s for s in signals if s.status == "EXECUTED"]
            for t in trades:
                match = None
                for s in executed:
                    if s.time <= t.open_time <= s.time + timedelta(minutes=15):
                        match = s
                if match is None:
                    continue
                bucket = f"ATR percentile {int(match.atr_percentile // 25) * 25}-{int(match.atr_percentile // 25) * 25 + 25}"
                dims["atr_percentile"].setdefault(bucket, []).append(t.r_multiple)
        return dims

    def generate(self, trades: list[Trade], signals: list[Signal] | None = None) -> list[Hypothesis]:
        if len(trades) < self.min_trades:
            return []
        baseline = [t.r_multiple for t in trades]
        base_mean, _ = _mean_sd(baseline)
        out: list[Hypothesis] = []
        for dim, groups in self._dimensions(trades, signals).items():
            for group, values in groups.items():
                n = len(values)
                if n < self.min_trades or n == len(trades):
                    continue
                mean, sd = _mean_sd(values)
                edge = mean - base_mean
                if abs(edge) < self.min_edge_r or sd == 0:
                    continue
                t_stat = edge / (sd / math.sqrt(n))
                if abs(t_stat) < self.min_t:
                    continue
                word = "better" if edge > 0 else "worse"
                out.append(
                    Hypothesis(
                        statement=(f"{group} performed {word} than the baseline "
                                   f"(avg {mean:+.2f}R vs {base_mean:+.2f}R over {n} trades, t={t_stat:.1f})."),
                        dimension=dim,
                        group=group,
                        trades=n,
                        group_avg_r=round(mean, 4),
                        baseline_avg_r=round(base_mean, 4),
                        t_stat=round(t_stat, 2),
                    )
                )
        out.sort(key=lambda h: -abs(h.t_stat))
        return out

    @staticmethod
    def rejection_summary(signals: list[Signal]) -> dict[str, int]:
        return dict(Counter(s.reject_reason for s in signals if s.reject_reason).most_common())

    @staticmethod
    def to_json(hypotheses: list[Hypothesis]) -> str:
        return json.dumps([asdict(h) for h in hypotheses], indent=2)
