//+------------------------------------------------------------------+
//| Types.mqh - shared constants, enumerations and data structures    |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_TYPES_MQH
#define APEXFLOW_TYPES_MQH

#define APEX_NAME          "ApexFlow"
#define APEX_CODE_VERSION  "1.0.0"
#define APEX_LOG_TAG       "[APEXFLOW]"

//--- Hard safety caps. Inputs above these are rejected at initialization.
//--- They cannot be changed from the input dialog on purpose.
#define APEX_HARD_MAX_RISK_PCT          2.0
#define APEX_HARD_MAX_DAILY_LOSS_PCT    10.0
#define APEX_HARD_MAX_OPEN_POSITIONS    3
#define APEX_HARD_MAX_ACCOUNT_POSITIONS 10
//--- Minimum-lot mode (small accounts): the broker's minimum trade may be used when it
//--- risks more than RiskPerTradePercent, but never more than this.
#define APEX_HARD_MAX_MINLOT_RISK_PCT   5.0

//--- Magic-number family: every ApexFlow chart uses base + offset (0..999).
#define APEX_MAGIC_FAMILY_SIZE 1000

//--- Timeframe slots used by the indicator manager.
#define APEX_TF_CONTEXT 0
#define APEX_TF_CONFIRM 1
#define APEX_TF_ENTRY   2
#define APEX_TF_COUNT   3

//====================================================================
// INPUT ENUMERATIONS
//====================================================================

//--- Trading mode. TEST is the default; LIVE needs three explicit switches.
enum ENUM_APEX_MODE
  {
   APEX_MODE_TEST = 0, // TEST - analysis only (orders simulated only in Strategy Tester)
   APEX_MODE_DEMO = 1, // DEMO - orders allowed on demo accounts only
   APEX_MODE_LIVE = 2  // LIVE - real money, requires ConfirmLiveTrading
  };

//--- How the broker server clock relates to GMT.
enum ENUM_APEX_SERVER_TZ
  {
   APEX_TZ_AUTO   = 0, // Auto (live: server time - GMT; tester: falls back to manual)
   APEX_TZ_MANUAL = 1  // Manual offset + DST rule below
  };

//--- Daylight-saving rule the broker server clock follows.
enum ENUM_APEX_DST_RULE
  {
   APEX_DST_NONE = 0, // None (server stays on fixed GMT offset)
   APEX_DST_EU   = 1, // European rule (last Sun Mar - last Sun Oct)
   APEX_DST_US   = 2  // US rule (2nd Sun Mar - 1st Sun Nov)
  };

//--- When the consecutive-loss breaker is cleared.
enum ENUM_APEX_LOSS_RESET
  {
   APEX_RESET_NEW_DAY = 0, // New broker trading day
   APEX_RESET_MANUAL  = 1  // Manual only (reload EA with ResetLossStreak=true)
  };

//--- Stop-loss placement method.
enum ENUM_APEX_STOP_MODE
  {
   APEX_STOP_STRUCTURE = 0, // Beyond structural swing (+ ATR buffer)
   APEX_STOP_ATR       = 1, // ATR multiple from entry
   APEX_STOP_HYBRID    = 2  // Structure, widened to ATR minimum if too tight
  };

//--- Take-profit method.
enum ENUM_APEX_TP_MODE
  {
   APEX_TP_FIXED_R   = 0, // Fixed R multiple
   APEX_TP_STRUCTURE = 1, // Next structure / liquidity level
   APEX_TP_ATR       = 2  // ATR multiple
  };

//--- Trailing-stop method.
enum ENUM_APEX_TRAIL_MODE
  {
   APEX_TRAIL_ATR       = 0, // ATR trailing
   APEX_TRAIL_STRUCTURE = 1, // Structure (swing) trailing
   APEX_TRAIL_HYBRID    = 2  // Looser of ATR and structure (less aggressive)
  };

//--- What to do with an open position when the regime turns against it.
enum ENUM_APEX_ADVERSE_ACTION
  {
   APEX_ADVERSE_NONE    = 0, // Nothing - normal management only
   APEX_ADVERSE_TIGHTEN = 1, // Tighten: move to break-even if in profit
   APEX_ADVERSE_CLOSE   = 2  // Close the position
  };

