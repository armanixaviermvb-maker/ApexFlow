"""Command-line report.

    python -m apexflow_research.report --trades trades_EURUSDm_26093002_tester.csv \
        [--signals signals_...csv] [--start-balance 3] [--out reports/eurusd.md]
"""

from __future__ import annotations

import argparse
from pathlib import Path

from .journal import load_signals, load_trades
from .metrics import compute_metrics, format_report
from .researcher import ApexFlowResearcher


def build_report(trades_path: str, signals_path: str | None, start_balance: float) -> str:
    trades = load_trades(trades_path)
    signals = load_signals(signals_path) if signals_path else None
    text = format_report(compute_metrics(trades, start_balance), f"ApexFlow report - {Path(trades_path).name}")
    researcher = ApexFlowResearcher()
    hyps = researcher.generate(trades, signals)
    text += "\n## Hypotheses (proposed only - not applied)\n\n"
    if not hyps:
        text += f"None: need at least {researcher.min_trades} trades per group with a clear, significant difference.\n"
    for h in hyps:
        text += f"- {h.statement} Gates pending: {', '.join(h.gates)}.\n"
    if signals:
        text += "\n## Rejection reasons\n\n| Reason | Count |\n|---|---|\n"
        for reason, count in ApexFlowResearcher.rejection_summary(signals).items():
            text += f"| {reason} | {count} |\n"
    return text


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="ApexFlow research report")
    ap.add_argument("--trades", required=True)
    ap.add_argument("--signals")
    ap.add_argument("--start-balance", type=float, default=0.0)
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    text = build_report(args.trades, args.signals, args.start_balance)
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
