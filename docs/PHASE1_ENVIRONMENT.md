# Phase 1 — Environment assessment and decisions

Date: 2026-09-30

## Cloud assessment (where Phase 1 ran)
- Ubuntu 24.04 cloud container. No MetaTrader 5, no MetaEditor, no Wine.
- Nothing was compiled there. The repo held only `README.md`.

## Decision: development workflow
Initially option C (local development on the Windows PC). Revised: code is written in the cloud session and
pushed; the user pulls and compiles each phase in MetaEditor, then reports the output.

## Brokers
| Broker | Account types | Notes |
|---|---|---|
| Exness | Standard (`m` suffix, e.g. `XAUUSDm`), Standard Cent (`c` suffix, balance in USC) | Suffix must be configurable |
| Deriv  | MT5 Financial / standard | Forex + metals only; synthetic indices out of scope |

## Symbol universe (minimum 4)
| Base | Why | Caveat |
|---|---|---|
| XAUUSD | Requested; high volume, strong London/NY moves | Wide ATR — large SL in money terms; hardest for a small account |
| EURUSD | Most liquid pair, tight spread | — |
| USDJPY | "YENUSD" as quoted by the market | JPY pip = 0.01; tick value varies with price |
| GBPUSD | Very liquid in London/NY | Highly correlated with EURUSD |

Optional later: AUDUSD, USDCAD, USDCHF.

## Multi-symbol design decision
- One EA instance per chart/symbol (isolated, simpler, Strategy-Tester friendly).
- Magic number = base MagicNumber + per-symbol offset (see docs/PHASES.md, Phase 2).
- An account-level guard shared across instances (terminal global variables) enforces:
  total open positions, total daily loss, and a USD-exposure/correlation cap
  (e.g. no simultaneous same-direction EURUSD + GBPUSD by default).

## $3 account reality check (to be verified by the EA's micro-account validator)
At 1% risk, $3 allows ~$0.03 risk per trade.
- Standard account: 0.01 lot EURUSD ≈ $0.10/pip → a 0.3-pip stop would be needed. Not tradable.
  Gold is worse. Expected result: INSUFFICIENT CAPITAL FOR VALID TRADE.
- Cent account: $3 = 300 USC and contract sizes are ~100× smaller, so a normal
  structural stop at minimum volume may fit within risk. This is the only realistic path for $3.
These are approximations; the EA must decide from live `SYMBOL_*` values, not from this table.

## Local setup checklist (Windows)
1. Install MT5 from Exness and/or Deriv; log in to a DEMO account first.
2. Install Git for Windows; clone this repo and check out the development branch.
3. Link the EA and test folders into the terminal data folder (MT5 → File → Open Data Folder),
   from a Command Prompt:
   `mklink /J "<DataFolder>\MQL5\Experts\ApexFlow" "<clone>\MQL5\Experts\ApexFlow"`
   `mklink /J "<DataFolder>\MQL5\Scripts\ApexFlowTests" "<clone>\MQL5\Scripts\ApexFlowTests"`
4. Verify: `scripts\compile.ps1 -MetaEditor "<install dir>\metaeditor64.exe" -Source "<DataFolder>\MQL5\Experts\ApexFlow\ApexFlow.mq5"`
5. After each phase is pushed: `git pull`, compile, run the test script, report results.
