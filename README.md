# ApexFlow MT5

ApexFlow is a session-aware, adaptive MetaTrader 5 Expert Advisor (MQL5). It looks for
high-quality entries during the London and New York sessions, manages positions
dynamically, and records every decision for later research.

> **Status:** all 18 phases are written but **not yet compiled**; see `docs/PHASES.md`.
> No part of this project claims or implies profitability. Every trade can lose money.

## Safety at a glance
- Defaults to **TEST** mode. Real orders need `TradingMode=LIVE` + `EnableTrading=true` +
  `ConfirmLiveTrading=true` + a real account.
- No martingale, loss doubling, averaging down or risk escalation. Hard caps: 2 % risk/trade,
  10 % daily loss.
- Every trade has a stop-loss. Position size is rounded **down**; if the broker minimum
  would exceed the risk budget, the EA shows *INSUFFICIENT CAPITAL FOR VALID TRADE*.
- `NO_TRADE` is the default decision.
- The $3 → $270 target is a dashboard milestone only.

## Single-file EA (simplest)
`dist/ApexFlow.mq5` is the whole EA in **one file**. Copy it to
`<DataFolder>\MQL5\Experts\` (MT5 → File → Open Data Folder), open it in MetaEditor and press F7.
It is generated from the modular sources with `python3 scripts/bundle.py`; edit the sources, not this file.

## Quick start (Windows, MetaTrader 5)
1. Clone this repo and check out the working branch.
2. Link the folders into your terminal's data folder (MT5 → File → Open Data Folder):
   ```
   mklink /J "<DataFolder>\MQL5\Experts\ApexFlow" "<clone>\MQL5\Experts\ApexFlow"
   mklink /J "<DataFolder>\MQL5\Scripts\ApexFlowTests" "<clone>\MQL5\Scripts\ApexFlowTests"
   ```
3. Compile `ApexFlow.mq5` and the three test scripts in MetaEditor (F7).
4. Run `TestConfig`, `TestCore` and `TestBroker` scripts and check the Experts tab.
5. Strategy Tester → demo → small live, following `docs/DEPLOYMENT.md`.

## Documentation
| File | Content |
|---|---|
| `docs/PHASES.md` | build log, architecture, design decisions, limitations |
| `docs/TESTING.md` | compile/test instructions and Section 54 coverage |
| `docs/DEPLOYMENT.md` | demo checklist, live safeguards, what the EA never does |
| `docs/AUCTION_REJECTION.md` | optional AUCTION_REJECTION strategy (research hypothesis) and its A/B test protocol |
| `docs/PHASE1_ENVIRONMENT.md` | environment, brokers, symbols, $3 analysis |
| `research/README.md` | optional Python research layer |
