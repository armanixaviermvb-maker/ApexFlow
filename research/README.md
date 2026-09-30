# ApexFlow research layer (optional)

Offline Python tools for studying ApexFlow's journals and Strategy Tester runs.
**The EA never needs Python to trade**, and nothing here can change the EA.
Standard library only — no packages to install (Python 3.10+).

```
research/
  apexflow_research/   journal loader, metrics, walk-forward planner, researcher, report CLI
  tests/               python -m unittest discover -s tests
  data/                copy CSV journals here (from MT5 Common\Files\ApexFlow\)
  backtests/           generated Strategy Tester .ini files and tester reports
  experiments/         notes and parameter experiments
  reports/             generated markdown reports
```

## Where the data comes from
The EA writes to the terminal's **Common** files folder
(`%APPDATA%\MetaQuotes\Terminal\Common\Files\ApexFlow\`):

| File | Content |
|---|---|
| `signals_<symbol>_<magic>[_tester].csv` | every signal evaluation: scores and components, regime, session, spread, ATR, plan, status, rejection reason |
| `trades_<symbol>_<magic>[_tester].csv` | every closed trade: entry/exit, R multiple, exit reason, strategy, regime, session |
| `report_<symbol>_<magic>_tester.txt` | performance report written by `OnTester` |

## Report
```
cd research
python -m apexflow_research.report --trades data/trades_EURUSDm_26093002_tester.csv \
    --signals data/signals_EURUSDm_26093002_tester.csv --start-balance 3 --out reports/eurusd.md
```

## Walk-forward plan
```python
from datetime import date
from apexflow_research.walkforward import walk_forward_windows, write_walk_forward_plan
ws = walk_forward_windows(date(2024, 1, 1), date(2026, 1, 1), is_months=6, oos_months=2)
write_walk_forward_plan("backtests/eurusd_wf", "EURUSDm", ws, deposit=300, currency="USD")
```
Run each file with `terminal64.exe /config:"<file>.ini"`. In-sample files run an optimisation
(custom criterion from `OnTester`); out-of-sample files run the chosen parameters **unchanged**.

## ApexFlow Researcher
`ApexFlowResearcher.generate(trades, signals)` proposes hypotheses such as
*"TREND_PULLBACK during LONDON performed better than the baseline (avg +0.45R vs +0.10R over 64 trades, t=2.6)"*.

Rules:
- Minimum 30 trades per group, a clear edge (≥ 0.2R) and |t| ≥ 2 — otherwise nothing is proposed.
- Every hypothesis starts with five **pending** gates:
  1. historical backtest, 2. out-of-sample validation, 3. walk-forward test,
  4. demo/paper evaluation, 5. human approval.
- The researcher only writes text/JSON. It has no access to the EA, its inputs or the terminal.
  A change reaches the EA only when a human edits the inputs, bumps `StrategyVersion`
  and records the reason in `ChangeReason` (the EA logs old → new values).

No LLM is integrated. Many hypotheses will be noise: multiple comparisons across
sessions/strategies/regimes produce false positives, which is exactly why the gates exist.
