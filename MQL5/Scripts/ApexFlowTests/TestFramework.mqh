//+------------------------------------------------------------------+
//| TestFramework.mqh - minimal assertion helpers for ApexFlow tests  |
//| Results are printed to the Experts log.                           |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_TESTFRAMEWORK_MQH
#define APEXFLOW_TESTFRAMEWORK_MQH

int g_testPass = 0;
int g_testFail = 0;

void Check(const bool condition, const string name)
  {
   if(condition)
      g_testPass++;
   else
     {
      g_testFail++;
      PrintFormat("[TEST] FAIL %s", name);
     }
  }

void CheckNear(const double actual, const double expected, const double tol, const string name)
  {
   bool ok = (MathAbs(actual - expected) <= tol);
   if(!ok)
      PrintFormat("[TEST] FAIL %s: expected %.10g got %.10g", name, expected, actual);
   if(ok)
      g_testPass++;
   else
      g_testFail++;
  }

void CheckInt(const long actual, const long expected, const string name)
  {
   if(actual == expected)
      g_testPass++;
   else
     {
      g_testFail++;
      PrintFormat("[TEST] FAIL %s: expected %I64d got %I64d", name, expected, actual);
     }
  }

void TestSummary(const string suite)
  {
   PrintFormat("[TEST] %s: %d passed, %d failed%s", suite, g_testPass, g_testFail,
               (g_testFail == 0 ? "  -> ALL PASSED" : "  -> SEE FAILURES ABOVE"));
  }

//--- UTC time helper for tests: "2026.07.15 07:00".
datetime T(const string s) { return StringToTime(s); }

#endif // APEXFLOW_TESTFRAMEWORK_MQH
