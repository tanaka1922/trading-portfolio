#region Using declarations
using System;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Windows.Media;
using NinjaTrader.Cbi;
using NinjaTrader.Gui;
using NinjaTrader.Gui.Chart;
using NinjaTrader.Data;
using NinjaTrader.NinjaScript;
using NinjaTrader.NinjaScript.DrawingTools;
#endregion

namespace NinjaTrader.NinjaScript.Indicators
{
    public class QQEv6 : Indicator
    {
        #region Variables
        private Series<double> rsiSmoothed;
        private Series<double> atrRsi;
        private Series<double> longBand;
        private Series<double> shortBand;
        private Series<int> trend;
        private Series<double> hmaValue;
        
        private double qqeFactor;
        private int wildersLength;
        #endregion

        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Description = "QQE × HMA Signal v3.0 - AI Score Edition";
                Name = "QQEv6";
                Calculate = Calculate.OnBarClose;
                IsOverlay = true;
                DisplayInDataBox = true;
                DrawOnPricePanel = true;
                PaintPriceMarkers = true;
                ScaleJustification = ScaleJustification.Right;
                IsSuspendedWhileInactive = true;
                
                // Parameters
                RsiPeriod = 14;
                SmoothingFactor = 5;
                HmaLength = 9;
                QqeFactorInput = 4.238;
                MinScore = 60;
                EnableAiScore = true;
                ShowHmaLine = false;
                
