//+------------------------------------------------------------------+
//| Reconciliation.mqh - expected vs actual broker positions          |
//|                                                                   |
//| The broker is the source of truth. Untracked ApexFlow positions   |
//| are adopted, vanished ones are recorded as closed, and a count    |
//| above the configured maximum trips POSITION_MISMATCH (blocks new  |
//| entries so a duplicate can never be added).                       |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_RECONCILIATION_MQH
#define APEXFLOW_RECONCILIATION_MQH

#include "PositionManager.mqh"

//--- Pure set difference used by the reconciler (unit-tested).
void ApexReconcileDiff(const ulong &tracked[], const ulong &actual[], ulong &adopt[], ulong &gone[])
  {
   ArrayResize(adopt, 0);
   ArrayResize(gone, 0);
   for(int i = 0; i < ArraySize(actual); i++)
     {
      bool found = false;
      for(int j = 0; j < ArraySize(tracked); j++)
         if(tracked[j] == actual[i])
           {
            found = true;
            break;
           }
      if(!found)
        {
         int n = ArraySize(adopt);
         ArrayResize(adopt, n + 1);
         adopt[n] = actual[i];
        }
     }
   for(int j = 0; j < ArraySize(tracked); j++)
     {
      bool found = false;
      for(int i = 0; i < ArraySize(actual); i++)
         if(tracked[j] == actual[i])
           {
            found = true;
            break;
           }
      if(!found)
        {
         int n = ArraySize(gone);
         ArrayResize(gone, n + 1);
         gone[n] = tracked[j];
        }
     }
  }

class CReconciler
  {
public:
   //--- Returns the number of closed trades appended to `closed`.
   int               Run(const SApexConfig &c, CPositionManager &pm, CCircuitBreaker &brk,
                         const double atr, const bool startup, SClosedTrade &closed[])
     {
      ulong actual[];
      ArrayResize(actual, 0);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != c.magic || PositionGetString(POSITION_SYMBOL) != c.symbol)
            continue;
         int n = ArraySize(actual);
         ArrayResize(actual, n + 1);
         actual[n] = t;
        }
      ulong tracked[], adopt[], gone[];
      pm.Tickets(tracked);
      ApexReconcileDiff(tracked, actual, adopt, gone);

      for(int i = 0; i < ArraySize(adopt); i++)
         pm.Adopt(adopt[i], atr, startup);

      int added = 0;
      for(int i = 0; i < ArraySize(gone); i++)
        {
         SClosedTrade ct;
         if(pm.HandleClosed(gone[i], ct))
           {
            int n = ArraySize(closed);
            ArrayResize(closed, n + 1);
            closed[n] = ct;
            added++;
           }
        }

      int count = ArraySize(actual);
      if(count > c.maxOpenPositions)
         brk.Trip(APEX_BRK_POSITION_MISMATCH,
                  StringFormat("%d ApexFlow positions open, maximum is %d", count, c.maxOpenPositions), false);
      else
         brk.Set(APEX_BRK_POSITION_MISMATCH, false, "");
      return added;
     }
  };

#endif // APEXFLOW_RECONCILIATION_MQH
