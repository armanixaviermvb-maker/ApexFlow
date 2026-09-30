//+------------------------------------------------------------------+
//| AuctionRejection.mqh - ApexFlow Auction Rejection Strategy        |
//| Identifier: AUCTION_REJECTION                                     |
//|                                                                   |
//| RESEARCH HYPOTHESIS - not a proven edge. Disabled by default.     |
//|                                                                   |
//| Pipeline (each stage is a gate with its own NO_TRADE reason):     |
//|   ENVIRONMENT      regime alignment (checked by the signal engine)|
//|   LOCATION         deep pullback into the 70.5-88.6% zone of a    |
//|                    confirmed swing leg (location filter only)     |
//|   INVALIDATION     decisive close beyond 88.6% -> setup dead      |
//|   PARTICIPATION    opposing effort elevated vs baseline (proxy)   |
//|   ABSORPTION       effort without proportional result + rejection |
//|   DOMINANCE SHIFT  response bar shows control changing sides      |
//|   STRUCTURE        micro structure confirms, HTF not contradictory|
//|   SIGNAL SCORE     weighted 0-100, own threshold                  |
//|   RISK VALIDATION  RiskEngine (unchanged)                         |
//|                                                                   |
//| No future data: swings are confirmed only after `strength` closed |
//| bars; every other read uses closed bars (index >= 0 = closed).    |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_AUCTIONREJECTION_MQH
#define APEXFLOW_AUCTIONREJECTION_MQH

#include "../Config.mqh"
#include "../Utils.mqh"
#include "../Indicators/IndicatorManager.mqh"
#include "../Core/StructureEngine.mqh"
#include "../Core/OrderFlow.mqh"
#include "../Core/EffortVsResult.mqh"

struct SAuctionLocation
  {
   bool              legFound;
   bool              valid;
   bool              invalidated;
   double            swingHigh;
   double            swingLow;
   double            levelStart;   // zone start (default 70.5%)
   double            levelMid;     // default 78.8%
   double            levelEnd;     // zone end / invalidation boundary (default 88.6%)
   double            extreme;      // deepest pullback since the leg extreme
   double            depthPct;     // retracement of the extreme, % of the leg
   double            score;        // 0..1
   string            status;
  };

//--- Environment component (0..1) for AUCTION_REJECTION.
double ApexAREnvironmentScore(const int dir, const ENUM_APEX_REGIME regime, const int vote, const bool allowRange)
  {
   bool aligned = ((dir == APEX_DIR_BUY && vote > 0) || (dir == APEX_DIR_SELL && vote < 0));
   switch(regime)
     {
      case APEX_REGIME_TREND_UP:   return (dir == APEX_DIR_BUY) ? 1.0 : 0.0;
      case APEX_REGIME_TREND_DOWN: return (dir == APEX_DIR_SELL) ? 1.0 : 0.0;
      case APEX_REGIME_RANGE:      return allowRange ? (aligned ? 0.7 : 0.5) : 0.0;
      case APEX_REGIME_LOW_VOL:    return allowRange ? 0.5 : 0.0;
      case APEX_REGIME_HIGH_VOL:   return aligned ? 0.6 : 0.0;
      case APEX_REGIME_TRANSITION: return 0.2;
      default:                     break;
     }
   return 0.0;
  }