                // Colors
                BuyColor = Brushes.Cyan;
                SellColor = Brushes.Magenta;
                BigChanceColor = Brushes.Gold;
            }
            else if (State == State.Configure)
            {
                wildersLength = RsiPeriod * 2 - 1;
                qqeFactor = QqeFactorInput;
            }
            else if (State == State.DataLoaded)
            {
                rsiSmoothed = new Series<double>(this);
                atrRsi = new Series<double>(this);
                longBand = new Series<double>(this);
                shortBand = new Series<double>(this);
                trend = new Series<int>(this);
                hmaValue = new Series<double>(this);
            }
        }

        protected override void OnBarUpdate()
        {
            if (CurrentBar < Math.Max(wildersLength, HmaLength) + 10)
                return;

            // === RSI Calculation ===
            double rsi = RSI(Close, RsiPeriod, 1)[0];
            
            // === Smoothed RSI (EMA) ===
            if (CurrentBar == Math.Max(wildersLength, HmaLength) + 10)
                rsiSmoothed[0] = rsi;
            else
                rsiSmoothed[0] = rsiSmoothed[1] + (2.0 / (SmoothingFactor + 1)) * (rsi - rsiSmoothed[1]);
            
            // === ATR of RSI ===
            double rsiDelta = Math.Abs(rsiSmoothed[0] - rsiSmoothed[1]);
            if (CurrentBar == Math.Max(wildersLength, HmaLength) + 10)
                atrRsi[0] = rsiDelta;
            else
                atrRsi[0] = (atrRsi[1] * (wildersLength - 1) + rsiDelta) / wildersLength;
            
            // === Dynamic Band (dar) ===
            double maAtrRsi = atrRsi[0];
            if (CurrentBar > Math.Max(wildersLength, HmaLength) + 11)
                maAtrRsi = (atrRsi[1] * (wildersLength - 1) + atrRsi[0]) / wildersLength;
            
            double dar = maAtrRsi * qqeFactor;
            
            // === Trailing Bands ===
            double newLongBand = rsiSmoothed[0] - dar;
            double newShortBand = rsiSmoothed[0] + dar;
            
            if (CurrentBar == Math.Max(wildersLength, HmaLength) + 10)
            {
                longBand[0] = newLongBand;
                shortBand[0] = newShortBand;
                trend[0] = 1;
            }
            else
            {
                // Long band logic
                if (rsiSmoothed[1] > longBand[1] && rsiSmoothed[0] > longBand[1])
                    longBand[0] = Math.Max(longBand[1], newLongBand);
                else
                    longBand[0] = newLongBand;
                
                // Short band logic
                if (rsiSmoothed[1] < shortBand[1] && rsiSmoothed[0] < shortBand[1])
                    shortBand[0] = Math.Min(shortBand[1], newShortBand);
                else
                    shortBand[0] = newShortBand;
                
                // Trend detection
                if (CrossAbove(rsiSmoothed, shortBand, 1))
                    trend[0] = 1;
                else if (CrossBelow(rsiSmoothed, longBand, 1))
                    trend[0] = -1;
                else
                    trend[0] = trend[1];
            }
            
            // === QQE Signals ===
            double fastAtrRsiTL = trend[0] == 1 ? longBand[0] : shortBand[0];
            bool qqeLong = trend[0] == 1 && trend[1] != 1;
            bool qqeShort = trend[0] == -1 && trend[1] != -1;
            
            // === HMA Calculation ===
            int halfLen = (int)Math.Floor(HmaLength / 2.0);
            int sqrtLen = (int)Math.Round(Math.Sqrt(HmaLength));
            
            double wma1 = WMA(Close, halfLen)[0];
            double wma2 = WMA(Close, HmaLength)[0];
            double hmaRaw = 2 * wma1 - wma2;
            
            hmaValue[0] = hmaRaw;
            
            bool hmaTrend = Close[0] > hmaValue[0];
            bool hmaLong = CurrentBar > 1 && hmaValue[0] > hmaValue[1] && hmaValue[1] <= hmaValue[2] && Close[0] > hmaValue[0];
            bool hmaShort = CurrentBar > 1 && hmaValue[0] < hmaValue[1] && hmaValue[1] >= hmaValue[2] && Close[0] < hmaValue[0];
            
            // === AI Score ===
            int aiScore = 0;
            if (EnableAiScore)
            {
                double atrCurrent = ATR(14)[0];
                double atrAvg = SMA(ATR(14), 20)[0];
                double atrRatio = atrAvg > 0 ? atrCurrent / atrAvg : 1;
                
                // Signal base
                int sigBase = 0;
                if ((qqeLong && hmaLong) || (qqeShort && hmaShort))
                    sigBase = 35;
                else if (qqeLong || qqeShort || hmaLong || hmaShort)
                    sigBase = 25;
                
                // QQE strength
                double qqeDist = Math.Abs(rsiSmoothed[0] - 50);
                int qqeStr = qqeDist > 30 ? 25 : qqeDist > 20 ? 20 : qqeDist > 10 ? 15 : 10;
                
                // Volatility score
                int volSc = 5;
                if (atrRatio > 1.1 && atrRatio < 2.0)
                    volSc = 15;
                else if (atrRatio < 0.8)
                    volSc = -10;
                
                // Volume confirmation
                double volAvg = SMA(Volume, 20)[0];
                double volRatio = volAvg > 0 ? Volume[0] / volAvg : 1;
                int volConf = volRatio > 1.2 ? 15 : volRatio < 0.8 ? -5 : 0;
                
                int rawScore = sigBase + qqeStr + volSc + volConf + 15;
                aiScore = Math.Max(0, Math.Min(100, rawScore));
            }
            
            // === Signal Display ===
            if (qqeLong && aiScore >= MinScore)
            {
                string signalType = "";
                Brush bgColor = BuyColor;
                
                if (aiScore >= 90)
                {
                    signalType = "BIG CHANCE";
                    bgColor = BigChanceColor;
                }
                else if (aiScore >= 80)
                {
                    signalType = "SUPER";
                    bgColor = Brushes.Yellow;
                }
                else if (aiScore >= 70 && hmaLong)
                {
                    signalType = "POWER";
                    bgColor = BuyColor;
                }
                else if (aiScore >= 60 && hmaTrend)
                {
                    signalType = "STRONG";
                    bgColor = Brushes.Lime;
                }
                
                if (!string.IsNullOrEmpty(signalType))
                {
                    Draw.ArrowUp(this, "BuyArrow" + CurrentBar, true, 0, Low[0] - TickSize * 10, bgColor);
                    Draw.Text(this, "BuyText" + CurrentBar, signalType + "\nBUY " + aiScore, 0, Low[0] - TickSize * 25, bgColor);
                }
            }
            
            if (qqeShort && aiScore >= MinScore)
            {
                string signalType = "";
                Brush bgColor = SellColor;
                
                if (aiScore >= 90)
                {
                    signalType = "BIG CHANCE";
                    bgColor = BigChanceColor;
                }
                else if (aiScore >= 80)
                {
                    signalType = "SUPER";
                    bgColor = Brushes.Yellow;
                }
                else if (aiScore >= 70 && hmaShort)
                {
                    signalType = "POWER";
                    bgColor = SellColor;
                }
                else if (aiScore >= 60 && !hmaTrend)
                {
                    signalType = "STRONG";
                    bgColor = Brushes.Red;
                }
                
                if (!string.IsNullOrEmpty(signalType))
                {
                    Draw.ArrowDown(this, "SellArrow" + CurrentBar, true, 0, High[0] + TickSize * 10, bgColor);
                    Draw.Text(this, "SellText" + CurrentBar, signalType + "\nSELL " + aiScore, 0, High[0] + TickSize * 25, bgColor);
                }
            }
            
            // === HMA Line (optional) ===
            if (ShowHmaLine)
            {
                PlotBrushes[0][0] = hmaTrend ? BuyColor : SellColor;
            }
        }
        
        #region Properties
        [NinjaScriptProperty]
        [Range(1, 50)]
        [Display(Name = "RSI Period", Order = 1, GroupName = "QQE Settings")]
        public int RsiPeriod { get; set; }
        
        [NinjaScriptProperty]
        [Range(1, 20)]
        [Display(Name = "Smoothing Factor", Order = 2, GroupName = "QQE Settings")]
        public int SmoothingFactor { get; set; }
        
        [NinjaScriptProperty]
        [Range(1.0, 20.0)]
        [Display(Name = "QQE Factor", Order = 3, GroupName = "QQE Settings")]
        public double QqeFactorInput { get; set; }
        
        [NinjaScriptProperty]
        [Range(3, 50)]
        [Display(Name = "HMA Length", Order = 4, GroupName = "HMA Settings")]
        public int HmaLength { get; set; }
        
        [NinjaScriptProperty]
        [Range(40, 90)]
        [Display(Name = "Min Score", Order = 5, GroupName = "AI Settings")]
        public int MinScore { get; set; }
        
        [NinjaScriptProperty]
        [Display(Name = "Enable AI Score", Order = 6, GroupName = "AI Settings")]
        public bool EnableAiScore { get; set; }
        
        [NinjaScriptProperty]
        [Display(Name = "Show HMA Line", Order = 7, GroupName = "Display")]
        public bool ShowHmaLine { get; set; }
        
        [NinjaScriptProperty]
        [Display(Name = "Buy Color", Order = 8, GroupName = "Colors")]
        public Brush BuyColor { get; set; }
        
        [NinjaScriptProperty]
        [Display(Name = "Sell Color", Order = 9, GroupName = "Colors")]
        public Brush SellColor { get; set; }
        
        [NinjaScriptProperty]
        [Display(Name = "Big Chance Color", Order = 10, GroupName = "Colors")]
        public Brush BigChanceColor { get; set; }
        #endregion
    }
}

