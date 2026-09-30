# ApexFlow MT5 — guidance for Claude Code sessions

ApexFlow is a native MQL5 Expert Advisor (`MQL5/Experts/ApexFlow/ApexFlow.mq5`).
The full specification is the "APEXFLOW MT5 — MASTER BUILD PROMPT" (60 sections);
decisions already made are recorded in `docs/PHASE1_ENVIRONMENT.md`.

## Workflow (decided: option C — local Windows development)
- Development happens on the user's Windows PC where MetaTrader 5 / MetaEditor are installed.
- Build in phases (Section 57). After EVERY phase: compile with `scripts/compile.ps1`,
  fix all errors, review warnings, run relevant test scripts, document in `docs/PHASES.md`.
- Never claim compilation, testing or profitability that did not actually happen.
- Stop and ask the user before starting each new phase.

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
