//+------------------------------------------------------------------+
//| Dashboard.mqh - lightweight on-chart status panel                 |
//| One OBJ_LABEL per row on a flat background, monospace font.       |
//+------------------------------------------------------------------+
#ifndef APEXFLOW_DASHBOARD_MQH
#define APEXFLOW_DASHBOARD_MQH

#define APEX_DASH_MAX_ROWS 32

class CDashboard
  {
private:
   string            m_prefix;
   int               m_font;
   bool              m_enabled;
   int               m_created;

   void              EnsureRow(const int i, const int x, const int y)
     {
      string name = m_prefix + "row" + IntegerToString(i);
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, m_font);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
        }
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
     }

public:
                     CDashboard(void) : m_prefix("APEXFLOW_"), m_font(9), m_enabled(false), m_created(0) {}

   void              Init(const string prefix, const int fontSize, const bool enabled)
     {
      m_prefix  = prefix;
      m_font    = fontSize;
      m_enabled = enabled;
     }

   bool              Enabled(void) const { return m_enabled; }

   //--- Draw rows. `live` switches the frame to a red warning style.
   void              Render(const string &labels[], const string &values[], const color &colors[],
                            const int count, const bool live)
     {
      if(!m_enabled)
         return;
      int n = (int)MathMin(count, APEX_DASH_MAX_ROWS);
      int lineH = (int)(m_font * 1.8) + 2;
      int x0 = 12, y0 = 24, pad = 8;
      int width = (int)(m_font * 0.78 * 46) + 2 * pad;
      int height = n * lineH + 2 * pad;

      string bg = m_prefix + "bg";
      if(ObjectFind(0, bg) < 0)
        {
         ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, bg, OBJPROP_BACK, false);
        }
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x0 - pad);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y0 - pad);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, live ? C'60,10,10' : C'18,22,30');
      ObjectSetInteger(0, bg, OBJPROP_COLOR, live ? clrRed : C'60,70,90');
      ObjectSetInteger(0, bg, OBJPROP_WIDTH, live ? 3 : 1);

      for(int i = 0; i < n; i++)
        {
         EnsureRow(i, x0, y0 + i * lineH);
         string name = m_prefix + "row" + IntegerToString(i);
         string text = (values[i] == "") ? labels[i] : StringFormat("%-17s %s", labels[i], values[i]);
         ObjectSetString(0, name, OBJPROP_TEXT, text);
         ObjectSetInteger(0, name, OBJPROP_COLOR, colors[i]);
        }
      // Blank rows left over from a longer previous render.
      for(int i = n; i < m_created; i++)
         ObjectSetString(0, m_prefix + "row" + IntegerToString(i), OBJPROP_TEXT, " ");
      m_created = (int)MathMax(m_created, n);
      ChartRedraw(0);
     }

   void              Destroy(void)
     {
      ObjectsDeleteAll(0, m_prefix);
      ChartRedraw(0);
     }
  };

#endif // APEXFLOW_DASHBOARD_MQH