//--- Auction Rejection: where participation data comes from.
enum ENUM_APEX_ORDERFLOW_MODE
  {
   APEX_OF_PROXY  = 0, // PROXY - tick volume + candle/tick behaviour (labelled as proxy)
   APEX_OF_NATIVE = 1  // NATIVE - broker real volume / market book where available, else proxy
  };

//--- Auction Rejection: how directional effort is apportioned inside a bar.
enum ENUM_APEX_EFFORT_SOURCE
  {
   APEX_EFFORT_CANDLE    = 0, // Candle excursion (open->low = selling push, open->high = buying push)
   APEX_EFFORT_TICK_RULE = 1  // Tick rule (bid upticks vs downticks via CopyTicksRange)
  };

//--- Auction Rejection: timeframe of the swing leg used for the retracement zone.
enum ENUM_APEX_LEG_TF
  {
   APEX_LEG_CONFIRMATION = 0, // Confirmation timeframe (default M15)
   APEX_LEG_ENTRY        = 1  // Entry timeframe (default M5)
  };

//--- Auction Rejection: primary target.
enum ENUM_APEX_AR_TARGET
  {
   APEX_AR_TARGET_SWING  = 0, // Swing extreme of the leg (structural target)
   APEX_AR_TARGET_GLOBAL = 1  // Global take-profit settings
  };

//--- Activity profile: how selective entries are. Risk per trade is NOT affected.
enum ENUM_APEX_ACTIVITY
  {
   APEX_ACTIVITY_CUSTOM       = 0, // CUSTOM - use the individual strategy inputs below
   APEX_ACTIVITY_CONSERVATIVE = 1, // CONSERVATIVE - score 70, gap 15, no transition entries
   APEX_ACTIVITY_BALANCED     = 2, // BALANCED - score 65, gap 10, transition pullbacks, Asia for JPY/AUD/NZD
   APEX_ACTIVITY_ACTIVE       = 3, // ACTIVE - score 60, gap 8, + AUCTION_REJECTION (more trades, test first)
   APEX_ACTIVITY_HIGH_WIN_RATE = 4 // HIGH_WIN_RATE - trend-only, 1R target, early break-even (fewer trades)
  };

//--- Which symbol the EA trades.
enum ENUM_APEX_SYMBOL_MODE
  {
   APEX_SYMBOLS_CHART = 0, // CHART - the chart symbol (or the Symbol input)
   APEX_SYMBOLS_AUTO  = 1  // AUTO - scan the broker and pick the best tradable symbol
  };

//--- Which symbols the automatic scan considers.
enum ENUM_APEX_UNIVERSE
  {
   APEX_UNIVERSE_PREFERRED    = 0, // Majors + gold/silver only (what the strategies were built on)
   APEX_UNIVERSE_FOREX_METALS = 1, // All forex pairs and metals
   APEX_UNIVERSE_ALL          = 2  // Everything tradable except synthetic indices (test first!)
  };

//--- Log verbosity.
enum ENUM_APEX_LOG_LEVEL
  {
   APEX_LOG_ERROR = 0, // Errors only
   APEX_LOG_INFO  = 1, // Info (recommended)
   APEX_LOG_DEBUG = 2  // Debug (verbose)
  };

//====================================================================
// ENGINE ENUMERATIONS
//====================================================================
enum ENUM_APEX_SESSION
  {
   APEX_SESSION_OUTSIDE  = 0,
   APEX_SESSION_ASIA     = 1,
   APEX_SESSION_LONDON   = 2,
   APEX_SESSION_NEW_YORK = 3,
   APEX_SESSION_OVERLAP  = 4
  };
#define APEX_SESSION_COUNT 5

enum ENUM_APEX_REGIME
  {
   APEX_REGIME_UNKNOWN    = 0,
   APEX_REGIME_TREND_UP   = 1,
   APEX_REGIME_TREND_DOWN = 2,
   APEX_REGIME_RANGE      = 3,
   APEX_REGIME_HIGH_VOL   = 4,
   APEX_REGIME_LOW_VOL    = 5,
   APEX_REGIME_TRANSITION = 6
  };
