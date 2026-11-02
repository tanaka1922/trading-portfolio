//+------------------------------------------------------------------+
//|                                     ICT_Killzone_Sessions.mq5    |
//|                        Copyright 2026, Seiichi Tanaka / EduVest  |
//|                  https://github.com/tanaka1922/trading-portfolio  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Seiichi Tanaka / EduVest"
#property link      "https://github.com/tanaka1922/trading-portfolio"
#property version   "1.00"
#property description "ICT Killzone Sessions - Highlights key institutional trading windows"
#property description "Asian, London, New York sessions with Killzone overlays."
#property description "Shows session highs/lows and Silver Bullet windows."
#property description "Based on ICT (Inner Circle Trader) concepts."
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

//--- Plot: Session High/Low Lines
#property indicator_label1  "Asian High"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_style1  STYLE_DOT
#property indicator_width1  1

#property indicator_label2  "Asian Low"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGold
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#property indicator_label3  "London KZ High"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_DASH
#property indicator_width3  1

#property indicator_label4  "London KZ Low"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDodgerBlue
#property indicator_style4  STYLE_DASH
#property indicator_width4  1

//--- Input Parameters
input int    Asian_Start_Hour    = 0;    // Asian Session Start (Server Hour)
input int    Asian_End_Hour      = 8;    // Asian Session End
input int    London_KZ_Start     = 7;    // London Killzone Start
input int    London_KZ_End       = 10;   // London Killzone End
input int    NY_KZ_Start         = 12;   // New York Killzone Start
input int    NY_KZ_End           = 15;   // New York Killzone End
input int    SilverBullet_Start  = 14;   // Silver Bullet Start (10AM EST)
input int    SilverBullet_End    = 15;   // Silver Bullet End (11AM EST)
input color  Asian_Color         = clrGold;          // Asian Session Color
input color  London_Color        = clrDodgerBlue;    // London Killzone Color
input color  NY_Color            = clrOrangeRed;     // NY Killzone Color
input color  SilverBullet_Color  = clrLimeGreen;     // Silver Bullet Color
input bool   Show_Asian_Range    = true;   // Show Asian Range
input bool   Show_London_KZ      = true;   // Show London Killzone
input bool   Show_NY_KZ          = true;   // Show NY Killzone
input bool   Show_SilverBullet   = true;   // Show Silver Bullet Window
input bool   Show_Session_Boxes  = true;   // Draw Session Background Boxes
input int    GMT_Offset          = 0;      // GMT Offset of Server Time

//--- Indicator Buffers
double AsianHighBuffer[];
double AsianLowBuffer[];
double LondonHighBuffer[];
double LondonLowBuffer[];

//--- Session tracking
double g_asian_high, g_asian_low;
double g_london_high, g_london_low;
double g_ny_high, g_ny_low;
int    g_last_day;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, AsianHighBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, AsianLowBuffer,  INDICATOR_DATA);
   SetIndexBuffer(2, LondonHighBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, LondonLowBuffer,  INDICATOR_DATA);
   
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   
   IndicatorSetString(INDICATOR_SHORTNAME, "ICT Killzones");
   
   g_asian_high = 0;
   g_asian_low  = 999999;
   g_london_high = 0;
   g_london_low  = 999999;
   g_ny_high = 0;
   g_ny_low  = 999999;
   g_last_day = -1;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "ICT_KZ_");
}

//+------------------------------------------------------------------+
bool IsInSession(int hour, int start, int end)
{
   if(start < end)
      return (hour >= start && hour < end);
   else
      return (hour >= start || hour < end);
}

//+------------------------------------------------------------------+
void DrawSessionBox(string name, datetime time1, datetime time2, 
                    double price1, double price2, color clr)
{
   if(!Show_Session_Boxes) return;
   
   string obj_name = "ICT_KZ_" + name;
   
   if(ObjectFind(0, obj_name) < 0)
      ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
   else
   {
      ObjectSetInteger(0, obj_name, OBJPROP_TIME, 0, time1);
      ObjectSetDouble(0, obj_name, OBJPROP_PRICE, 0, price1);
      ObjectSetInteger(0, obj_name, OBJPROP_TIME, 1, time2);
      ObjectSetDouble(0, obj_name, OBJPROP_PRICE, 1, price2);
   }
   
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, obj_name, OBJPROP_FILL, true);
   ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
   
   //--- Semi-transparent fill
   uchar alpha = 30;
   uchar r, g, b;
   r = (uchar)((clr) & 0xFF);
   g = (uchar)((clr >> 8) & 0xFF);
   b = (uchar)((clr >> 16) & 0xFF);
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 10) return(0);
   
   int start = (prev_calculated > 0) ? prev_calculated - 1 : 0;
   
   for(int i = start; i < rates_total; i++)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      int hour = dt.hour;
      int day  = dt.day;
      
      //--- Reset on new day
      if(day != g_last_day)
      {
         g_asian_high = 0;
         g_asian_low  = 999999;
         g_london_high = 0;
         g_london_low  = 999999;
         g_ny_high = 0;
         g_ny_low  = 999999;
         g_last_day = day;
      }
      
      //--- Asian Session tracking
      if(Show_Asian_Range && IsInSession(hour, Asian_Start_Hour, Asian_End_Hour))
      {
         if(high[i] > g_asian_high) g_asian_high = high[i];
         if(low[i] < g_asian_low)   g_asian_low  = low[i];
      }
      
      //--- London Killzone tracking
      if(Show_London_KZ && IsInSession(hour, London_KZ_Start, London_KZ_End))
      {
         if(high[i] > g_london_high) g_london_high = high[i];
         if(low[i] < g_london_low)   g_london_low  = low[i];
      }
      
      //--- Set buffer values
      AsianHighBuffer[i]  = (g_asian_high > 0) ? g_asian_high : 0.0;
      AsianLowBuffer[i]   = (g_asian_low < 999999) ? g_asian_low : 0.0;
      LondonHighBuffer[i] = (g_london_high > 0) ? g_london_high : 0.0;
      LondonLowBuffer[i]  = (g_london_low < 999999) ? g_london_low : 0.0;
      
      //--- Draw NY Killzone box on last bar
      if(Show_NY_KZ && i == rates_total - 1 && IsInSession(hour, NY_KZ_Start, NY_KZ_End))
      {
         if(high[i] > g_ny_high) g_ny_high = high[i];
         if(low[i] < g_ny_low)   g_ny_low  = low[i];
      }
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+
