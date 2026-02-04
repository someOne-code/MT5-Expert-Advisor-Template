//-PROPERTIES-//
#property link          "https://www.earnforex.com/metatrader-expert-advisors/mt5-ea-template/"
#property version       "1.00"
#property copyright     "EarnForex.com - 2025"
#property description   "Jules EA Implementation - Clean Slate"
#property description   ""
#property description   "Based on EarnForex MT5 EA Template"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

//-INCLUDES-//
#include <Trade\Trade.mqh> // Easy trade management

//-INPUTS-//
input group "Strateji Ayarlari"
input double InpLotSize        = 0.01; // Islem Hacmi (Lot)
input int    InpMAHours        = 7;    // Hareketli Ortalama Saati (7)
input int    InpTrendPeriod    = 25;   // Trend Teyidi Mum Sayisi (25)
input int    InpDelaySeconds   = 20;   // Maksimum Giris Gecikmesi (Saniye)
input double InpMinProfit      = 10.0; // Minimum Kar (Yavas Hedef)
input double InpMaxProfit      = 50.0; // Maksimum Kar (Hizli Hedef)
input int    InpMinTrades      = 2;    // Min Islem Adedi
input int    InpMaxTrades      = 7;    // Max Islem Adedi
input int    InpMomentumTime   = 60;   // Momentum Zaman Siniri (Saniye)
input double InpMaxSpreadPoints= 0;    // Max Spread (Puan, 0=Devre Disi)

input group "Zaman Ayarlari (Gate)"
input bool   InpEnableSundayGate = false;// Pazar Gate Aktif Et
input int    InpGateHour       = 5;    // Gate Saati (Orn: 05:00)
input int    InpGateMinute     = 0;    // Gate Dakikasi
input int    InpGateDay        = 1;    // Gate Gunu (0=Paz, 1=Pzt)

input group "Genel Ayarlar"
input long   InpMagicNumber    = 20240101; // Magic Numarasi
input string InpComment        = "JulesEA"; // Emir Yorumu

//-GLOBAL VARIABLES-//
CTrade Trade; // Trade object
datetime ExtLastBar = 0; // Last processed bar time
int    ExtHandleMA = INVALID_HANDLE; // Moving Average Handle
int    ExtHandleATR = INVALID_HANDLE; // ATR Handle

// Pending State
enum PendingSignal { PENDING_NONE, PENDING_BUY, PENDING_SELL };
PendingSignal ExtPendingState = PENDING_NONE;
datetime      ExtPendingSince = 0;
int           ExtPendingDelay = 0;

