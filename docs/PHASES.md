# ApexFlow build log

All phases were written in a cloud session **without MetaEditor**. At the user's request,
compilation happens once at the end on the user's Windows PC. Until that compile reports
0 errors and the test scripts pass, no phase counts as verified.

| Phase | Content | Written | Compiled | Tested |
|---|---|---|---|---|
| 1 | Environment & architecture | yes | n/a | n/a |
| 2 | Project structure, configuration, live lock | yes | pending | pending (TestConfig) |
| 3 | Core types & utilities | yes | pending | pending (TestCore) |
| 4 | Market data & indicator manager | yes | pending | pending (tester) |
| 5 | Session engine (DST) | yes | pending | pending (TestCore) |
| 6 | Market structure & liquidity | yes | pending | pending (TestCore) |
| 7 | Regime engine | yes | pending | pending (TestCore) |
| 8 | Signal engine + 3 strategies | yes | pending | pending (TestCore) |
| 9 | Risk engine, circuit breakers, news interface | yes | pending | pending (TestCore/tester) |
| 10 | Order execution | yes | pending | pending (demo) |
| 11 | Position management / reconciliation | yes | pending | pending (TestCore/demo) |
| 12 | Profit protection | yes | pending | pending (TestCore/tester) |
| 13 | Dashboard | yes | pending | pending (chart) |
| 14 | Trade logging | yes | pending | pending (tester CSV) |
| 15 | Strategy Tester compatibility & metrics | yes | pending | pending (tester) |
| 16 | Test scripts + Python research layer | yes | pending | Python: 12/12 passed |
| 17 | Demo validation | checklist written | — | user (docs/DEPLOYMENT.md §2) |
| 18 | Live safeguards | implemented + checklist | pending | user (docs/DEPLOYMENT.md §3) |
| AR | AUCTION_REJECTION strategy module (research hypothesis, off by default) | yes | pending | TestCore (AR sections); Python compare 22/22 |

## Source layout
```
MQL5/Experts/ApexFlow/
  ApexFlow.mq5            orchestration: OnInit/OnTick/OnTimer/OnTradeTransaction/OnTester
  Config.mqh              inputs, SApexConfig, validation, live lock, config versioning
  Types.mqh               enums, structs, hard caps, string conversions
  Utils.mqh               DST/time, price/volume normalization, lot math, retcodes, logging
  Core/SessionEngine.mqh  server->UTC->local market time; sessions; entry buffer
  Core/StructureEngine.mqh swings, HH/HL/LH/LL, BOS, transitions, liquidity levels/sweeps
  Core/RegimeEngine.mqh   multi-factor regime with hysteresis
  Core/SignalEngine.mqh   BUY/SELL scores, regime->strategy rules, decision
  Core/RiskEngine.mqh     pre-trade checks, sizing, margin, loss limits, micro-account check
  Core/CircuitBreaker.mqh entry kill-switches
  Core/NewsFilter.mqh     INewsFilter + no-op implementation
  Strategies/             StrategyBase, TrendPullback, Breakout, Reversal, AuctionRejection
  Core/OrderFlow.mqh      participation data (PROXY / NATIVE), always labelled
  Core/EffortVsResult.mqh absorption, dominance shift, AR structure score
  Execution/OrderManager.mqh    CTrade wrapper with verification and retries
  Execution/PositionManager.mqh state machine, BE, partial, trailing, adverse regime
  Execution/Reconciliation.mqh  broker vs tracked positions
  Indicators/             IndicatorManager (closed-bar caches), ATRHelper
  UI/Dashboard.mqh        chart panel
  Logging/TradeLogger.mqh structured log + CSV journals
  Logging/PerformanceStats.mqh metrics + OnTester criterion
MQL5/Scripts/ApexFlowTests/  TestConfig, TestCore, TestBroker, TestFramework.mqh
research/                optional Python research layer
```

## Key design decisions
- **Decision cadence:** entries are evaluated once per closed entry-timeframe bar; never on
  the first evaluation after a restart (prevents re-entering an already-used signal).
  Position management runs on every tick.
- **Regime → strategies:** TREND_UP: BUY pullback/breakout only. TREND_DOWN: SELL only.
  RANGE: reversal/breakout both ways. HIGH_VOL: pullback in vote direction, +10 score.
  LOW_VOL: breakout/reversal, +5. TRANSITION: none (optional pullback, +10). UNKNOWN: none.
- **Scores:** 7 weighted components (default 20/20/15/15/10/10/10), each 0..1, total 0..100,
  computed independently for BUY and SELL. Decision needs threshold + gap + concrete setup.
- **Stops:** structure (+ATR buffer), ATR, or hybrid (structure widened to ≥ 0.5 ATR).
  Wider than 3 ATR → NO TRADE rather than a smaller position with a meaningless stop.
- **Sizing:** equity × risk% ÷ (loss per lot from `OrderCalcProfit`), rounded down.
- **Exposure:** max positions per symbol and across ApexFlow; no opposite position; optional
  block on same-direction USD exposure across charts (e.g. BUY EURUSD + BUY GBPUSD).
- **Netting accounts:** entries blocked while the symbol has any position.
- **Persistence:** initial SL/volume/risk/flags per position in terminal global variables
  (`AF.<ticket>.*`); daily P/L and loss streak rebuilt from broker deal history.
- **Protective operations** (modify SL, partial close, close) are allowed in every mode; only
  opening positions is subject to the live lock.
- **AUCTION_REJECTION** has its own gates and 0..100 score model; base strategies keep theirs.
  It is disabled by default so BASE vs BASE + AR can be compared with one switch
  (`docs/AUCTION_REJECTION.md`). Positions record MAE/MFE for that comparison.
- **Journals** go to the Common files folder so tester and live runs are both reachable by the
  research layer.

## Known limitations / to verify on first compile and demo
- Not compiled. Expect a first round of compiler fixes.
- Session times assume the default broker offset handling; verify the tester's manual
  server offset for your broker.
- Strategy logic is a reasonable first version, **not an optimised or proven edge**.
- News filter is an interface only (no calendar integration yet).
- Correlation control is limited to USD-direction matching.
