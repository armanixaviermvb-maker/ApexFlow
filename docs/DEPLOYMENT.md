# ApexFlow deployment: demo first, then small controlled live

Compilation is not validation, and a good backtest is not a forecast. Follow the steps in
order and do not skip any. You can stop at any step and nothing is lost.

| Step | What | Exit criterion |
|---|---|---|
| 1 | Compile | 0 errors, warnings reviewed |
| 2 | Static inspection | code review done, no martingale/averaging (see §4) |
| 3 | Script tests | TestConfig + TestCore all passed; TestBroker run per broker |
| 4 | Strategy Tester | runs without errors on all 4 symbols, report produced |
| 5 | Historical + walk-forward | out-of-sample results reviewed (research layer) |
| 6 | Demo account | ≥ 4 weeks, ≥ 50 trades, checklist §2 passed |
| 7 | Small controlled live | only after 1–6; minimum risk; checklist §3 |

## 1. Chart setup
One chart per symbol (e.g. XAUUSDm, EURUSDm, USDJPYm, GBPUSDm), timeframe **M5**, ApexFlow
attached to each with the same `MagicNumber` base (per-symbol offsets are automatic).
Enable **Algo Trading** in the terminal and "Allow Algo Trading" on the EA's Common tab.

## 2. Phase 17 - Demo validation checklist
Mode `DEMO`, `EnableTrading = true`, on a **demo** account.

- [ ] Dashboard shows `MODE: DEMO`, `ORDERS: PERMITTED - DEMO mode on demo account`.
- [ ] Session changes at the expected local times (London 08:00, New York 08:00 local),
      including the week(s) around a DST change.
- [ ] `REGIME_CHANGE` log lines appear and look sensible on the chart.
- [ ] Most bars end in `NO_TRADE` with a reason in the signals CSV (expected).
- [ ] Every opened position has a stop-loss (`TRADE_OPENED ... SL=`), none without.
- [ ] Break-even, partial close (or `PARTIAL_SKIPPED` on min-lot positions) and trailing
      appear in the log; SL never moves backwards.
- [ ] Restart test: with a position open, close and reopen the terminal. Log shows
      `POSITION_RECOVERED ... SOURCE=saved_state`; no duplicate position is opened.
- [ ] Manual-trade test: open a manual trade on the same symbol; ApexFlow does not touch it.
- [ ] Mismatch test: open a second position with ApexFlow's magic (e.g. via another copy of
      the EA with MaxOpenPositions=2); `POSITION_MISMATCH` breaker blocks new entries.
- [ ] Daily loss test: set `MaximumDailyLossPercent` very low on demo; `DAILY_LOSS` breaker
      trips and clears on the next trading day.
- [ ] Algo Trading button off → dashboard `BLOCKED: TRADING_DISABLED`; back on → clears.
- [ ] Research report generated from the demo CSVs and reviewed.

## 3. Phase 18 - Live safeguards (all must hold)
Real orders require **all** of these; any one missing blocks new positions:

1. `TradingMode = LIVE`
2. `EnableTrading = true`
3. `ConfirmLiveTrading = true`
4. The account is a **real** account (LIVE on a demo account is refused, DEMO on a real account is refused)
5. Terminal Algo Trading on, EA allowed to trade, broker allows expert trading
6. No circuit breaker active; session, spread, volatility, margin, and risk checks pass

Hard limits the input dialog cannot exceed: risk ≤ 2 % per trade, daily loss ≤ 10 %,
≤ 3 positions per symbol, ≤ 10 across ApexFlow charts.

Before the first live session:
- [ ] Demo checklist (§2) fully passed on the **same broker** and account type.
- [ ] TestBroker on the live account shows the symbols as `TRADABLE`; otherwise the EA will
      (correctly) show `INSUFFICIENT CAPITAL FOR VALID TRADE` and never trade them.
- [ ] Start with the smallest risk that is still tradable; do not raise risk to "catch up".
- [ ] `StrategyVersion` recorded; any input change later gets a new version and a `ChangeReason`.
- [ ] You accept that every trade can lose and that past results do not predict future ones.

## 4. Things ApexFlow deliberately does not do
- No martingale, grid, averaging down, loss doubling or "recovery" sizing.
- Risk never depends on recent losses or on the distance to the $270 milestone.
- Volume is never rounded up to the broker minimum; untradable means no trade.
- No automatic flip: an opposite signal is ignored while a position is open.
- No trading without a stop-loss; a position whose SL could not be set is closed.

## 5. About the $3 → $270 milestone
The dashboard shows progress for information only. On a standard account $3 will almost
always be untradable at 1 % risk (the broker minimum lot risks far more than $0.03).
On a cent account (balance shown in USC) it may be tradable; TestBroker tells you.
Growing $3 to $270 is a 90× increase; ApexFlow makes no claim that this is achievable.
