# ApexFlow Auction Rejection Strategy (`AUCTION_REJECTION`)

**Status: research hypothesis. Disabled by default (`EnableAuctionRejection = false`).**
Nothing here claims or implies profitability, and no external win rates are assumed.
The module exists so that backtesting and forward testing can decide whether it adds
measurable value to ApexFlow. Keep it only if the evidence says so (see §6).

## 1. Idea
Price reaches a high-value structural location (a deep pullback into a swing leg).
Aggressive participation against the trade shows up, but price fails to move in
proportion to it (absorption). Control then shifts to the other side, and structure
confirms it. The Fibonacci zone is **only a location filter**; it never triggers an entry on its own.

## 2. Pipeline and gates
Each stage is a gate. The first gate that fails is logged as the NO_TRADE reason.

| Stage | BUY rule (SELL is the mirror) | NO_TRADE reason |
|---|---|---|
| Environment | regime TREND_UP; RANGE/LOW_VOL only if `ARAllowRange`; HIGH_VOL only in the vote direction (+10 score); never in TRANSITION | `regime_*` |
| Location | leg = confirmed swing low → highest **unexceeded** confirmed swing high (leg timeframe, default M15), leg ≥ `ARMinLegATR` × ATR; pullback reached the 70.5% level; price still below 50% of the leg | `location_invalid` |
| Invalidation | any close beyond the 88.6% level by more than `ARDecisiveBreakATR` × ATR since the high | `setup_invalidated` |
| Participation | the absorption window (bars 1..3) trades inside the zone, and opposing effort is ≥ `AREffortMin` × baseline (bars 4..23) | `absorption_weak` |
| Absorption | `AbsorptionScore` ≥ `ARMinAbsorption` | `absorption_weak` |
| Dominance shift | `DominanceShiftScore` ≥ `ARMinDominance` on the response bar (bar 0) | `dominance_shift_absent` |
| Structure | the confirmation timeframe is not bearish, and structure score ≥ 0.5 (micro-swing break, or higher low plus a close above the previous high) | `structure_contradictory` / `no_structure_confirmation` |
| Signal score | weighted score ≥ `ARMinScore` (+ regime surcharge), and beats the opposite AR score by the minimum gap | `score_below_threshold` / `scores_too_close` |
| Risk | unchanged RiskEngine: session, spread, volatility, stop distance, sizing, margin, breakers | as in the base EA |

A wick beyond 88.6% without a decisive close is **not** invalidation. It scores a reduced
location score of 0.6.

## 3. Scores
**AbsorptionScore (0–100)** = 100 × (0.40·E + 0.35·(1 − result) + 0.25·rejection)
- E = (effortRatio − 1) / 1.5, clamped to 0..1. effortRatio = mean opposing effort in the window ÷ baseline.
- result = actual closing-basis move in the effort direction ÷ the move expected if price
  responded in proportion to effort (baseline body × bars × effortRatio), clamped to 0..1.
- rejection = the best window bar's 0.5 × wick fraction + 0.5 × close location.
- ×0.7 if the window spread is more than 2× the baseline spread (e.g. rollover). The score is
  capped at 40 when effort is not elevated.

**DominanceShiftScore (0–100)** = strong close (15) + engulfing (15) + higher low (15)
+ micro-swing break (25, or 10 for a close above the previous bar) + displacement up to
0.5 ATR (15) + rising activity in the trade direction (15) + broker-book imbalance
(+10, NATIVE live only), capped at 100.

**Signal score (0–100)**, with configurable weights (defaults shown; not assumed optimal):

| Environment | Location | Absorption | Dominance | Structure | Session | Volatility |
|---|---|---|---|---|---|---|
| 15 | 20 | 25 | 20 | 10 | 5 | 5 |

The AR score is separate from the base score model. The two only meet when the signal
engine picks the best valid setup.

## 4. Order-flow modes: what the data is and is not
| Mode | Participation | Directional split | Label in logs |
|---|---|---|---|
| `PROXY` (default) | tick volume | candle excursion (open→low = selling push, open→high = buying push) or tick rule (bid upticks vs downticks, `CopyTicksRange`) | `PROXY:TICK_VOLUME+CANDLE_EXCURSION` / `+TICK_RULE` |
| `NATIVE` | broker real volume, if the symbol publishes it; otherwise the proxy | as above | `NATIVE:BROKER_REAL_VOLUME…` |
| `NATIVE` + market book (live only) | adds a broker-local book imbalance to the dominance score | — | `+NATIVE:BROKER_BOOK(not centralized)` |