#define APEX_REGIME_COUNT 7

enum ENUM_APEX_BIAS
  {
   APEX_BIAS_NONE       = 0,
   APEX_BIAS_BULLISH    = 1,
   APEX_BIAS_BEARISH    = 2,
   APEX_BIAS_RANGE      = 3,
   APEX_BIAS_TRANSITION = 4
  };

//--- Direction as a signed integer: +1 buy, -1 sell, 0 none.
#define APEX_DIR_NONE  0
#define APEX_DIR_BUY   1
#define APEX_DIR_SELL (-1)

enum ENUM_APEX_DECISION
  {
   APEX_DECISION_NO_TRADE = 0,
   APEX_DECISION_BUY      = 1,
   APEX_DECISION_SELL     = 2
  };

enum ENUM_APEX_STRATEGY
  {
   APEX_STRAT_NONE           = 0,
   APEX_STRAT_TREND_PULLBACK = 1,
   APEX_STRAT_BREAKOUT       = 2,
   APEX_STRAT_REVERSAL       = 3,
   APEX_STRAT_AUCTION_REJECTION = 4
  };
#define APEX_STRAT_COUNT 5

enum ENUM_APEX_POS_STATE
  {
   APEX_POS_NEW          = 0,
   APEX_POS_OPEN         = 1,
   APEX_POS_PROTECTING   = 2,
   APEX_POS_PARTIAL_EXIT = 3,
   APEX_POS_TRAILING     = 4,
   APEX_POS_CLOSING      = 5,
   APEX_POS_CLOSED       = 6
  };

enum ENUM_APEX_REJECT
  {
   APEX_REJECT_NONE = 0,
   APEX_REJECT_SCORE_BELOW_THRESHOLD,
   APEX_REJECT_SCORE_GAP,
   APEX_REJECT_NO_SETUP,
   APEX_REJECT_OUTSIDE_SESSION,
   APEX_REJECT_SESSION_ENDING,
   APEX_REJECT_SPREAD_TOO_HIGH,
   APEX_REJECT_VOLATILITY,
   APEX_REJECT_DAILY_LOSS,
   APEX_REJECT_ACCOUNT_DAILY_LOSS,
   APEX_REJECT_CONSECUTIVE_LOSSES,
   APEX_REJECT_MAX_POSITIONS,
   APEX_REJECT_ACCOUNT_MAX_POSITIONS,
   APEX_REJECT_CORRELATION,
   APEX_REJECT_OPPOSITE_POSITION,
   APEX_REJECT_INSUFFICIENT_MARGIN,
   APEX_REJECT_INVALID_STOP,
   APEX_REJECT_STOP_TOO_WIDE,
   APEX_REJECT_INSUFFICIENT_CAPITAL,
   APEX_REJECT_REGIME_TRANSITION,
   APEX_REJECT_REGIME_BLOCKED,
   APEX_REJECT_RISK_LIMIT,
   APEX_REJECT_BROKER_CONSTRAINT,
   APEX_REJECT_CIRCUIT_BREAKER,
   APEX_REJECT_NEWS,
   APEX_REJECT_DATA_NOT_READY,
   APEX_REJECT_ENTRY_IN_FLIGHT,
   APEX_REJECT_ORDER_FAILED,
   APEX_REJECT_LOCATION_INVALID,
   APEX_REJECT_SETUP_INVALIDATED,
   APEX_REJECT_ABSORPTION_WEAK,
   APEX_REJECT_NO_DOMINANCE_SHIFT,
   APEX_REJECT_STRUCTURE_CONTRADICTORY,
   APEX_REJECT_NO_STRUCTURE_CONFIRMATION,
   APEX_REJECT_TARGET_TOO_CLOSE,
   APEX_REJECT_COST_TOO_HIGH,
   APEX_REJECT_DRAWDOWN_STOP
  };

