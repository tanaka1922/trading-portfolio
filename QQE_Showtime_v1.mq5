//+------------------------------------------------------------------+
//|                                          QQE_Showtime_v1.mq5     |
//|                        Copyright 2026, Seiichi Tanaka / EduVest  |
//|                  https://github.com/tanaka1922/trading-portfolio  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Seiichi Tanaka / EduVest"
#property link      "https://github.com/tanaka1922/trading-portfolio"
#property version   "1.00"
#property description "QQE Showtime - Smoothed RSI with Dynamic Volatility Bands"
#property description "Combines QQE (Qualitative Quantitative Estimation) with"
#property description "HMA smoothing for clearer trend identification."
#property description "Green/Red histogram shows trend direction with signal strength."
#property indicator_separate_window
#property indicator_buffers 7
#property indicator_plots   3

//--- Plot 1: QQE Line
#property indicator_label1  "QQE Line"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: Signal Line
#property indicator_label2  "Signal"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Plot 3: Histogram (Trend Strength)
#property indicator_label3  "Trend Strength"
#property indicator_type3   DRAW_COLOR_HISTOGRAM
#property indicator_color3  clrLimeGreen,clrRed,clrGray
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- Input Parameters
input int    RSI_Period     = 14;     // RSI Period
input int    SF             = 5;      // RSI Smoothing Factor
input double QQE_Factor     = 4.236;  // QQE Factor (Volatility Multiplier)
input int    HMA_Period     = 6;      // HMA Smoothing Period
input int    Signal_Period  = 3;      // Signal Line Period
input double Threshold      = 0.0;    // Histogram Threshold

//--- Indicator Buffers
double QQE_Buffer[];       // QQE Main Line
double Signal_Buffer[];    // Signal Line
double Hist_Buffer[];      // Histogram Values
double Hist_Color[];       // Histogram Colors
double RSI_Buffer[];       // Raw RSI
double Smooth_RSI[];       // Smoothed RSI
double TR_Buffer[];        // Trailing (for QQE bands)

//--- Global Variables
int rsi_handle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set indicator buffers
   SetIndexBuffer(0, QQE_Buffer,    INDICATOR_DATA);
   SetIndexBuffer(1, Signal_Buffer, INDICATOR_DATA);
   SetIndexBuffer(2, Hist_Buffer,   INDICATOR_DATA);
   SetIndexBuffer(3, Hist_Color,    INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, RSI_Buffer,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, Smooth_RSI,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, TR_Buffer,     INDICATOR_CALCULATIONS);
   
   //--- Set levels
   IndicatorSetInteger(INDICATOR_LEVELS, 2);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, 50.0 + Threshold);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, 50.0 - Threshold);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrGray);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 1, STYLE_DOT);
   
   //--- Set indicator name
   IndicatorSetString(INDICATOR_SHORTNAME, 
      "QQE Showtime(" + IntegerToString(RSI_Period) + "," + 
      IntegerToString(SF) + "," + DoubleToString(QQE_Factor, 3) + ")");
   
   //--- Get RSI handle
   rsi_handle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   if(rsi_handle == INVALID_HANDLE)
   {
      Print("Error creating RSI handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(rsi_handle != INVALID_HANDLE)
      IndicatorRelease(rsi_handle);
}

//+------------------------------------------------------------------+
//| EMA calculation helper                                            |
//+------------------------------------------------------------------+
double EMA(double current_value, double prev_ema, int period)
{
   double k = 2.0 / (period + 1.0);
   return current_value * k + prev_ema * (1.0 - k);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
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
   //--- Check minimum bars
   int min_bars = RSI_Period + SF + HMA_Period + 50;
   if(rates_total < min_bars) return(0);
   
   //--- Copy RSI data
   int copied = CopyBuffer(rsi_handle, 0, 0, rates_total, RSI_Buffer);
   if(copied <= 0) return(0);
   
   //--- Determine starting position
   int start;
   if(prev_calculated <= 0)
   {
      start = RSI_Period + 1;
      
      //--- Initialize buffers
      for(int i = 0; i < start; i++)
      {
         QQE_Buffer[i]    = 0.0;
         Signal_Buffer[i] = 0.0;
         Hist_Buffer[i]   = 0.0;
         Hist_Color[i]    = 2;
         Smooth_RSI[i]    = 50.0;
         TR_Buffer[i]     = 0.0;
      }
      
      //--- First smoothed RSI value
      Smooth_RSI[start] = RSI_Buffer[start];
   }
   else
   {
      start = prev_calculated - 1;
   }
   
   //--- Main calculation loop
   for(int i = start; i < rates_total; i++)
   {
      //--- Step 1: Smooth the RSI with EMA
      Smooth_RSI[i] = EMA(RSI_Buffer[i], Smooth_RSI[i-1], SF);
      
      //--- Step 2: Calculate absolute difference for volatility
      double delta = MathAbs(Smooth_RSI[i] - Smooth_RSI[i-1]);
      
      //--- Step 3: EMA of the delta (Average True Range of RSI)
      double ema_delta = EMA(delta, (TR_Buffer[i-1] > 0 ? TR_Buffer[i-1] : delta), RSI_Period);
      TR_Buffer[i] = ema_delta;
      
      //--- Step 4: Dynamic bands
      double upper_band = Smooth_RSI[i] + QQE_Factor * ema_delta;
      double lower_band = Smooth_RSI[i] - QQE_Factor * ema_delta;
      
      //--- Step 5: QQE trailing logic
      double prev_qqe = QQE_Buffer[i-1];
      
      if(prev_qqe == 0.0) prev_qqe = Smooth_RSI[i];
      
      if(Smooth_RSI[i] > prev_qqe)
      {
         QQE_Buffer[i] = (lower_band > prev_qqe) ? lower_band : prev_qqe;
      }
      else
      {
         QQE_Buffer[i] = (upper_band < prev_qqe) ? upper_band : prev_qqe;
      }
      
      //--- Step 6: Signal line (EMA of QQE)
      Signal_Buffer[i] = EMA(QQE_Buffer[i], Signal_Buffer[i-1], Signal_Period);
      
      //--- Step 7: Histogram = difference between smoothed RSI and 50 level
      double strength = Smooth_RSI[i] - 50.0;
      Hist_Buffer[i] = strength;
      
      //--- Step 8: Color assignment
      if(Smooth_RSI[i] > QQE_Buffer[i] && strength > Threshold)
         Hist_Color[i] = 0;  // Green (Bullish)
      else if(Smooth_RSI[i] < QQE_Buffer[i] && strength < -Threshold)
         Hist_Color[i] = 1;  // Red (Bearish)
      else
         Hist_Color[i] = 2;  // Gray (Neutral)
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+