//--- Location / invalidation analysis (pure; unit-tested).
//--- legRates: series of closed bars on the leg timeframe; entryRates: closed entry bars.
//--- BUY: leg = swing low -> highest unexceeded swing high; zone measured down from the high.
//--- SELL: leg = swing high -> lowest unexceeded swing low; zone measured up from the low.
void ApexAuctionLocation(const int dir, const MqlRates &legRates[], const int legCount, const int strength,
                         const int legPeriodSec, const MqlRates &entryRates[], const int entryCount,
                         const double legAtr, const double entryAtr, const double zoneStart, const double zoneMid,
                         const double zoneEnd, const double decisiveATR, const double minLegATR,
                         SAuctionLocation &L)
  {
   ZeroMemory(L);
   L.status = "no_leg";
   bool buy = (dir == APEX_DIR_BUY);
   int n = (int)MathMin(legCount, ArraySize(legRates));
   int ne = (int)MathMin(entryCount, ArraySize(entryRates));
   if(n < 2 * strength + 3 || ne < 1)
      return;

   SSwingPoint ext[], org[];
   int nx = ApexFindSwings(legRates, n, strength, buy, ext, 6);    // leg extremes (highs for BUY)
   int no = ApexFindSwings(legRates, n, strength, !buy, org, 12);  // leg origins (lows for BUY)
   if(nx < 1 || no < 1)
      return;

   // Leg extreme: the most extreme swing that no later bar has exceeded.
   int best = -1;
   for(int k = 0; k < nx; k++)
     {
      bool exceeded = false;
      for(int i = 0; i < ext[k].index && !exceeded; i++)
         exceeded = buy ? (legRates[i].high > ext[k].price) : (legRates[i].low < ext[k].price);
      if(exceeded)
         continue;
      if(best < 0 || (buy ? ext[k].price > ext[best].price : ext[k].price < ext[best].price))
         best = k;
     }
   if(best < 0)
     {
      L.status = "leg_extended";
      return;
     }
   // Leg origin: the first opposite swing that is OLDER than the extreme.
   int o = -1;
   for(int k = 0; k < no; k++)
      if(org[k].index > ext[best].index)
        {
         o = k;
         break;
        }
   if(o < 0)
      return;

   L.legFound  = true;
   L.swingHigh = buy ? ext[best].price : org[o].price;
   L.swingLow  = buy ? org[o].price : ext[best].price;
   double range = L.swingHigh - L.swingLow;
   if(range <= 0)
     {
      L.status = "no_leg";
      L.legFound = false;
      return;
     }
   if(buy)
     {
      L.levelStart = L.swingHigh - zoneStart / 100.0 * range;
      L.levelMid   = L.swingHigh - zoneMid / 100.0 * range;
      L.levelEnd   = L.swingHigh - zoneEnd / 100.0 * range;
     }
   else
     {
      L.levelStart = L.swingLow + zoneStart / 100.0 * range;
      L.levelMid   = L.swingLow + zoneMid / 100.0 * range;
      L.levelEnd   = L.swingLow + zoneEnd / 100.0 * range;
     }
   if(legAtr > 0 && range < minLegATR * legAtr)
     {
      L.status = "leg_too_small";
      return;
     }

   // Pullback since the leg extreme: leg-TF bars after it + entry bars after its bar closed.
   double legExtreme = ext[best].price;
   datetime after = ext[best].time + legPeriodSec;
   double boundary = buy ? L.levelEnd - decisiveATR * entryAtr : L.levelEnd + decisiveATR * entryAtr;
   bool haveExtreme = false, extended = false, decisive = false;
   for(int i = 0; i < ext[best].index; i++)
     {
      double p = buy ? legRates[i].low : legRates[i].high;
      if(!haveExtreme || (buy ? p < L.extreme : p > L.extreme))
         L.extreme = p;
      haveExtreme = true;
      if(buy ? legRates[i].close < boundary : legRates[i].close > boundary)
         decisive = true;
     }
   for(int i = 0; i < ne; i++)
     {
      if(entryRates[i].time < after)
         break;
      if(buy ? entryRates[i].high > legExtreme : entryRates[i].low < legExtreme)
         extended = true;
      double p = buy ? entryRates[i].low : entryRates[i].high;
      if(!haveExtreme || (buy ? p < L.extreme : p > L.extreme))
         L.extreme = p;
      haveExtreme = true;
      if(buy ? entryRates[i].close < boundary : entryRates[i].close > boundary)
         decisive = true;
     }
   if(extended)
     {
      L.status = "leg_extended";
      return;
     }
   if(!haveExtreme)
     {
      L.status = "no_pullback_yet";
      return;
     }
   L.depthPct = buy ? (L.swingHigh - L.extreme) / range * 100.0 : (L.extreme - L.swingLow) / range * 100.0;
   if(decisive)
     {
      L.invalidated = true;
      L.status = "invalidated_beyond_zone_end";
      return;
     }
   if(L.depthPct < zoneStart)
     {
      L.status = "not_in_zone";
      return;
     }
   double close0 = entryRates[0].close;
   double half = buy ? L.swingHigh - 0.5 * range : L.swingLow + 0.5 * range;
   if(buy ? close0 >= half : close0 <= half)
     {
      L.status = buy ? "left_discount" : "left_premium";
      return;
     }
   if(L.depthPct <= zoneEnd)
     {
      double halfWidth = MathMax(zoneMid - zoneStart, zoneEnd - zoneMid);
      L.score = ApexClamp(1.0 - 0.3 * MathAbs(L.depthPct - zoneMid) / halfWidth, 0.7, 1.0);
     }
   else
      L.score = 0.6; // wick beyond the boundary without a decisive close
   L.valid  = true;
   L.status = buy ? "valid_discount" : "valid_premium";
  }