//--- Circuit breakers (indices into the breaker table).
#define APEX_BRK_MARKET_DATA        0
#define APEX_BRK_STALE_DATA         1
#define APEX_BRK_INVALID_PRICE      2
#define APEX_BRK_ABNORMAL_SPREAD    3
#define APEX_BRK_ORDER_FAILURES     4
#define APEX_BRK_POSITION_MISMATCH  5
#define APEX_BRK_DAILY_LOSS         6
#define APEX_BRK_ACCOUNT_DAILY_LOSS 7
#define APEX_BRK_LOSS_STREAK        8
#define APEX_BRK_TRADING_DISABLED   9
#define APEX_BRK_MARGIN             10
#define APEX_BRK_CLOCK              11
#define APEX_BRK_MAX_DRAWDOWN       12
#define APEX_BRK_COUNT              13

//====================================================================
// DATA STRUCTURES
// (Structures are always passed by reference in MQL5.)
//====================================================================
struct SSwingPoint
  {
   double            price;
   datetime          time;
   int               index;   // bar index, 0 = most recent CLOSED bar
  };

struct SStructureState
  {
   bool              valid;
   ENUM_APEX_BIAS    bias;
   double            lastHigh;
   double            prevHigh;
   double            lastLow;
   double            prevLow;
   datetime          lastHighTime;
   datetime          lastLowTime;
   bool              higherHigh;
   bool              higherLow;
   bool              lowerHigh;
   bool              lowerLow;
   bool              bosUp;      // last close broke above the latest swing high
   bool              bosDown;    // last close broke below the latest swing low
   double            rangeHigh;  // highest high of bars 1..N (excludes last closed bar)
   double            rangeLow;
  };

struct SLiquidityState
  {
   double            pdh;             // previous day high
   double            pdl;             // previous day low
   double            sessionHigh;     // current session high (closed bars before the last one)
   double            sessionLow;
   bool              sweptLow;        // last bar traded below a level and closed back above it
   bool              sweptHigh;
   double            sweptLowLevel;
   double            sweptHighLevel;
   bool              nearSupport;     // close within 0.5 ATR above a support level
   bool              nearResistance;  // close within 0.5 ATR below a resistance level
   double            roomUpAtr;       // distance to nearest resistance, in ATR
   double            roomDownAtr;     // distance to nearest support, in ATR
  };

struct SSessionState
  {
   bool              valid;
   ENUM_APEX_SESSION session;
   bool              entriesAllowed;
   bool              endingSoon;       // inside the no-entry buffer before session end
   int               minutesToEnd;
   datetime          serverTime;
   datetime          utcTime;
   int               serverOffsetSec;
   bool              londonDst;
   bool              newYorkDst;
   datetime          sessionStartServer;
  };

struct SRegimeInputs
  {
   double            emaFastCtx;
   double            emaSlowCtx;
   double            emaLongCtx;
   double            slopeNorm;       // slow EMA slope over 5 context bars, in ATR
   double            rsiCtx;
   double            atrPercentile;   // confirmation TF ATR percentile (0..100)
   double            returnAtr;       // 20-bar confirmation TF return, in ATR
   double            rangeWidthAtr;   // 20-bar confirmation TF range width, in ATR
   ENUM_APEX_BIAS    confirmBias;
  };

struct SRegimeState
  {
   ENUM_APEX_REGIME  regime;
   ENUM_APEX_REGIME  raw;             // unfiltered classification of the last update
   int               vote;            // -5 (bearish) .. +5 (bullish)
   int               emaAlign;        // -1, 0, +1
   double            atrPercentile;
   datetime          since;
  };

struct SScoreBreakdown
  {
   double            trend;
   double            structure;
   double            momentum;
   double            liquidity;
   double            volatility;
   double            session;
   double            confirmation;
   double            total;           // 0..100
  };

struct SSetup
  {
   bool              valid;
   int               dir;             // APEX_DIR_BUY / APEX_DIR_SELL
   ENUM_APEX_STRATEGY strategy;
   double            structuralStop;  // stop suggested by the setup (includes ATR buffer)
   double            quality;         // 0..1
   string            note;
   double            score;           // strategy-specific 0..100 score; < 0 = use the base score model
   double            target;          // structural target price; 0 = use the global take-profit
   ENUM_APEX_REJECT  gateReject;      // first failed gate of a multi-stage strategy (NONE if n/a)
  };

