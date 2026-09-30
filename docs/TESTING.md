# ApexFlow testing

Nothing here proves profitability. Tests show that the logic does what it is
specified to do; only out-of-sample, walk-forward and demo results say anything
about performance, and even those are no guarantee.

## 1. Compile (MetaEditor)
Compile each file (F7 or `scripts\compile.ps1 -Source <file>`), expect **0 errors**:

| File | Kind |
|---|---|
| `MQL5\Experts\ApexFlow\ApexFlow.mq5` | the EA |
| `MQL5\Scripts\ApexFlowTests\TestConfig.mq5` | test script |
| `MQL5\Scripts\ApexFlowTests\TestCore.mq5` | test script |
| `MQL5\Scripts\ApexFlowTests\TestBroker.mq5` | broker check script |

Review every warning; unused-parameter warnings in strategy modules are expected.

## 2. Offline logic tests (scripts, no orders)
Drag each script onto any chart; results are in the **Experts** tab.

| Script | Expected last line |
|---|---|
| TestConfig | `TestConfig: N passed, 0 failed` |
| TestCore | `TestCore: N passed, 0 failed  -> ALL PASSED` |
| TestBroker | one line per symbol + summary (see §4) |

## 3. Section 54 coverage map
| Requirement | Where it is tested |
|---|---|
| Position sizing | TestCore `TestVolume` (budget never exceeded, $3 case) + TestBroker (live spec) |
| Broker volume normalization | TestCore `TestVolume` (round down, min/max/step) |
| Stop-loss calculation | TestCore `TestStops` (structure/ATR/hybrid, too wide, wrong side) |
| Spread filter | Strategy Tester + journal `spread_too_high` rejections (needs live quotes) |
| Session detection | TestCore `TestSessions` (London/NY/overlap/weekend/end buffer) |
| DST handling | TestCore `TestDst` (2025/2026 EU and US transitions, server offset) |
| Regime classification | TestCore `TestRegime` (+ hysteresis) |
| Signal scoring | TestCore `TestScoring` (bounds, symmetry, session weight) |
| BUY / SELL / NO_TRADE decision | TestCore `TestDecisions` |
| Invalidation after direction change | TestCore `TestDecisions` ("adaptive" cases) |
| Daily loss limit | Strategy Tester / demo: journal `daily_loss_limit`, breaker log (uses broker history) |
| Consecutive losses | Strategy Tester / demo: `LOSS_STREAK` breaker log (uses broker history) |
| Partial close | TestCore `TestProtection` (volume rules) + tester visual mode |
| Break-even | TestCore `TestProtection` + tester `SL_MOVED REASON=break_even` |
| Trailing stop / never backwards | TestCore `TestProtection` + tester `SL_MOVED REASON=trailing` |
| Broker rejection | TestCore retcode classification; demo: `OPERATION_FAILED` + `ORDER_FAILURES` breaker |
| Position reconciliation | TestCore `TestReconcileAndRetcodes`; demo restart test (§6) |
| AUCTION_REJECTION location / invalidation | TestCore `TestAuctionLocation` (zone levels, 88.6% invalidation, wick vs decisive close, extended/small leg, SELL mirror) |
| Effort vs result / dominance shift | TestCore `TestEffortAndDominance` (absorption vs follow-through, no elevated effort, spread penalty, mirror) |
| AR decisions / BASE unchanged when off | TestCore `TestAuctionDecisions` |
| BASE vs BASE + AR comparison | Python `compare` tests (insufficient evidence, reject, candidate, single-window overfit, drawdown) |

## 4. Micro-account ($3) check
Run **TestBroker** on each broker/account you intend to use, with the exact symbol names
(e.g. `XAUUSDm,EURUSDm,USDJPYm,GBPUSDm` on Exness Standard, `...c` on Standard Cent).
Each symbol reports `TRADABLE` or `INSUFFICIENT CAPITAL FOR VALID TRADE` with the balance
it would need. The EA uses the same math and refuses untradable setups.

## 5. Strategy Tester
- Model: **Every tick based on real ticks**; timeframe of the chart = entry timeframe (M5).
- Deposit/currency matching the real account (USD 3, or USC 300 for a cent account).
- Server time: the tester cannot auto-detect the broker's GMT offset, so the EA uses the
  manual inputs there (`Server GMT offset` + `Server DST rule`). Set them to match your broker:
  compare the Market Watch server clock with UTC once in live and note the offset.
- Keep `TradingMode = TEST` (tester orders are simulated regardless).
- After the run: Journal tab shows `REPORT ...` lines; CSVs are in `Common\Files\ApexFlow\`.
- Look-ahead: all indicator/rate reads start at bar 1 (last closed bar); verify in visual mode
  that decisions appear only at bar open after the signal bar closed.

## 6. Demo validation (Phase 17)
See `docs/DEPLOYMENT.md`.
