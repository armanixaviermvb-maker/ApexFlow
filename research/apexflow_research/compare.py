"""BASE APEXFLOW vs BASE APEXFLOW + AUCTION_REJECTION.

Compares two sets of trade journals produced by identical Strategy Tester runs
that differ only in `InpEnableAuctionRejection` (see walkforward.write_ab_plan).
The verdict is deliberately conservative:

    INSUFFICIENT_EVIDENCE  not enough AR trades or out-of-sample windows to judge
    REJECT                 at least one keep-criterion failed
    CANDIDATE              every criterion passed - still requires demo/paper
                           evaluation and human approval before any live use

A CANDIDATE verdict is not a claim of profitability.

    python -m apexflow_research.compare \\
        --base data/trades_EURUSDm_26093002_base_wf00_tester.csv data/..._base_wf01_tester.csv \\
        --variant data/trades_EURUSDm_26093002_ar_wf00_tester.csv data/..._ar_wf01_tester.csv \\
        --start-balance 3 --out reports/ar_vs_base.md
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass, field
from pathlib import Path

from .journal import Trade, load_trades
from .metrics import GroupStats, Metrics, compute_metrics

AR = "AUCTION_REJECTION"


@dataclass
class KeepCriteria:
    min_ar_trades: int = 30              # AR trades in the variant across all windows
    min_windows: int = 3                 # out-of-sample windows
    min_window_share: float = 0.6        # share of windows where the variant's avg R >= base
    max_dd_increase_rel: float = 0.20    # variant max DD% may exceed base by 20% (relative) ...
    max_dd_increase_abs: float = 2.0     # ... or by 2 percentage points, whichever is larger
    min_expectancy_gain_r: float = 0.0   # variant avg R must exceed base avg R by more than this


@dataclass
class Check:
    name: str
    passed: bool
    detail: str


@dataclass
class Verdict:
    status: str
    checks: list[Check] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def _avg_r(trades: list[Trade]) -> float:
    return sum(t.r_multiple for t in trades) / len(trades) if trades else 0.0


def _pf(m: Metrics) -> float:
    if m.profit_factor is None:
        return 0.0
    return m.profit_factor


def evaluate(base_windows: list[list[Trade]], variant_windows: list[list[Trade]],
             start_balance: float = 0.0, criteria: KeepCriteria | None = None,
             mode: str = "strategy") -> tuple[Metrics, Metrics, Verdict]:
    """mode="strategy": does AUCTION_REJECTION add value (default).
    mode="profile": is a more active profile better? Judged on total R per window
    (growth), not average R per trade - more trades only help if they add net R."""
    if len(base_windows) != len(variant_windows):
        raise ValueError("base and variant need the same number of windows")
    cr = criteria or KeepCriteria()
    if mode == "profile":
        return _evaluate_profile(base_windows, variant_windows, start_balance, cr)
    base_all = [t for w in base_windows for t in w]
    var_all = [t for w in variant_windows for t in w]
    mb = compute_metrics(base_all, start_balance)
    mv = compute_metrics(var_all, start_balance)
    ar_trades = [t for t in var_all if t.strategy == AR]
    v = Verdict("REJECT")
    v.notes.append("Past results only; a CANDIDATE still needs demo/paper evaluation and human approval.")

    enough_trades = len(ar_trades) >= cr.min_ar_trades
    v.checks.append(Check("enough AUCTION_REJECTION trades", enough_trades,
                          f"{len(ar_trades)} AR trades (minimum {cr.min_ar_trades})"))
    enough_windows = len(variant_windows) >= cr.min_windows
    v.checks.append(Check("enough out-of-sample windows", enough_windows,
                          f"{len(variant_windows)} windows (minimum {cr.min_windows})"))

    gain = mv.average_r - mb.average_r
    v.checks.append(Check("expectancy improves", gain > cr.min_expectancy_gain_r,
                          f"avg R {mb.average_r:+.3f} -> {mv.average_r:+.3f} ({gain:+.3f})"))
    v.checks.append(Check("profit factor not lower", _pf(mv) >= _pf(mb),
                          f"PF {_fmt(mb.profit_factor)} -> {_fmt(mv.profit_factor)}"))
    dd_limit = max(mb.max_drawdown_pct * (1 + cr.max_dd_increase_rel), mb.max_drawdown_pct + cr.max_dd_increase_abs)
    v.checks.append(Check("drawdown acceptable", mv.max_drawdown_pct <= dd_limit,
                          f"max DD {mb.max_drawdown_pct:.2f}% -> {mv.max_drawdown_pct:.2f}% (limit {dd_limit:.2f}%)"))
    ar_avg = _avg_r(ar_trades)
    v.checks.append(Check("AR trades have positive expectancy on their own", ar_avg > 0,
                          f"AR avg R {ar_avg:+.3f} over {len(ar_trades)} trades"))

    # Robustness: improvement must hold in most windows and survive removing the best window.
    diffs = []
    for bw, vw in zip(base_windows, variant_windows):
        if not bw and not vw:
            continue
        diffs.append(_avg_r(vw) - _avg_r(bw))
    share = sum(1 for d in diffs if d >= 0) / len(diffs) if diffs else 0.0
    v.checks.append(Check("consistent across windows", share >= cr.min_window_share,
                          f"variant >= base in {share:.0%} of {len(diffs)} windows (minimum {cr.min_window_share:.0%})"))
    if len(diffs) >= 2:
        best = max(range(len(diffs)), key=lambda i: diffs[i])
        rest_b = [t for i, w in enumerate(base_windows) if i != best for t in w]
        rest_v = [t for i, w in enumerate(variant_windows) if i != best for t in w]
        robust_gain = _avg_r(rest_v) - _avg_r(rest_b)
        v.checks.append(Check("not driven by a single window", robust_gain > 0,
                              f"avg R gain without the best window: {robust_gain:+.3f}"))
    else:
        v.checks.append(Check("not driven by a single window", False, "needs at least 2 windows"))

    if not (enough_trades and enough_windows):
        v.status = "INSUFFICIENT_EVIDENCE"
    elif all(c.passed for c in v.checks):
        v.status = "CANDIDATE"
    else:
        v.status = "REJECT"
    return mb, mv, v


def _evaluate_profile(base_windows, variant_windows, start_balance, cr):
    base_all = [t for w in base_windows for t in w]
    var_all = [t for w in variant_windows for t in w]
    mb = compute_metrics(base_all, start_balance)
    mv = compute_metrics(var_all, start_balance)
    v = Verdict("REJECT")
    v.notes.append("Profile comparison: past results only; a CANDIDATE still needs demo evaluation and human approval.")
    enough_trades = len(var_all) >= cr.min_ar_trades
    v.checks.append(Check("enough trades", enough_trades, f"{len(var_all)} variant trades (minimum {cr.min_ar_trades})"))
    enough_windows = len(variant_windows) >= cr.min_windows
    v.checks.append(Check("enough out-of-sample windows", enough_windows,
                          f"{len(variant_windows)} windows (minimum {cr.min_windows})"))
    v.checks.append(Check("more total R (growth)", mv.total_r > mb.total_r,
                          f"total R {mb.total_r:+.2f} -> {mv.total_r:+.2f}"))
    v.checks.append(Check("still positive expectancy", mv.average_r > 0,
                          f"avg R per trade {mb.average_r:+.3f} -> {mv.average_r:+.3f}"))
    dd_limit = max(mb.max_drawdown_pct * (1 + cr.max_dd_increase_rel), mb.max_drawdown_pct + cr.max_dd_increase_abs)
    v.checks.append(Check("drawdown acceptable", mv.max_drawdown_pct <= dd_limit,
                          f"max DD {mb.max_drawdown_pct:.2f}% -> {mv.max_drawdown_pct:.2f}% (limit {dd_limit:.2f}%)"))
    diffs = [sum(t.r_multiple for t in vw) - sum(t.r_multiple for t in bw)
             for bw, vw in zip(base_windows, variant_windows) if bw or vw]
    share = sum(1 for d in diffs if d >= 0) / len(diffs) if diffs else 0.0
    v.checks.append(Check("consistent across windows", share >= cr.min_window_share,
                          f"more total R in {share:.0%} of {len(diffs)} windows"))
    if len(diffs) >= 2:
        best = max(range(len(diffs)), key=lambda i: diffs[i])
        v.checks.append(Check("not driven by a single window", sum(diffs) - diffs[best] > 0,
                              f"total R gain without the best window: {sum(diffs) - diffs[best]:+.2f}"))
    else:
        v.checks.append(Check("not driven by a single window", False, "needs at least 2 windows"))
    v.notes.append(f"Activity: {mb.trades_per_week:.1f} -> {mv.trades_per_week:.1f} trades/week; "
                   f"longest gap {mb.longest_gap_hours:.0f}h -> {mv.longest_gap_hours:.0f}h.")
    if not (enough_trades and enough_windows):
        v.status = "INSUFFICIENT_EVIDENCE"
    elif all(c.passed for c in v.checks):
        v.status = "CANDIDATE"
    else:
        v.status = "REJECT"
    return mb, mv, v


def _fmt(x: float | None) -> str:
    if x is None:
        return "n/a"
    return "inf" if math.isinf(x) else f"{x:.2f}"


def _group_table(title: str, gb: dict[str, GroupStats], gv: dict[str, GroupStats]) -> list[str]:
    lines = ["", f"## {title}", "", "| Group | Base trades | Base avg R | Variant trades | Variant avg R |", "|---|---|---|---|---|"]
    for key in sorted(set(gb) | set(gv)):
        b = gb.get(key, GroupStats())
        v = gv.get(key, GroupStats())
        lines.append(f"| {key} | {b.trades} | {b.avg_r:+.2f} | {v.trades} | {v.avg_r:+.2f} |")
    return lines


def format_comparison(mb: Metrics, mv: Metrics, verdict: Verdict) -> str:
    rows = [
        ("Trades", f"{mb.total_trades}", f"{mv.total_trades}"),
        ("Win rate", f"{mb.win_rate:.1f}%", f"{mv.win_rate:.1f}%"),
        ("Profit factor", _fmt(mb.profit_factor), _fmt(mv.profit_factor)),
        ("Expectancy per trade", f"{mb.expectancy:.2f}", f"{mv.expectancy:.2f}"),
        ("Average R", f"{mb.average_r:+.3f}", f"{mv.average_r:+.3f}"),
        ("Max drawdown", f"{mb.max_drawdown_pct:.2f}%", f"{mv.max_drawdown_pct:.2f}%"),
        ("Avg adverse excursion (MAE)", f"{mb.average_mae_r:.2f}R", f"{mv.average_mae_r:.2f}R"),
        ("Avg favourable excursion (MFE)", f"{mb.average_mfe_r:.2f}R", f"{mv.average_mfe_r:.2f}R"),
        ("Net profit", f"{mb.net_profit:.2f}", f"{mv.net_profit:.2f}"),
        ("Total R", f"{mb.total_r:+.2f}", f"{mv.total_r:+.2f}"),
        ("Trades per week", f"{mb.trades_per_week:.1f}", f"{mv.trades_per_week:.1f}"),
        ("Longest gap between entries", f"{mb.longest_gap_hours:.0f}h", f"{mv.longest_gap_hours:.0f}h"),
    ]
    lines = [
        "# ApexFlow comparison: base vs variant",
        "",
        "_Research comparison of past, out-of-sample results. Not a forecast; no profitability is implied._",
        "",
        f"**Verdict: {verdict.status}**",
        "",
        "| Metric | Base | Base + AR |",
        "|---|---|---|",
    ]
    lines += [f"| {a} | {b} | {c} |" for a, b, c in rows]
    lines += ["", "## Keep criteria", "", "| Check | Result | Detail |", "|---|---|---|"]
    lines += [f"| {c.name} | {'pass' if c.passed else 'FAIL'} | {c.detail} |" for c in verdict.checks]
    lines += _group_table("Session performance", mb.by_session, mv.by_session)
    lines += _group_table("Regime performance", mb.by_regime, mv.by_regime)
    lines += _group_table("Strategy performance", mb.by_strategy, mv.by_strategy)
    lines += ["", "## Notes", ""] + [f"- {n}" for n in verdict.notes]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Compare base ApexFlow with base + AUCTION_REJECTION")
    ap.add_argument("--base", nargs="+", required=True, help="base trade journals, one per OOS window, in order")
    ap.add_argument("--variant", nargs="+", required=True, help="variant trade journals, same windows, same order")
    ap.add_argument("--start-balance", type=float, default=0.0)
    ap.add_argument("--mode", choices=["strategy", "profile"], default="strategy",
                    help="strategy: does AUCTION_REJECTION add value; profile: is a more active profile better")
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    base = [load_trades(p) for p in args.base]
    variant = [load_trades(p) for p in args.variant]
    mb, mv, verdict = evaluate(base, variant, args.start_balance, mode=args.mode)
    text = format_comparison(mb, mv, verdict)
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