//--- Auction Rejection diagnostics for one direction (logged for every candidate).
struct SAuctionDiag
  {
   bool              evaluated;         // a swing leg exists: this is a candidate
   int               dir;
   double            swingHigh;
   double            swingLow;
   double            fibStart;          // zone start level (default 70.5%)
   double            fibMid;            // default 78.8%
   double            fibEnd;            // zone end / invalidation boundary (default 88.6%)
   double            extreme;           // deepest pullback price since the leg extreme
   string            locationStatus;
   double            participation;     // mean opposing effort in the absorption window (see source)
   double            baseline;          // mean opposing effort in the baseline window
   double            effortRatio;       // participation / baseline
   double            displacementATR;   // closing-basis move in the effort direction, in ATR
   double            resultRatio;       // actual / effort-proportional expected move
   double            effortResultRatio; // effortRatio / resultRatio (high = effort without result)
   double            environmentScore;  // 0..1
   double            locationScore;     // 0..1
   double            absorptionScore;   // 0..100
   double            dominanceScore;    // 0..100
   double            structureScore;    // 0..1
   double            sessionScore;      // 0..1
   double            volatilityScore;   // 0..1
   double            total;             // 0..100 weighted AUCTION_REJECTION score
   ENUM_APEX_REJECT  reject;            // first failed gate
   string            source;            // data label, e.g. PROXY:TICK_VOLUME+CANDLE_EXCURSION
  };

struct SSignalResult
  {
   datetime          time;
   ENUM_APEX_DECISION decision;
   int               dir;
   ENUM_APEX_STRATEGY strategy;
   ENUM_APEX_REGIME  regime;
   ENUM_APEX_SESSION session;
   SScoreBreakdown   buy;
   SScoreBreakdown   sell;
   double            structuralStop;
   double            requiredScore;
   ENUM_APEX_REJECT  reject;
   string            detail;
   double            atr;             // entry TF ATR (price units)
   double            spreadPoints;
   double            target;          // structural target from the chosen setup (0 = global TP)
   SAuctionDiag      arBuy;
   SAuctionDiag      arSell;
  };

struct STradePlan
  {
   bool              valid;
   int               dir;
   ENUM_APEX_STRATEGY strategy;
   double            entry;
   double            sl;
   double            tp;
   double            volume;
   double            riskMoney;       // money lost if SL is hit at `volume`
   double            riskPct;         // riskMoney / equity * 100
   double            lossPerLot;
   bool              minLotMode;      // broker minimum used because 1x risk could not afford it
  };

struct SPositionTrack
  {
   ulong             ticket;
   int               dir;
   double            entry;
   double            initialSL;
   double            initialVolume;
   double            riskDist;        // |entry - initialSL| (1R in price)
   double            riskMoney;       // money at risk at open (for R multiple)
   ENUM_APEX_POS_STATE state;
   bool              beDone;
   bool              partialDone;
   bool              trailing;
   bool              adverseHandled;
   datetime          openTime;
   ENUM_APEX_STRATEGY strategy;
   ENUM_APEX_REGIME  regime;
   ENUM_APEX_SESSION session;
   double            buyScore;
   double            sellScore;
   uint              lastModifyMs;
   double            maxR;            // maximum favourable excursion (R)
   double            minR;            // maximum adverse excursion (R, <= 0)
   string            closeReason;     // set when ApexFlow itself closes the position
  };

struct SClosedTrade
  {
   ulong             ticket;
   string            symbol;
   int               dir;
   ENUM_APEX_STRATEGY strategy;
   ENUM_APEX_REGIME  regime;
   ENUM_APEX_SESSION session;
   datetime          openTime;
   datetime          closeTime;
   double            entry;
   double            exitPrice;
   double            initialSL;
   double            volume;
   double            riskMoney;
   double            profit;          // net: profit + swap + commission + fee
   double            rMultiple;
   string            exitReason;
   double            buyScore;
   double            sellScore;
   double            maeR;            // maximum adverse excursion while tracked (R, <= 0)
   double            mfeR;            // maximum favourable excursion while tracked (R, >= 0)
  };

//====================================================================
// STRING CONVERSIONS
//====================================================================
string ApexModeToString(const ENUM_APEX_MODE mode)
  {
   switch(mode)
     {
      case APEX_MODE_TEST: return "TEST";
      case APEX_MODE_DEMO: return "DEMO";
      case APEX_MODE_LIVE: return "LIVE";
     }
   return "UNKNOWN";
  }