//--- Weighted AUCTION_REJECTION score from the components gathered so far.
double ApexARTotal(const SAuctionDiag &d, const SApexConfig &c)
  {
   return d.environmentScore * c.arWEnv + d.locationScore * c.arWLoc +
          d.absorptionScore / 100.0 * c.arWAbs + d.dominanceScore / 100.0 * c.arWDom +
          d.structureScore * c.arWStruct + d.sessionScore * c.arWSession + d.volatilityScore * c.arWVol;
  }

class CAuctionRejection
  {
private:
   bool              Gate(SSetup &out, SAuctionDiag &diag, const SApexConfig &c,
                          const ENUM_APEX_REJECT reason, const string note) const
     {
      diag.reject    = reason;
      diag.total     = ApexARTotal(diag, c);
      out.valid      = false;
      out.gateReject = reason;
      out.score      = diag.total;
      out.note       = note;
      return false;
     }

public:
   ENUM_APEX_STRATEGY Id(void) const { return APEX_STRAT_AUCTION_REJECTION; }

   bool              Evaluate(const int dir, CIndicatorManager &ind, COrderFlow &of,
                              const SStructureState &confirmSt, const SStructureState &entrySt,
                              const SRegimeState &reg, const SSessionState &ss, const SApexConfig &c,
                              SSetup &out, SAuctionDiag &diag)
     {
      out.valid          = false;
      out.dir            = dir;
      out.strategy       = Id();
      out.structuralStop = 0.0;
      out.quality        = 0.0;
      out.note           = "";
      out.score          = 0.0;
      out.target         = 0.0;
      out.gateReject     = APEX_REJECT_NONE;
      ZeroMemory(diag);
      diag.dir    = dir;
      diag.reject = APEX_REJECT_NONE;
      bool buy = (dir == APEX_DIR_BUY);

      if(!ind.Ready())
         return Gate(out, diag, c, APEX_REJECT_DATA_NOT_READY, "data not ready");
      int legSlot = (c.arLegTf == APEX_LEG_CONFIRMATION) ? APEX_TF_CONFIRM : APEX_TF_ENTRY;
      double entryAtr = ind.Atr(APEX_TF_ENTRY);
      double legAtr   = ind.Atr(legSlot);
      int depth = ind.Depth();

      //--- ENVIRONMENT / SESSION / VOLATILITY components
      diag.environmentScore = ApexAREnvironmentScore(dir, reg.regime, reg.vote, c.arAllowRange);
      diag.sessionScore     = ApexSessionScore(ss.session);
      diag.volatilityScore  = ApexVolatilityScore(ind.AtrPercentile(APEX_TF_ENTRY, c.atrPctLookback), c.atrPctMin, c.atrPctMax);

      //--- LOCATION + INVALIDATION
      SAuctionLocation L;
      ApexAuctionLocation(dir, ind.data[legSlot].rates, depth, c.swingStrength, PeriodSeconds(ind.data[legSlot].tf),
                          ind.data[APEX_TF_ENTRY].rates, depth, legAtr, entryAtr,
                          c.arZoneStart, c.arZoneMid, c.arZoneEnd, c.arDecisiveATR, c.arMinLegATR, L);
      diag.swingHigh      = L.swingHigh;
      diag.swingLow       = L.swingLow;
      diag.fibStart       = L.levelStart;
      diag.fibMid         = L.levelMid;
      diag.fibEnd         = L.levelEnd;
      diag.extreme        = L.extreme;
      diag.locationStatus = L.status;
      if(!L.legFound)
         return Gate(out, diag, c, APEX_REJECT_LOCATION_INVALID, "location: " + L.status);
      diag.evaluated = true;
      if(L.invalidated)
         return Gate(out, diag, c, APEX_REJECT_SETUP_INVALIDATED, "setup invalidated: decisive close beyond zone end");
      if(!L.valid)
         return Gate(out, diag, c, APEX_REJECT_LOCATION_INVALID, "location: " + L.status);
      diag.locationScore = L.score;

      // The absorption window itself must trade inside the zone.
      int need = c.arWindow + c.arBaseline + 2;
      bool inZone = false;
      for(int i = 1; i <= c.arWindow && i < depth; i++)
         if(buy ? ind.data[APEX_TF_ENTRY].rates[i].low <= L.levelStart : ind.data[APEX_TF_ENTRY].rates[i].high >= L.levelStart)
            inZone = true;
      if(!inZone)
         return Gate(out, diag, c, APEX_REJECT_LOCATION_INVALID, "absorption window outside the zone");

      //--- PARTICIPATION + ABSORPTION (effort vs result)
      double buyE[], sellE[], totE[];
      diag.source = of.BarEfforts(ind.data[APEX_TF_ENTRY].rates, need, buyE, sellE, totE);
      SEffortResult er;
      ApexEffortVsResult(dir, ind.data[APEX_TF_ENTRY].rates, buyE, sellE, c.arWindow, c.arBaseline, entryAtr, c.arEffortMin, er);
      diag.participation     = er.participation;
      diag.baseline          = er.baseline;
      diag.effortRatio       = er.effortRatio;
      diag.displacementATR   = er.displacementATR;
      diag.resultRatio       = er.resultRatio;
      diag.effortResultRatio = er.effortResultRatio;
      diag.absorptionScore   = er.absorptionScore;

      //--- DOMINANCE SHIFT
      double imbalance = 0;
      bool book = of.BookImbalance(imbalance);
      if(book)
         diag.source += "+NATIVE:BROKER_BOOK(not centralized)";
      SDominance dom;
      ApexDominanceShift(dir, ind.data[APEX_TF_ENTRY].rates, buyE, sellE, c.arWindow, entryAtr, book, imbalance, dom);
      diag.dominanceScore = dom.score;

      //--- STRUCTURE
      bool contradictory = false;
      diag.structureScore = ApexARStructureScore(dir, dom, entrySt, confirmSt, contradictory);
      diag.total = ApexARTotal(diag, c);

      if(!er.ok)
         return Gate(out, diag, c, APEX_REJECT_DATA_NOT_READY, "not enough bars for effort baseline");
      if(er.absorptionScore < c.arMinAbsorption)
         return Gate(out, diag, c, APEX_REJECT_ABSORPTION_WEAK,
                     StringFormat("absorption %.0f < %d (effort x%.2f, result %.2f)", er.absorptionScore,
                                  c.arMinAbsorption, er.effortRatio, er.resultRatio));
      if(dom.score < c.arMinDominance)
         return Gate(out, diag, c, APEX_REJECT_NO_DOMINANCE_SHIFT,
                     StringFormat("dominance shift %.0f < %d", dom.score, c.arMinDominance));
      if(contradictory)
         return Gate(out, diag, c, APEX_REJECT_STRUCTURE_CONTRADICTORY, "confirmation timeframe structure opposes the trade");
      if(diag.structureScore < 0.5)
         return Gate(out, diag, c, APEX_REJECT_NO_STRUCTURE_CONFIRMATION,
                     StringFormat("structure %.2f < 0.50", diag.structureScore));

      //--- STOP beyond the invalidation point; TARGET = the leg's swing extreme.
      if(buy)
         out.structuralStop = MathMin(L.extreme, L.levelEnd) - c.stopATRBuffer * entryAtr;
      else
         out.structuralStop = MathMax(L.extreme, L.levelEnd) + c.stopATRBuffer * entryAtr;
      if(c.arTargetMode == APEX_AR_TARGET_SWING)
         out.target = buy ? L.swingHigh : L.swingLow;

      out.valid   = true;
      out.score   = diag.total;
      out.quality = dom.score / 100.0;
      out.note    = StringFormat("absorption %.0f, dominance %.0f, depth %.1f%%", er.absorptionScore, dom.score, L.depthPct);
      return true;
     }
  };

#endif // APEXFLOW_AUCTIONREJECTION_MQH