- Forex/CFD **tick volume is the number of price updates from one broker's feed**. It is not
  traded volume and not institutional order flow.
- A Forex/CFD **market book shows only the broker's own liquidity**. It is not a centralized
  exchange book. The Strategy Tester has no book history, so NATIVE silently uses the proxy there.
- Every candidate row records `participation_source`, so the logs never present proxy data as real order flow.

## 5. Stop, target, management
- **Stop:** beyond the invalidation point. For a BUY: min(pullback extreme, 88.6% level) − `StopATRBuffer` × ATR.
  The RiskEngine still enforces the ATR bounds, broker stop and freeze levels, and 2× spread.
- **Target:** the leg's swing extreme (`ARTargetMode = SWING`) or the global take-profit settings.
  `ARMinRewardR` (default 1.0) rejects setups whose structural target is too close. No reward/risk ratio is guaranteed.
- **Management:** the existing rules apply: protection at +1R, optional partial at +1.5R,
  trailing from +2R (ATR, structure, or hybrid), and a stop that never moves backwards.

## 6. Testing protocol: BASE vs BASE + AUCTION_REJECTION
1. Generate the A/B plan. Each window gets two runs with identical inputs except the switch:
   ```python
   from datetime import date
   from apexflow_research.walkforward import walk_forward_windows, write_ab_plan
   ws = walk_forward_windows(date(2023, 1, 1), date(2026, 1, 1), is_months=6, oos_months=2)
   write_ab_plan("backtests/ar_ab", "EURUSDm", ws, deposit=300)
   ```
2. Run every `.ini` (`terminal64.exe /config:<file>`), using every tick based on real ticks.
   The journals land in `Common\Files\ApexFlow\` as `trades_<sym>_<magic>_base_wf00_tester.csv` and so on.
3. Compare:
   ```
   python -m apexflow_research.compare --base data/trades_*_base_wf*_tester.csv \
       --variant data/trades_*_ar_wf*_tester.csv --start-balance 3 --out reports/ar_vs_base.md
   ```
4. Repeat for each symbol (XAUUSD, EURUSD, USDJPY, GBPUSD) and read the session and regime tables:
   trending, ranging, high and low volatility; London, New York and overlap.

**Keep criteria** (all must pass; otherwise the verdict is REJECT or INSUFFICIENT_EVIDENCE):
- ≥ 30 AR trades and ≥ 3 out-of-sample windows
- average R improves; profit factor is not lower
- max drawdown is no worse than +20% relative or +2 percentage points, whichever is larger
- AR trades have positive expectancy on their own
- the variant is ≥ base in at least 60% of windows, and the gain survives removing the best window (overfitting guard)

Even a `CANDIDATE` verdict then needs demo/paper evaluation and human approval. Enabling the
strategy live means bumping `StrategyVersion` and recording `ChangeReason`.

The comparison reports profit factor, expectancy, max drawdown, average R, win rate, trade
count, session and regime performance, and average adverse and favourable excursion (MAE/MFE, in R).

## 7. Candidate log (`auction_<symbol>_<magic>[_tag][_tester].csv`)
One row per direction on each bar where a swing leg exists: time, symbol, session, regime,
direction, swing high/low, the three zone levels, pullback extreme, location status,
participation, baseline, effort ratio, price displacement, result ratio, effort/result ratio,
every component score, the AR buy/sell scores, the final base buy/sell scores, the decision
and its strategy, status, gate rejection, final rejection, participation source and strategy version.

## 8. Known limitations
- Proxies can be fooled: tick volume rises with quote activity, news and spread changes. The spread penalty only partly addresses this.
- MAE/MFE are measured on the ticks the EA saw while the position was tracked. After a restart they resume from the last saved values.
- The swing-leg choice (highest unexceeded confirmed swing within the cached ~125 bars) is a design choice worth testing against alternatives.
- Fixed default thresholds (effort ×1.3, absorption 50, dominance 50, score 70) are starting points, not tuned values.
