# ApexFlow build log

Each phase is written in the cloud session, then compiled by the user in MetaEditor.
A phase is only "done" after a zero-error compile on the user's machine.

| Phase | Status |
|---|---|
| 1 Environment & architecture | Done |
| 2 Project structure & configuration | Written — **awaiting user compile** |
| 3 Core types & utilities | Not started |

---

## Phase 2 — Project structure and configuration

### Files
| File | Purpose |
|---|---|
| `MQL5/Experts/ApexFlow/ApexFlow.mq5` | EA entry point. Loads/validates config, evaluates order permission, 1 s timer, temporary chart status. **No trading logic.** |
| `MQL5/Experts/ApexFlow/Types.mqh` | Constants, hard safety caps, enums used by inputs. |
| `MQL5/Experts/ApexFlow/Config.mqh` | All inputs (grouped), `SApexConfig`, validation, live-trading lock, config change tracking. |
| `MQL5/Scripts/ApexFlowTests/TestConfig.mq5` | 60+ assertions on parsing, validation, magic offsets, change diff, permission lock. |

### Safety behaviour implemented
- **Mode defaults to TEST**; `EnableTrading=false`; `ConfirmLiveTrading=false`.
- `ConfigOrdersPermitted()` — orders only when:
  - Strategy Tester (simulated), or
  - DEMO mode + EnableTrading + demo account, or
  - LIVE mode + EnableTrading + ConfirmLiveTrading + **real** account,
  - and terminal / EA / account / broker all allow algo trading.
  - DEMO mode on a real account is refused; LIVE on a demo account is refused.
- **Hard caps** (not editable from inputs): risk ≤ 2 %/trade, daily loss ≤ 10 %,
  ≤ 3 positions per symbol, ≤ 10 across the account. Inputs above them → EA refuses to load.
- `TargetBalance` is stored for display only.

### Symbol and magic number
- `Symbol` empty → chart symbol. Otherwise `Symbol + SymbolSuffix` (e.g. `XAUUSD` + `m`).
- Effective magic = `MagicNumber` + per-symbol offset:
  XAUUSD 1, EURUSD 2, USDJPY 3, GBPUSD 4, AUDUSD 5, USDCAD 6, USDCHF 7, NZDUSD 8, XAGUSD 9,
  others a stable hash in 100–899. Suffixes are ignored, so `XAUUSDm` and `XAUUSD` share offset 1 —
  use a different base MagicNumber per account if you run the same symbol on two accounts in one terminal.

### Sessions (inputs only in this phase; engine is Phase 5)
Session hours are entered in **each market's local time** (London time for London, New York
time for New York, Tokyo for Asia). The session engine will convert with the correct DST rule,
so 08:00 London stays 08:00 London all year. Overlap is derived from London ∩ New York.
Server clock: AUTO in live (server − GMT); in the Strategy Tester the manual offset + DST rule are used
because `TimeGMT()` equals server time there.

### Config versioning (Section 43)
On each load (outside the tester) the config is compared with the last saved copy in
`MQL5/Files/ApexFlow/config_<symbol>_<magic>.txt`. Every change is logged as
`EVENT=CONFIG_CHANGE CHANGE=key: old -> new REASON=...`. If a strategy (`s.`) parameter changed but
`StrategyVersion` did not, a `STRATEGY_PARAMETERS_CHANGED_WITHOUT_VERSION_BUMP` warning is logged.

### How to verify Phase 2 (on your PC)
1. `git pull`, then compile both files:
   ```
   .\scripts\compile.ps1 -Source "<DataFolder>\MQL5\Experts\ApexFlow\ApexFlow.mq5"
   .\scripts\compile.ps1 -Source "<DataFolder>\MQL5\Scripts\ApexFlowTests\TestConfig.mq5"
   ```
   (or open each in MetaEditor and press F7).
2. Run `TestConfig` on any chart → Experts tab should show `TestConfig: N passed, 0 failed`.
3. Attach `ApexFlow` to a chart with defaults → chart shows `MODE: TEST`, `ORDERS: BLOCKED (TEST mode: analysis only)`.
4. Set RiskPerTradePercent = 5 → EA must refuse to load (`INIT_FAILED`).
5. Paste the compiler output and any failures back into the cloud session.

### Known limitations
- Not compiled yet (no MetaEditor in the cloud session).
- Account-level limits (`MaxAccountOpenPositions`, account daily loss, correlation block) are
  configured here and enforced in Phase 9 (Risk engine).
