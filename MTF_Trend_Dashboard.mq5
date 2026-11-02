//+------------------------------------------------------------------+
//|                                      MTF_Trend_Dashboard.mq5     |
//|                        Copyright 2026, Seiichi Tanaka / EduVest  |
//|                  https://github.com/tanaka1922/trading-portfolio  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Seiichi Tanaka / EduVest"
#property link      "https://github.com/tanaka1922/trading-portfolio"
#property version   "1.00"
#property description "Multi-Timeframe Trend Dashboard"
#property description "Displays trend direction across M5, M15, H1, H4, D1 timeframes."
#property description "Uses EMA crossover + RSI + ADX for trend confirmation."
#property description "On-chart panel with color-coded trend status per timeframe."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input Parameters
input int    EMA_Fast        = 9;      // Fast EMA Period
input int    EMA_Slow        = 21;     // Slow EMA Period
input int    RSI_Period      = 14;     // RSI Period
input int    ADX_Period      = 14;     // ADX Period
input double ADX_Threshold   = 20.0;   // ADX Trend Threshold
input int    Panel_X         = 20;     // Panel X Position
input int    Panel_Y         = 30;     // Panel Y Position
input int    Font_Size       = 10;     // Font Size
input color  Panel_BG        = clrBlack;       // Panel Background
input color  Bullish_Color   = clrLimeGreen;   // Bullish Color
input color  Bearish_Color   = clrOrangeRed;   // Bearish Color
input color  Neutral_Color   = clrGray;        // Neutral Color
input color  Header_Color    = clrWhite;       // Header Color
input bool   Show_M5         = true;    // Show M5
input bool   Show_M15        = true;    // Show M15
input bool   Show_H1         = true;    // Show H1
input bool   Show_H4         = true;    // Show H4
input bool   Show_D1         = true;    // Show D1

//--- Timeframe array
ENUM_TIMEFRAMES TF_Array[];
string TF_Names[];
int TF_Count;

//--- Handles per timeframe
int ema_fast_handles[];
int ema_slow_handles[];
int rsi_handles[];
int adx_handles[];

//+------------------------------------------------------------------+
int OnInit()
{
   //--- Build timeframe arrays
   TF_Count = 0;
   if(Show_M5)  TF_Count++;
   if(Show_M15) TF_Count++;
   if(Show_H1)  TF_Count++;
   if(Show_H4)  TF_Count++;
   if(Show_D1)  TF_Count++;
   
   ArrayResize(TF_Array, TF_Count);
   ArrayResize(TF_Names, TF_Count);
   ArrayResize(ema_fast_handles, TF_Count);
   ArrayResize(ema_slow_handles, TF_Count);
   ArrayResize(rsi_handles, TF_Count);
   ArrayResize(adx_handles, TF_Count);
   
   int idx = 0;
   if(Show_M5)  { TF_Array[idx] = PERIOD_M5;  TF_Names[idx] = "M5";  idx++; }
   if(Show_M15) { TF_Array[idx] = PERIOD_M15; TF_Names[idx] = "M15"; idx++; }
   if(Show_H1)  { TF_Array[idx] = PERIOD_H1;  TF_Names[idx] = "H1";  idx++; }
   if(Show_H4)  { TF_Array[idx] = PERIOD_H4;  TF_Names[idx] = "H4";  idx++; }
   if(Show_D1)  { TF_Array[idx] = PERIOD_D1;  TF_Names[idx] = "D1";  idx++; }
   
   //--- Create indicator handles for each timeframe
   for(int i = 0; i < TF_Count; i++)
   {
      ema_fast_handles[i] = iMA(_Symbol, TF_Array[i], EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      ema_slow_handles[i] = iMA(_Symbol, TF_Array[i], EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
      rsi_handles[i]      = iRSI(_Symbol, TF_Array[i], RSI_Period, PRICE_CLOSE);
      adx_handles[i]      = iADX(_Symbol, TF_Array[i], ADX_Period);
      
      if(ema_fast_handles[i] == INVALID_HANDLE || ema_slow_handles[i] == INVALID_HANDLE ||
         rsi_handles[i] == INVALID_HANDLE || adx_handles[i] == INVALID_HANDLE)
      {
         Print("Error creating handles for ", TF_Names[i]);
         return(INIT_FAILED);
      }
   }
   
   //--- Create background panel
   CreatePanel();
   
   IndicatorSetString(INDICATOR_SHORTNAME, "MTF Dashboard");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < TF_Count; i++)
   {
      if(ema_fast_handles[i] != INVALID_HANDLE) IndicatorRelease(ema_fast_handles[i]);
      if(ema_slow_handles[i] != INVALID_HANDLE) IndicatorRelease(ema_slow_handles[i]);
      if(rsi_handles[i] != INVALID_HANDLE)      IndicatorRelease(rsi_handles[i]);
      if(adx_handles[i] != INVALID_HANDLE)      IndicatorRelease(adx_handles[i]);
   }
   
   ObjectsDeleteAll(0, "MTF_");
}

//+------------------------------------------------------------------+
void CreatePanel()
{
   //--- Background rectangle
   string bg_name = "MTF_BG";
   int panel_width  = 280;
   int panel_height = 30 + TF_Count * 25 + 10;
   
   ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, Panel_X - 5);
   ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, Panel_Y - 5);
   ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, panel_width);
   ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, panel_height);
   ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, Panel_BG);
   ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrDarkSlateGray);
   ObjectSetInteger(0, bg_name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, bg_name, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg_name, OBJPROP_SELECTABLE, false);
   
   //--- Header
   CreateLabel("MTF_Header", "MTF TREND DASHBOARD", Panel_X, Panel_Y, Header_Color, Font_Size + 1, true);
   
   //--- Column headers
   int y_offset = Panel_Y + 22;
   CreateLabel("MTF_Col_TF",    "TF",     Panel_X,       y_offset, clrDarkGray, Font_Size - 1, false);
   CreateLabel("MTF_Col_EMA",   "EMA",    Panel_X + 45,  y_offset, clrDarkGray, Font_Size - 1, false);
   CreateLabel("MTF_Col_RSI",   "RSI",    Panel_X + 100, y_offset, clrDarkGray, Font_Size - 1, false);
   CreateLabel("MTF_Col_ADX",   "ADX",    Panel_X + 155, y_offset, clrDarkGray, Font_Size - 1, false);
   CreateLabel("MTF_Col_TREND", "TREND",  Panel_X + 210, y_offset, clrDarkGray, Font_Size - 1, false);
}

