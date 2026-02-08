//+------------------------------------------------------------------+
//|                                    BB_Squeeze_Momentum.mq5       |
//|                        Copyright 2026, Seiichi Tanaka / EduVest  |
//|                  https://github.com/tanaka1922/trading-portfolio  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Seiichi Tanaka / EduVest"
#property link      "https://github.com/tanaka1922/trading-portfolio"
#property version   "1.00"
#property description "Bollinger Bands Squeeze Momentum Indicator"
#property description "Detects BB squeeze (low volatility) and momentum breakouts."
#property description "Green dots = BB inside Keltner (squeeze on)."
#property description "Red dots = BB outside Keltner (squeeze off / momentum firing)."
#property description "Histogram shows momentum direction and strength."
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   2

//--- Plot 1: Momentum Histogram
#property indicator_label1  "Momentum"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrLime,clrGreen,clrRed,clrMaroon
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- Plot 2: Squeeze Dots
#property indicator_label2  "Squeeze"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_color2  clrLime,clrRed,clrGray
#property indicator_style2  STYLE_SOLID
#property indicator_width2  4

//--- Input Parameters
input int    BB_Period       = 20;     // Bollinger Band Period
input double BB_Mult         = 2.0;    // BB Multiplier
input int    KC_Period       = 20;     // Keltner Channel Period
input double KC_Mult         = 1.5;    // KC Multiplier
input int    Mom_Length      = 12;     // Momentum Length
input ENUM_APPLIED_PRICE Applied_Price = PRICE_CLOSE; // Applied Price

//--- Indicator Buffers
double MomBuffer[];        // Momentum histogram
double MomColorBuffer[];   // Momentum color
double SqzBuffer[];        // Squeeze dots
double SqzColorBuffer[];   // Squeeze color
double TempBuffer[];       // Temp calculations

//--- Handles
int bb_handle;
int atr_handle;
int ma_handle;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, MomBuffer,      INDICATOR_DATA);
   SetIndexBuffer(1, MomColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, SqzBuffer,      INDICATOR_DATA);
   SetIndexBuffer(3, SqzColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, TempBuffer,     INDICATOR_CALCULATIONS);
   
   //--- Zero line
   IndicatorSetInteger(INDICATOR_LEVELS, 1);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, 0.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
   
   IndicatorSetString(INDICATOR_SHORTNAME, 
      "BB Squeeze(" + IntegerToString(BB_Period) + "," + 
      DoubleToString(BB_Mult, 1) + ")");
   
   //--- Create handles
   bb_handle  = iBands(_Symbol, _Period, BB_Period, 0, BB_Mult, Applied_Price);
   atr_handle = iATR(_Symbol, _Period, KC_Period);
   ma_handle  = iMA(_Symbol, _Period, KC_Period, 0, MODE_EMA, Applied_Price);
   
   if(bb_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE || ma_handle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(bb_handle != INVALID_HANDLE)  IndicatorRelease(bb_handle);
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
   if(ma_handle != INVALID_HANDLE)  IndicatorRelease(ma_handle);
}

//+------------------------------------------------------------------+
double LinearRegression(const double &src[], int length, int shift)
{
   if(shift < length) return(0);
   
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
   
   for(int i = 0; i < length; i++)
   {
      double x = (double)i;
      double y = src[shift - length + 1 + i];
      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
   }
   
   double n = (double)length;
   double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
   double intercept = (sumY - slope * sumX) / n;
   
   return(intercept + slope * (n - 1));
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
   int min_bars = MathMax(BB_Period, KC_Period) + Mom_Length + 10;
   if(rates_total < min_bars) return(0);
   
   //--- Copy indicator data
   double bb_upper[], bb_lower[], bb_middle[];
   double atr_data[], ma_data[];
   
   if(CopyBuffer(bb_handle, 1, 0, rates_total, bb_upper) <= 0) return(0);
   if(CopyBuffer(bb_handle, 2, 0, rates_total, bb_lower) <= 0) return(0);
   if(CopyBuffer(bb_handle, 0, 0, rates_total, bb_middle) <= 0) return(0);
   if(CopyBuffer(atr_handle, 0, 0, rates_total, atr_data) <= 0) return(0);
   if(CopyBuffer(ma_handle, 0, 0, rates_total, ma_data) <= 0) return(0);
   
   int start = (prev_calculated > 0) ? prev_calculated - 1 : min_bars;
   
   //--- First pass: calculate delta values for linear regression
   for(int i = start; i < rates_total; i++)
   {
      //--- Keltner Channel bounds
      double kc_upper = ma_data[i] + KC_Mult * atr_data[i];
      double kc_lower = ma_data[i] - KC_Mult * atr_data[i];
      
      //--- Squeeze detection
      bool squeeze_on = (bb_lower[i] > kc_lower && bb_upper[i] < kc_upper);
      
      SqzBuffer[i] = 0.0;
      if(squeeze_on)
         SqzColorBuffer[i] = 0;  // Green dots (squeeze on)
      else
         SqzColorBuffer[i] = 1;  // Red dots (squeeze off)
      
      //--- Momentum: Linear regression of (close - avg(highest high, lowest low, close midline))
      double highest = high[i];
      double lowest  = low[i];
      for(int j = 1; j < Mom_Length && (i - j) >= 0; j++)
      {
         if(high[i - j] > highest) highest = high[i - j];
         if(low[i - j] < lowest)   lowest  = low[i - j];
      }
      
      double midline = (highest + lowest) / 2.0;
      double avg_mid = (midline + bb_middle[i]) / 2.0;
      TempBuffer[i] = close[i] - avg_mid;
   }
   
   //--- Second pass: apply linear regression to momentum
   for(int i = start; i < rates_total; i++)
   {
      if(i >= Mom_Length)
         MomBuffer[i] = LinearRegression(TempBuffer, Mom_Length, i);
      else
         MomBuffer[i] = 0;
      
      //--- Color: 4 states based on momentum direction and acceleration
      if(MomBuffer[i] > 0)
      {
         if(i > 0 && MomBuffer[i] > MomBuffer[i-1])
            MomColorBuffer[i] = 0;  // Lime (positive & increasing)
         else
            MomColorBuffer[i] = 1;  // Dark Green (positive & decreasing)
      }
      else
      {
         if(i > 0 && MomBuffer[i] < MomBuffer[i-1])
            MomColorBuffer[i] = 2;  // Red (negative & decreasing)
         else
            MomColorBuffer[i] = 3;  // Maroon (negative & increasing)
      }
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+
