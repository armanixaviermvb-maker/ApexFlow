# ApexFlow MT5 — guidance for Claude Code sessions

ApexFlow is a native MQL5 Expert Advisor (`MQL5/Experts/ApexFlow/ApexFlow.mq5`).
The full specification is the "APEXFLOW MT5 — MASTER BUILD PROMPT" (60 sections);
decisions already made are recorded in `docs/PHASE1_ENVIRONMENT.md`.

## Workflow
- Code is written in a cloud Claude Code session (no MetaEditor there) and pushed to
  branch `claude/great-johnson-dtai9s`. The user pulls on their Windows PC and compiles with
  `scripts/compile.ps1` (or F7 in MetaEditor), then pastes compiler output back.
- Phases 1-18 were all written before any compile, at the user's request ("compile in the
  end"). Current step: the user compiles everything once and pastes the full compiler output;
  fix every error, then have them run TestConfig/TestCore/TestBroker. Track status in `docs/PHASES.md`.
- Never claim compilation, testing or profitability that did not actually happen.
- Python research tests: `cd research && python3 -m unittest discover -s tests`.

## Non-negotiable rules
- Default mode is TEST. Real orders require `EnableTrading=true` AND `TradingMode=LIVE`
  AND `ConfirmLiveTrading=true`.
- No martingale, loss doubling, revenge sizing, averaging down, or risk escalation — ever.
- The target balance ($270) is a dashboard metric only; it must never influence entries or size.
- Every trade has a validated stop loss. If a broker-valid, risk-controlled position is not
  possible → NO_TRADE ("INSUFFICIENT CAPITAL FOR VALID TRADE"). Never round volume up to the broker minimum.
- Flow is always Signal → Risk → Execution validation → Order. No component bypasses another.
- Indicators/structure read closed bars only (no look-ahead). Heavy analysis on new bar; fast path on tick.
- Only manage positions with our MagicNumber and symbol.
- No credentials in code, comments or logs.

## Brokers and symbols
- Brokers: Exness and Deriv (MT5), standard and cent/micro accounts.
- Symbols vary by account suffix (Exness Standard `XAUUSDm`, Standard Cent `XAUUSDc`, others no suffix).
  Never hard-code names; resolve from a base name + suffix input and verify with `SymbolSelect`/`SymbolInfo*`.
- Initial universe: XAUUSD, EURUSD, USDJPY, GBPUSD. Exclude Deriv synthetic indices.
- Account currency may be USC (cent). All money math must use deposit-currency tick value from the
  broker, never assume USD.

## Layout
```
MQL5/Experts/ApexFlow/   EA source (Section 40 structure, relative #include "...")
MQL5/Scripts/ApexFlowTests/  MQL5 test scripts
research/                optional Python research layer (never needed to trade)
docs/                    architecture, phase log, test plan
scripts/compile.ps1      MetaEditor command-line compile
```