#region NinjaScript generated code. Neither change nor remove.

namespace NinjaTrader.NinjaScript.Indicators
{
	public partial class Indicator : NinjaTrader.Gui.NinjaScript.IndicatorRenderBase
	{
		private QQEv6[] cacheQQEv6;
		public QQEv6 QQEv6(int rsiPeriod, int smoothingFactor, double qqeFactorInput, int hmaLength, int minScore, bool enableAiScore, bool showHmaLine, Brush buyColor, Brush sellColor, Brush bigChanceColor)
		{
			return QQEv6(Input, rsiPeriod, smoothingFactor, qqeFactorInput, hmaLength, minScore, enableAiScore, showHmaLine, buyColor, sellColor, bigChanceColor);
		}

		public QQEv6 QQEv6(ISeries<double> input, int rsiPeriod, int smoothingFactor, double qqeFactorInput, int hmaLength, int minScore, bool enableAiScore, bool showHmaLine, Brush buyColor, Brush sellColor, Brush bigChanceColor)
		{
			if (cacheQQEv6 != null)
				for (int idx = 0; idx < cacheQQEv6.Length; idx++)
					if (cacheQQEv6[idx] != null && cacheQQEv6[idx].RsiPeriod == rsiPeriod && cacheQQEv6[idx].SmoothingFactor == smoothingFactor && cacheQQEv6[idx].QqeFactorInput == qqeFactorInput && cacheQQEv6[idx].HmaLength == hmaLength && cacheQQEv6[idx].MinScore == minScore && cacheQQEv6[idx].EnableAiScore == enableAiScore && cacheQQEv6[idx].ShowHmaLine == showHmaLine && cacheQQEv6[idx].BuyColor == buyColor && cacheQQEv6[idx].SellColor == sellColor && cacheQQEv6[idx].BigChanceColor == bigChanceColor && cacheQQEv6[idx].EqualsInput(input))
						return cacheQQEv6[idx];
			return CacheIndicator<QQEv6>(new QQEv6(){ RsiPeriod = rsiPeriod, SmoothingFactor = smoothingFactor, QqeFactorInput = qqeFactorInput, HmaLength = hmaLength, MinScore = minScore, EnableAiScore = enableAiScore, ShowHmaLine = showHmaLine, BuyColor = buyColor, SellColor = sellColor, BigChanceColor = bigChanceColor }, input, ref cacheQQEv6);
		}
	}
}

