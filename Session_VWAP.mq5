//+------------------------------------------------------------------+
//|                                          Session_VWAP.mq5        |
//|                        Copyright 2026, Seiichi Tanaka / EduVest  |
//|                  https://github.com/tanaka1922/trading-portfolio  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Seiichi Tanaka / EduVest"
#property link      "https://github.com/tanaka1922/trading-portfolio"
#property version   "1.00"
#property description "Session VWAP (Volume Weighted Average Price)"
#property description "Calculates VWAP with Standard Deviation Bands."
#property description "Resets at the start of each session (daily or custom)."
#property description "Upper/Lower bands show 1SD and 2SD levels."
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

//--- VWAP Line
#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Upper Band 1 (+1 SD)
#property indicator_label2  "+1 SD"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDarkGray
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Lower Band 1 (-1 SD)
#property indicator_label3  "-1 SD"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDarkGray
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

//--- Upper Band 2 (+2 SD)
#property indicator_label4  "+2 SD"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrSlateGray
#property indicator_style4  STYLE_DASHDOT
#property indicator_width4  1

//--- Lower Band 2 (-2 SD)
#property indicator_label5  "-2 SD"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrSlateGray
#property indicator_style5  STYLE_DASHDOT
#property indicator_width5  1

//--- Input Parameters
input ENUM_TIMEFRAMES Reset_Period = PERIOD_D1;  // VWAP Reset Period (D1=Daily)
input double SD1_Multiplier = 1.0;    // 1st Band SD Multiplier
input double SD2_Multiplier = 2.0;    // 2nd Band SD Multiplier
input bool   Use_Real_Volume = false;  // Use Real Volume (vs Tick Volume)

//--- Indicator Buffers
double VwapBuffer[];
double UpperSD1[];
double LowerSD1[];
double UpperSD2[];
double LowerSD2[];

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, VwapBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, UpperSD1,   INDICATOR_DATA);
   SetIndexBuffer(2, LowerSD1,   INDICATOR_DATA);
   SetIndexBuffer(3, UpperSD2,   INDICATOR_DATA);
   SetIndexBuffer(4, LowerSD2,   INDICATOR_DATA);
   
   IndicatorSetString(INDICATOR_SHORTNAME, "Session VWAP");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
bool IsNewSession(const datetime &time[], int i)
{
   if(i <= 0) return true;
   
   MqlDateTime dt_curr, dt_prev;
   TimeToStruct(time[i], dt_curr);
   TimeToStruct(time[i-1], dt_prev);
   
   switch(Reset_Period)
   {
      case PERIOD_D1:
         return (dt_curr.day != dt_prev.day);
      case PERIOD_W1:
         return (dt_curr.day_of_week < dt_prev.day_of_week || 
                 (dt_curr.day - dt_prev.day) > 1);
      case PERIOD_MN1:
         return (dt_curr.mon != dt_prev.mon);
      case PERIOD_H4:
         return ((dt_curr.hour / 4) != (dt_prev.hour / 4) || dt_curr.day != dt_prev.day);
      default:
         return (dt_curr.day != dt_prev.day);
   }
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
   
   int start = (prev_calculated > 1) ? prev_calculated - 1 : 0;
   
   //--- Running totals
   static double cum_vol;
   static double cum_pv;      // cumulative (price * volume)
   static double cum_pv2;     // cumulative (price^2 * volume)
   
   if(start == 0)
   {
      cum_vol = 0;
      cum_pv  = 0;
      cum_pv2 = 0;
   }
   
   for(int i = start; i < rates_total; i++)
   {
      //--- Check for new session
      if(IsNewSession(time, i))
      {
         cum_vol = 0;
         cum_pv  = 0;
         cum_pv2 = 0;
      }
      
      //--- Typical price
      double tp = (high[i] + low[i] + close[i]) / 3.0;
      
      //--- Volume
      double vol;
      if(Use_Real_Volume && volume[i] > 0)
         vol = (double)volume[i];
      else
         vol = (double)tick_volume[i];
      
      //--- Avoid zero volume
      if(vol < 1) vol = 1;
      
      //--- Accumulate
      cum_vol += vol;
      cum_pv  += tp * vol;
      cum_pv2 += tp * tp * vol;
      
      //--- VWAP
      double vwap = cum_pv / cum_vol;
      VwapBuffer[i] = vwap;
      
      //--- Standard Deviation
      double variance = (cum_pv2 / cum_vol) - (vwap * vwap);
      double sd = (variance > 0) ? MathSqrt(variance) : 0;
      
      //--- Bands
      UpperSD1[i] = vwap + SD1_Multiplier * sd;
      LowerSD1[i] = vwap - SD1_Multiplier * sd;
      UpperSD2[i] = vwap + SD2_Multiplier * sd;
      LowerSD2[i] = vwap - SD2_Multiplier * sd;
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+