string ApexSessionToString(const ENUM_APEX_SESSION s)
  {
   switch(s)
     {
      case APEX_SESSION_OUTSIDE:  return "OUTSIDE_SESSION";
      case APEX_SESSION_ASIA:     return "ASIA";
      case APEX_SESSION_LONDON:   return "LONDON";
      case APEX_SESSION_NEW_YORK: return "NEW_YORK";
      case APEX_SESSION_OVERLAP:  return "LONDON_NEW_YORK_OVERLAP";
     }
   return "UNKNOWN";
  }

string ApexRegimeToString(const ENUM_APEX_REGIME r)
  {
   switch(r)
     {
      case APEX_REGIME_UNKNOWN:    return "UNKNOWN";
      case APEX_REGIME_TREND_UP:   return "TREND_UP";
      case APEX_REGIME_TREND_DOWN: return "TREND_DOWN";
      case APEX_REGIME_RANGE:      return "RANGE";
      case APEX_REGIME_HIGH_VOL:   return "HIGH_VOLATILITY";
      case APEX_REGIME_LOW_VOL:    return "LOW_VOLATILITY";
      case APEX_REGIME_TRANSITION: return "TRANSITION";
     }
   return "UNKNOWN";
  }

string ApexBiasToString(const ENUM_APEX_BIAS b)
  {
   switch(b)
     {
      case APEX_BIAS_NONE:       return "NONE";
      case APEX_BIAS_BULLISH:    return "BULLISH";
      case APEX_BIAS_BEARISH:    return "BEARISH";
      case APEX_BIAS_RANGE:      return "RANGING";
      case APEX_BIAS_TRANSITION: return "TRANSITIONING";
     }
   return "UNKNOWN";
  }

string ApexDecisionToString(const ENUM_APEX_DECISION d)
  {
   switch(d)
     {
      case APEX_DECISION_NO_TRADE: return "NO_TRADE";
      case APEX_DECISION_BUY:      return "BUY";
      case APEX_DECISION_SELL:     return "SELL";
     }
   return "UNKNOWN";
  }

string ApexDirToString(const int dir)
  {
   if(dir == APEX_DIR_BUY)
      return "BUY";
   if(dir == APEX_DIR_SELL)
      return "SELL";
   return "NONE";
  }

string ApexStrategyToString(const ENUM_APEX_STRATEGY s)
  {
   switch(s)
     {
      case APEX_STRAT_NONE:           return "NONE";
      case APEX_STRAT_TREND_PULLBACK: return "TREND_PULLBACK";
      case APEX_STRAT_BREAKOUT:       return "BREAKOUT";
      case APEX_STRAT_REVERSAL:       return "REVERSAL";
      case APEX_STRAT_AUCTION_REJECTION: return "AUCTION_REJECTION";
     }
   return "UNKNOWN";
  }

string ApexPosStateToString(const ENUM_APEX_POS_STATE s)
  {
   switch(s)
     {
      case APEX_POS_NEW:          return "NEW";
      case APEX_POS_OPEN:         return "OPEN";
      case APEX_POS_PROTECTING:   return "PROTECTING";
      case APEX_POS_PARTIAL_EXIT: return "PARTIAL_EXIT";
      case APEX_POS_TRAILING:     return "TRAILING";
      case APEX_POS_CLOSING:      return "CLOSING";
      case APEX_POS_CLOSED:       return "CLOSED";
     }
   return "UNKNOWN";
  }