//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int size, bool bold)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
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
   if(rates_total < 2) return(0);
   
   for(int i = 0; i < TF_Count; i++)
   {
      double ema_fast_val[1], ema_slow_val[1], rsi_val[1], adx_val[1], plus_di[1], minus_di[1];
      
      //--- Get latest values
      if(CopyBuffer(ema_fast_handles[i], 0, 0, 1, ema_fast_val) <= 0) continue;
      if(CopyBuffer(ema_slow_handles[i], 0, 0, 1, ema_slow_val) <= 0) continue;
      if(CopyBuffer(rsi_handles[i], 0, 0, 1, rsi_val) <= 0) continue;
      if(CopyBuffer(adx_handles[i], 0, 0, 1, adx_val) <= 0) continue;
      if(CopyBuffer(adx_handles[i], 1, 0, 1, plus_di) <= 0) continue;
      if(CopyBuffer(adx_handles[i], 2, 0, 1, minus_di) <= 0) continue;
      
      //--- Analyze trend
      bool ema_bull   = ema_fast_val[0] > ema_slow_val[0];
      bool rsi_bull   = rsi_val[0] > 50.0;
      bool adx_strong = adx_val[0] > ADX_Threshold;
      bool di_bull    = plus_di[0] > minus_di[0];
      
      //--- Determine overall trend
      string ema_txt, rsi_txt, adx_txt, trend_txt;
      color  ema_clr, rsi_clr, adx_clr, trend_clr;
      
      // EMA status
      if(ema_bull) { ema_txt = "BULL"; ema_clr = Bullish_Color; }
      else         { ema_txt = "BEAR"; ema_clr = Bearish_Color; }
      
      // RSI status
      if(rsi_val[0] > 60)      { rsi_txt = StringFormat("%.0f", rsi_val[0]); rsi_clr = Bullish_Color; }
      else if(rsi_val[0] < 40) { rsi_txt = StringFormat("%.0f", rsi_val[0]); rsi_clr = Bearish_Color; }
      else                     { rsi_txt = StringFormat("%.0f", rsi_val[0]); rsi_clr = Neutral_Color; }
      
      // ADX status
      if(adx_strong && di_bull)  { adx_txt = StringFormat("%.0f↑", adx_val[0]); adx_clr = Bullish_Color; }
      else if(adx_strong)        { adx_txt = StringFormat("%.0f↓", adx_val[0]); adx_clr = Bearish_Color; }
      else                       { adx_txt = StringFormat("%.0f", adx_val[0]);   adx_clr = Neutral_Color; }
      
      // Overall trend
      int bull_score = 0;
      if(ema_bull) bull_score++;
      if(rsi_bull) bull_score++;
      if(di_bull)  bull_score++;
      
      if(bull_score >= 2 && adx_strong)      { trend_txt = "▲ BULL"; trend_clr = Bullish_Color; }
      else if(bull_score <= 1 && adx_strong)  { trend_txt = "▼ BEAR"; trend_clr = Bearish_Color; }
      else                                    { trend_txt = "— FLAT"; trend_clr = Neutral_Color; }
      
      //--- Update dashboard labels
      int y_pos = Panel_Y + 40 + i * 25;
      
      CreateLabel("MTF_TF_"    + IntegerToString(i), TF_Names[i], Panel_X,       y_pos, Header_Color,  Font_Size, true);
      CreateLabel("MTF_EMA_"   + IntegerToString(i), ema_txt,     Panel_X + 45,  y_pos, ema_clr,       Font_Size, false);
      CreateLabel("MTF_RSI_"   + IntegerToString(i), rsi_txt,     Panel_X + 100, y_pos, rsi_clr,       Font_Size, false);
      CreateLabel("MTF_ADX_"   + IntegerToString(i), adx_txt,     Panel_X + 155, y_pos, adx_clr,       Font_Size, false);
      CreateLabel("MTF_TREND_" + IntegerToString(i), trend_txt,   Panel_X + 210, y_pos, trend_clr,     Font_Size, true);
   }
   
   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