//+------------------------------------------------------------------+
//| Helper: Check for New Bar                                        |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime current = iTime(Symbol(), Period(), 0);
   if (current == 0) return false;

   if (current != ExtLastBar)
   {
       ExtLastBar = current;
       return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Helper: Get Rates Safely (Retry Loop)                            |
//+------------------------------------------------------------------+
bool GetRates(string symbol, ENUM_TIMEFRAMES timeframe, int count, MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   int attempts = 3;

   for(int i=0; i<attempts; i++)
   {
      int copied = CopyRates(symbol, timeframe, 0, count, rates);
      if (copied == count) return true;

      int err = GetLastError();
      if (err == 4401) // History not found/ready
      {
         PrintFormat("Gecmis veri hazirlaniyor (%s, %d). Deneme %d...", symbol, timeframe, i+1);
         Sleep(100); // Wait for terminal
         continue;
      }

      PrintFormat("Hata: CopyRates basarisiz (%d/%d). Hata Kodu: %d", copied, count, err);
      Sleep(50);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Task 9: Dynamic Trade Count                                      |
//+------------------------------------------------------------------+
int GetTradeCount(const MqlRates &rates[], int trendPeriod)
{
    if (ExtHandleATR == INVALID_HANDLE) return InpMinTrades;

    // 1. Calculate Average Body Size of recent Trend Period
    double totalBody = 0;
    for(int i=1; i<=trendPeriod; i++)
    {
       if(i >= ArraySize(rates)) break;
       totalBody += MathAbs(rates[i].close - rates[i].open);
    }
    double avgBody = totalBody / trendPeriod;

    // 2. Get ATR
    double atrBuf[1];
    if (CopyBuffer(ExtHandleATR, 0, 0, 1, atrBuf) != 1) return InpMinTrades;
    double atr = atrBuf[0];

    if (atr <= 0) return InpMinTrades; // Prevent division by zero

    // 3. Score = AvgBody / ATR
    // If Body is large relative to ATR -> Strong Move -> More Trades
    double score = avgBody / atr;

    // 4. Map Score (e.g., 0.2 to 1.0) to MinTrades..MaxTrades
    double minScore = 0.2;
    double maxScore = 1.0;

    double factor = (score - minScore) / (maxScore - minScore);
    if (factor < 0) factor = 0;
    if (factor > 1) factor = 1;

    int count = (int)(InpMinTrades + factor * (InpMaxTrades - InpMinTrades));

    PrintFormat("Pazar Gucu Analizi: AvgBody=%.5f ATR=%.5f Score=%.2f -> Islem Adedi: %d",
        avgBody, atr, score, count);

    return count;
}

//+------------------------------------------------------------------+
//| Task 11: Dynamic Exit Logic                                      |
//+------------------------------------------------------------------+
void CheckExits()
{
    int total = PositionsTotal();
    for(int i=total-1; i>=0; i--)
    {
        // Select by index
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) continue;

        // Filter by Symbol and Magic
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        // Check Profit & Time
        double profit   = PositionGetDouble(POSITION_PROFIT);
        long   openTime = PositionGetInteger(POSITION_TIME);
        long   elapsed  = TimeCurrent() - openTime;

        double target = InpMinProfit; // Default Slow Target
        string type   = "Yavas/Min";

        // If trade is young (high momentum), aim for MaxProfit
        if (elapsed < InpMomentumTime)
        {
            target = InpMaxProfit;
            type   = "Hizli/Max";
        }

        if (profit >= target)
        {
            PrintFormat("Dinamik Kar Al (%s): Ticket %d | Kar=%.2f >= Hedef=%.2f (Sure: %d sn)",
                type, ticket, profit, target, elapsed);

            if (Trade.PositionClose(ticket))
            {
                Print("Pozisyon Kapatildi.");
            }
            else
            {
                Print("Hata: Kapatma basarisiz.", Trade.ResultRetcodeDescription());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Task 10: Execution Logic                                         |
//+------------------------------------------------------------------+
void ExecuteTrades(int direction)
{
    // 1. Spread Filter (Optional)
    if (InpMaxSpreadPoints > 0)
    {
        long spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
        if (spread > InpMaxSpreadPoints)
        {
            PrintFormat("Spread Filtresi: Engellendi (%d > %.0f).", spread, InpMaxSpreadPoints);
            return;
        }
    }

    // 2. Determine Trade Count
    // Need fresh rates for Body calc
    MqlRates rates[];
    if (!GetRates(Symbol(), Period(), InpTrendPeriod + 1, rates)) return;

    int count = GetTradeCount(rates, InpTrendPeriod);

    // 3. Execute Loop
    PrintFormat("Emir Gonderiliyor... Hedef: %d Adet", count);

    int opened = 0;
    for(int i=0; i<count; i++)
    {
        bool res = false;

        // No SL/TP initially (Dynamic Exit will handle it)
        if (direction == 1) // BUY
            res = Trade.Buy(InpLotSize, Symbol(), 0, 0, 0, InpComment);
        else if (direction == -1) // SELL
            res = Trade.Sell(InpLotSize, Symbol(), 0, 0, 0, InpComment);

        if (res)
        {
            opened++;
        }
        else
        {
            PrintFormat("Emir Hatasi: %d - %s", Trade.ResultRetcode(), Trade.ResultRetcodeDescription());
        }
    }

    PrintFormat("Tamamlandi. Acilan: %d/%d", opened, count);
}

//+------------------------------------------------------------------+
//| Task 7: Reversal Check                                           |
//+------------------------------------------------------------------+
bool CheckReversal(const MqlRates &rates[], int direction)
{
   // rates[1] is the last closed candle (the signal candle)
   // rates[2] is the one before it

   // BUY Signal: Look for "Bearish -> Bullish" turn
   if (direction == 1)
   {
       bool prevBearish = (rates[2].close < rates[2].open); // Red
       bool currBullish = (rates[1].close > rates[1].open); // Green

       if (prevBearish && currBullish) return true;
   }

   // SELL Signal: Look for "Bullish -> Bearish" turn
   if (direction == -1)
   {
       bool prevBullish = (rates[2].close > rates[2].open); // Green
       bool currBearish = (rates[1].close < rates[1].open); // Red

       if (prevBullish && currBearish) return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Task 6: Trend Confirmation (Body Sum)                            |
//+------------------------------------------------------------------+
bool CheckTrend(const MqlRates &rates[], int count, int direction, double &outBodySum)
{
   outBodySum = 0.0;
   // Sum body (Close - Open) of last 'count' closed candles (index 1 to count)
   // Array is series: 0=current, 1=last closed

   for(int i=1; i<=count; i++)
   {
       if (i >= ArraySize(rates)) break;
       outBodySum += (rates[i].close - rates[i].open);
   }

   // Logic:
   // If BUY allowed (Dip Buy), we want overall Uptrend (Positive BodySum)
   if (direction == 1 && outBodySum > 0) return true;

   // If SELL allowed (Rally Sell), we want overall Downtrend (Negative BodySum)
   if (direction == -1 && outBodySum < 0) return true;

   return false;
}

//+------------------------------------------------------------------+
//| Task 5: Get MA Value                                             |
//+------------------------------------------------------------------+
double GetMA()
{
   if (ExtHandleMA == INVALID_HANDLE) return -1.0;

   double buf[1];
   int attempts = 3;
   for(int i=0; i<attempts; i++)
   {
       if (CopyBuffer(ExtHandleMA, 0, 0, 1, buf) == 1)
           return buf[0];

       int err = GetLastError();
       // 4806/4807 = Data not ready
       PrintFormat("MA verisi hazirlaniyor. Deneme %d...", i+1);
       Sleep(50);
   }

   Print("Hata: MA Verisi Okunamadi!");
   return -1.0;
}

//+------------------------------------------------------------------+
//| Task 4: Sunday Gate (Time Filter)                                |
//+------------------------------------------------------------------+
bool CheckGate()
{
   if (!InpEnableSundayGate) return true; // Gate disabled -> Always open

   MqlDateTime dt;
   TimeCurrent(dt);

   // Calculate absolute minutes from Sunday 00:00
   long currentMinutes = dt.day_of_week * 1440 + dt.hour * 60 + dt.min;
   long gateMinutes    = InpGateDay * 1440 + InpGateHour * 60 + InpGateMinute;

   // Logic: If current time is BEFORE the Gate time, block trade
   if (currentMinutes < gateMinutes)
   {
      // Log only once per new bar or significant change to avoid spam (handled in OnTick)
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization handler                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    // Seed random generator
    MathSrand(GetTickCount());

    // Initialize Trade Object
    Trade.SetExpertMagicNumber(InpMagicNumber);
    Trade.SetDeviationInPoints(5); // Default deviation

    // Task 5: Initialize MA Handle (H1, SMA, Close)
    ExtHandleMA = iMA(Symbol(), PERIOD_H1, InpMAHours, 0, MODE_SMA, PRICE_CLOSE);
    if (ExtHandleMA == INVALID_HANDLE)
    {
        PrintFormat("Hata: MA Indicator olusturulamadi (Hata: %d)", GetLastError());
        return(INIT_FAILED);
    }

    // Task 9: Initialize ATR Handle (Current, 14) for Volatility
    ExtHandleATR = iATR(Symbol(), PERIOD_CURRENT, 14);
    if (ExtHandleATR == INVALID_HANDLE)
    {
        PrintFormat("Hata: ATR Indicator olusturulamadi (Hata: %d)", GetLastError());
        return(INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization handler                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Cleanup if necessary
}

//+------------------------------------------------------------------+
//| Expert tick handler                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // 1. Check New Bar
    if (IsNewBar())
    {
        Print("--- YENI MUM (NEW BAR) ---");

        // 2. Check Gate
        bool gateOpen = CheckGate();
        if (!gateOpen)
        {
             PrintFormat("Piyasa Kapali (Gate). Beklenen: Gun %d Saat %02d:%02d",
                 InpGateDay, InpGateHour, InpGateMinute);
             return; // Stop processing for this bar
        }
        else
        {
             Print("Piyasa Acik (Gate Open).");
        }

        // 3. Get Rates
        MqlRates rates[];
        if (!GetRates(Symbol(), Period(), InpTrendPeriod + 5, rates))
        {
             Print("Veri Okuma Hatasi (Rates). Islem iptal.");
             return;
        }
        Print("Veri Okuma Basarili.");

        // 4. MA Filter (Direction)
        double maValue = GetMA();
        if (maValue < 0) return; // Error handled inside GetMA

        double currentPrice = rates[0].close;
        int allowedDirection = 0; // 0=None, 1=Buy, -1=Sell

        if (currentPrice < maValue) allowedDirection = 1;      // Below MA -> Look for BUY
        else if (currentPrice > maValue) allowedDirection = -1; // Above MA -> Look for SELL

        string dirStr = (allowedDirection == 1) ? "Sadece BUY" : ((allowedDirection == -1) ? "Sadece SELL" : "YON YOK");
        PrintFormat("Yon Filtresi: Fiyat=%.5f MA=%.5f -> %s", currentPrice, maValue, dirStr);

        if (allowedDirection == 0) return;

        // 5. Trend Confirmation
        double bodySum = 0;
        bool trendPass = CheckTrend(rates, InpTrendPeriod, allowedDirection, bodySum);

        PrintFormat("Trend Teyidi: %s (BodySum: %.5f)", trendPass ? "BASARILI" : "BASARISIZ", bodySum);

        if (!trendPass) return;

        // 6. Reversal Detection
        if (CheckReversal(rates, allowedDirection))
        {
            PrintFormat("REVERSAL Sinyali Tespit Edildi: %s", (allowedDirection == 1) ? "BUY" : "SELL");

            // Task 8: Set Pending Logic
            ExtPendingState = (allowedDirection == 1) ? PENDING_BUY : PENDING_SELL;
            ExtPendingSince = TimeCurrent();
            ExtPendingDelay = (int)(MathRand() % (InpDelaySeconds + 1));

            PrintFormat("Bekleyen Emir Tetiklendi: %s. Gecikme: %d sn.",
                (ExtPendingState == PENDING_BUY) ? "BUY" : "SELL", ExtPendingDelay);
        }
    }

    // Task 8: Execute Pending
    if (ExtPendingState != PENDING_NONE)
    {
        long elapsed = TimeCurrent() - ExtPendingSince;
        if (elapsed >= ExtPendingDelay)
        {
             PrintFormat("Gecikme doldu (%d sn). Islem baslatiliyor...", elapsed);

             // Execute Trades
             int dir = (ExtPendingState == PENDING_BUY) ? 1 : -1;
             ExecuteTrades(dir);

             ExtPendingState = PENDING_NONE; // Reset
        }
    }

    // Task 11: Dynamic Exits (Run every tick)
    CheckExits();
}