string ApexRejectToString(const ENUM_APEX_REJECT r)
  {
   switch(r)
     {
      case APEX_REJECT_NONE:                  return "none";
      case APEX_REJECT_SCORE_BELOW_THRESHOLD: return "score_below_threshold";
      case APEX_REJECT_SCORE_GAP:             return "scores_too_close";
      case APEX_REJECT_NO_SETUP:              return "no_valid_setup";
      case APEX_REJECT_OUTSIDE_SESSION:       return "outside_session";
      case APEX_REJECT_SESSION_ENDING:        return "session_ending";
      case APEX_REJECT_SPREAD_TOO_HIGH:       return "spread_too_high";
      case APEX_REJECT_VOLATILITY:            return "volatility_unsuitable";
      case APEX_REJECT_DAILY_LOSS:            return "daily_loss_limit";
      case APEX_REJECT_ACCOUNT_DAILY_LOSS:    return "account_daily_loss_limit";
      case APEX_REJECT_CONSECUTIVE_LOSSES:    return "consecutive_loss_limit";
      case APEX_REJECT_MAX_POSITIONS:         return "max_open_positions";
      case APEX_REJECT_ACCOUNT_MAX_POSITIONS: return "account_max_open_positions";
      case APEX_REJECT_CORRELATION:           return "correlated_exposure";
      case APEX_REJECT_OPPOSITE_POSITION:     return "opposite_position_open";
      case APEX_REJECT_INSUFFICIENT_MARGIN:   return "insufficient_margin";
      case APEX_REJECT_INVALID_STOP:          return "invalid_stop";
      case APEX_REJECT_STOP_TOO_WIDE:         return "stop_too_wide";
      case APEX_REJECT_INSUFFICIENT_CAPITAL:  return "insufficient_capital";
      case APEX_REJECT_REGIME_TRANSITION:     return "regime_transition";
      case APEX_REJECT_REGIME_BLOCKED:        return "regime_blocks_strategy";
      case APEX_REJECT_RISK_LIMIT:            return "risk_limit";
      case APEX_REJECT_BROKER_CONSTRAINT:     return "broker_constraint";
      case APEX_REJECT_CIRCUIT_BREAKER:       return "circuit_breaker";
      case APEX_REJECT_NEWS:                  return "news_block";
      case APEX_REJECT_DATA_NOT_READY:        return "data_not_ready";
      case APEX_REJECT_ENTRY_IN_FLIGHT:       return "entry_in_flight";
      case APEX_REJECT_ORDER_FAILED:          return "order_failed";
      case APEX_REJECT_LOCATION_INVALID:      return "location_invalid";
      case APEX_REJECT_SETUP_INVALIDATED:     return "setup_invalidated";
      case APEX_REJECT_ABSORPTION_WEAK:       return "absorption_weak";
      case APEX_REJECT_NO_DOMINANCE_SHIFT:    return "dominance_shift_absent";
      case APEX_REJECT_STRUCTURE_CONTRADICTORY: return "structure_contradictory";
      case APEX_REJECT_NO_STRUCTURE_CONFIRMATION: return "no_structure_confirmation";
      case APEX_REJECT_TARGET_TOO_CLOSE:      return "target_too_close";
      case APEX_REJECT_COST_TOO_HIGH:         return "cost_too_high";
      case APEX_REJECT_DRAWDOWN_STOP:         return "drawdown_stop";
     }
   return "unknown";
  }

string ApexBreakerToString(const int b)
  {
   switch(b)
     {
      case APEX_BRK_MARKET_DATA:        return "MARKET_DATA";
      case APEX_BRK_STALE_DATA:         return "STALE_DATA";
      case APEX_BRK_INVALID_PRICE:      return "INVALID_PRICE";
      case APEX_BRK_ABNORMAL_SPREAD:    return "ABNORMAL_SPREAD";
      case APEX_BRK_ORDER_FAILURES:     return "ORDER_FAILURES";
      case APEX_BRK_POSITION_MISMATCH:  return "POSITION_MISMATCH";
      case APEX_BRK_DAILY_LOSS:         return "DAILY_LOSS";
      case APEX_BRK_ACCOUNT_DAILY_LOSS: return "ACCOUNT_DAILY_LOSS";
      case APEX_BRK_LOSS_STREAK:        return "LOSS_STREAK";
      case APEX_BRK_TRADING_DISABLED:   return "TRADING_DISABLED";
      case APEX_BRK_MARGIN:             return "MARGIN";
      case APEX_BRK_CLOCK:              return "CLOCK";
      case APEX_BRK_MAX_DRAWDOWN:       return "MAX_DRAWDOWN";
     }
   return "UNKNOWN";
  }

#endif // APEXFLOW_TYPES_MQH