namespace NinjaTrader.NinjaScript.MarketAnalyzerColumns
{
	public partial class MarketAnalyzerColumn : MarketAnalyzerColumnBase
	{
		public Indicators.QQEv6 QQEv6(int rsiPeriod, int smoothingFactor, double qqeFactorInput, int hmaLength, int minScore, bool enableAiScore, bool showHmaLine, Brush buyColor, Brush sellColor, Brush bigChanceColor)
		{
			return indicator.QQEv6(Input, rsiPeriod, smoothingFactor, qqeFactorInput, hmaLength, minScore, enableAiScore, showHmaLine, buyColor, sellColor, bigChanceColor);
		}

		public Indicators.QQEv6 QQEv6(ISeries<double> input, int rsiPeriod, int smoothingFactor, double qqeFactorInput, int hmaLength, int minScore, bool enableAiScore, bool showHmaLine, Brush buyColor, Brush sellColor, Brush bigChanceColor)
		{
			return indicator.QQEv6(input, rsiPeriod, smoothingFactor, qqeFactorInput, hmaLength, minScore, enableAiScore, showHmaLine, buyColor, sellColor, bigChanceColor);
		}
	}
}

namespace NinjaTrader.NinjaScript.Strategies
{
	public partial class Strategy : NinjaTrader.Gui.NinjaScript.StrategyRenderBase
	{
		public Indicators.QQEv6 QQEv6(int rsiPeriod, int smoothingFactor, double qqeFactorInput, int hmaLength, int minScore, bool enableAiScore, bool showHmaLine, Brush buyColor, Brush sellColor, Brush bigChanceColor)
		{
			return indicator.QQEv6(Input, rsiPeriod, smoothingFactor, qqeFactorInput, hmaLength, minScore, enableAiScore, showHmaLine, buyColor, sellColor, bigChanceColor);
		}

		public Indicators.QQEv6 QQEv6(ISeries<double> input, int rsiPeriod, int smoothingFactor, double qqeFactorInput, int hmaLength, int minScore, bool enableAiScore, bool showHmaLine, Brush buyColor, Brush sellColor, Brush bigChanceColor)
		{
			return indicator.QQEv6(input, rsiPeriod, smoothingFactor, qqeFactorInput, hmaLength, minScore, enableAiScore, showHmaLine, buyColor, sellColor, bigChanceColor);
		}
	}
}

#endregion
