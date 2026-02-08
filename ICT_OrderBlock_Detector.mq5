//+------------------------------------------------------------------+
//|                                     ICT_OrderBlock_Detector.mq5  |
//|                        Copyright 2026, Seiichi Tanaka / EduVest  |
//|                  https://github.com/tanaka1922/trading-portfolio  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Seiichi Tanaka / EduVest"
#property link      "https://github.com/tanaka1922/trading-portfolio"
#property version   "1.00"
#property description "ICT Order Block Detector - Smart Money Concepts"
#property description "Identifies bullish and bearish order blocks based on"
#property description "displacement candles and structural breaks."
#property description "Draws rectangles on chart marking active OB zones."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Bullish OB markers
#property indicator_label1  "Bullish OB"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_width1  2

//--- Bearish OB markers
#property indicator_label2  "Bearish OB"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_width2  2

//--- Input Parameters
input int    Lookback         = 100;     // Lookback Bars
input double Displacement_ATR = 1.5;     // Min Displacement (x ATR)
input int    ATR_Period       = 14;      // ATR Period
input int    Max_OB_Display   = 10;      // Max Order Blocks to Display
input color  Bull_OB_Color    = clrDarkGreen;   // Bullish OB Box Color
input color  Bear_OB_Color    = clrDarkRed;     // Bearish OB Box Color
input bool   Show_Boxes       = true;    // Draw OB Rectangles
input bool   Show_Arrows      = true;    // Show Arrow Markers
input int    OB_Extend_Bars   = 20;      // Extend OB Box (bars forward)

//--- Indicator Buffers
double BullOB_Buffer[];
double BearOB_Buffer[];

//--- ATR Handle
int atr_handle;

//--- OB tracking
struct OrderBlock
{
   datetime time_start;
   double   high;
   double   low;
   bool     is_bullish;
   bool     is_active;
   string   obj_name;
};

OrderBlock OB_List[];
int OB_Count;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BullOB_Buffer, INDICATOR_DATA);
   SetIndexBuffer(1, BearOB_Buffer, INDICATOR_DATA);
   
   //--- Arrow codes
   PlotIndexSetInteger(0, PLOT_ARROW, 233);  // Up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);  // Down arrow
   
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   
   atr_handle = iATR(_Symbol, _Period, ATR_Period);
   if(atr_handle == INVALID_HANDLE)
   {
      Print("Error creating ATR handle");
      return(INIT_FAILED);
   }
   
   OB_Count = 0;
   ArrayResize(OB_List, Max_OB_Display * 2);
   
   IndicatorSetString(INDICATOR_SHORTNAME, "ICT Order Blocks");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "OB_");
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
void DrawOBBox(string name, datetime time1, datetime time2, 
               double price1, double price2, color clr, bool is_bull)
{
   if(!Show_Boxes) return;
   
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, time1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, time2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price2);
   }
   
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   
   //--- Add label
   string label_name = name + "_LBL";
   if(ObjectFind(0, label_name) < 0)
      ObjectCreate(0, label_name, OBJ_TEXT, 0, time1, is_bull ? price1 : price2);
   
   ObjectSetString(0, label_name, OBJPROP_TEXT, is_bull ? "Bull OB" : "Bear OB");
   ObjectSetInteger(0, label_name, OBJPROP_COLOR, is_bull ? clrLimeGreen : clrOrangeRed);
   ObjectSetString(0, label_name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, is_bull ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
}

//+------------------------------------------------------------------+
bool IsDisplacement(double candle_body, double atr_val)
{
   return (candle_body > Displacement_ATR * atr_val);
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
   int min_bars = ATR_Period + Lookback + 5;
   if(rates_total < min_bars) return(0);
   
   //--- Copy ATR
   double atr_data[];
   if(CopyBuffer(atr_handle, 0, 0, rates_total, atr_data) <= 0) return(0);
   
   //--- Clear old objects
   if(prev_calculated == 0)
   {
      ObjectsDeleteAll(0, "OB_");
      OB_Count = 0;
   }
   
   int start = MathMax(prev_calculated - 3, ATR_Period + 3);
   int ob_idx = 0;
   
   for(int i = start; i < rates_total - 1; i++)
   {
      BullOB_Buffer[i] = 0.0;
      BearOB_Buffer[i] = 0.0;
      
      if(i < 3) continue;
      
      double atr = atr_data[i];
      if(atr <= 0) continue;
      
      //--- Current candle body
      double body = MathAbs(close[i] - open[i]);
      
      //--- Check for BULLISH Order Block
      //--- Pattern: down candle(s) followed by strong up displacement
      if(close[i] > open[i] && IsDisplacement(body, atr))
      {
         //--- Previous candle was bearish (the order block candle)
         if(close[i-1] < open[i-1])
         {
            //--- Verify displacement: current close above previous high
            if(close[i] > high[i-1])
            {
               if(Show_Arrows)
                  BullOB_Buffer[i-1] = low[i-1];
               
               if(Show_Boxes && ob_idx < Max_OB_Display)
               {
                  string name = "OB_Bull_" + IntegerToString(i);
                  datetime end_time = time[MathMin(i + OB_Extend_Bars, rates_total - 1)];
                  DrawOBBox(name, time[i-1], end_time, low[i-1], MathMax(open[i-1], close[i-1]), Bull_OB_Color, true);
                  ob_idx++;
               }
            }
         }
      }
      
      //--- Check for BEARISH Order Block
      //--- Pattern: up candle(s) followed by strong down displacement
      if(close[i] < open[i] && IsDisplacement(body, atr))
      {
         //--- Previous candle was bullish (the order block candle)
         if(close[i-1] > open[i-1])
         {
            //--- Verify displacement: current close below previous low
            if(close[i] < low[i-1])
            {
               if(Show_Arrows)
                  BearOB_Buffer[i-1] = high[i-1];
               
               if(Show_Boxes && ob_idx < Max_OB_Display)
               {
                  string name = "OB_Bear_" + IntegerToString(i);
                  datetime end_time = time[MathMin(i + OB_Extend_Bars, rates_total - 1)];
                  DrawOBBox(name, time[i-1], end_time, MathMin(open[i-1], close[i-1]), high[i-1], Bear_OB_Color, false);
                  ob_idx++;
               }
            }
         }
      }
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+
