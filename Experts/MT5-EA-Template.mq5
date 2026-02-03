//-PROPERTIES-//
// Properties help the software look better when you load it in MT5.
// They provide more information and details
// This is what you see in the About tab when you attach the expert advisor to a chart.
#property link          "https://www.earnforex.com/metatrader-expert-advisors/mt5-ea-template/"
#property version       "1.01"
#property copyright     "EarnForex.com - 2025"
#property description   "A basic expert advisor template for MT5."
#property description   ""
#property description   "WARNING: There is no guarantee that this expert advisor will work as intended. Use at your own risk."
#property description   ""
#property description   "Find more on www.EarnForex.com"
#property description   "Recommended Timeframe: M5"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

//-INCLUDES-//
// '#include' allows to import code from other files.
// In the following instance the file has to be placed in the MQL5\Include folder.
#include <Trade\Trade.mqh> // This file is required to easily manage orders and positions.
#include <MQLTA ErrorHandling.mqh> // This file contains useful descriptions for errors.
#include <MQLTA Utils.mqh> // This file contains some useful functions.

//-COMMENTS-//
// This is a single line comment and you can do it by placing // at the start of the comment, this text is ignored when compiling.

/*
This is a multi-line comment.
It starts with /* and it finishes with the * and / like below
*/

enum ENUM_RISK_BASE
{
    RISK_BASE_EQUITY = 1,     // EQUITY
    RISK_BASE_BALANCE = 2,    // BALANCE
    RISK_BASE_FREEMARGIN = 3, // FREE MARGIN
};

enum ENUM_RISK_DEFAULT_SIZE
{
    RISK_DEFAULT_FIXED = 1,   // FIXED SIZE
    RISK_DEFAULT_AUTO = 2,    // AUTOMATIC SIZE BASED ON RISK
};

enum ENUM_MODE_SL
{
    SL_FIXED = 0,             // FIXED STOP LOSS
    SL_AUTO = 1,              // AUTOMATIC STOP LOSS
};

enum ENUM_MODE_TP
{
    TP_FIXED = 0,             // FIXED TAKE PROFIT
    TP_AUTO = 1,              // AUTOMATIC TAKE PROFIT
};

// EA Parameters
input group "Strategy Settings"
input double InpLotSize = 0.01;        // Lot Size
input int InpMAHours = 7;              // Moving Average Hours (7)
input int InpTrendPeriod = 25;         // Trend Confirmation Candles (25)
input int InpDelaySeconds = 20;        // Max Entry Delay (Seconds)
input double InpMinProfit = 10.0;      // Minimum Profit (Slow Target)
input double InpMaxProfit = 50.0;      // Maximum Profit (Fast Target)
input int InpMinTrades = 2;            // Min Trades per Signal
input int InpMaxTrades = 7;            // Max Trades per Signal
input int InpMomentumTime = 60;        // Momentum Time Threshold (Seconds)
input double InpMaxSpreadPoints = 0;   // Max Spread (Points, 0=Disabled)

input group "Time Settings"
input bool InpEnableSundayGate = false; // Enable Start Gate
input int InpGateHour = 5;             // Gate Hour (e.g. 05:00)
input int InpGateMinute = 0;           // Gate Minute
input int InpGateDay = 1;              // Gate Day (0=Sun, 1=Mon, etc. - Default Mon)

input group "EA Settings"
input long InpMagicNumber = 20240101;  // Magic Number
input string InpComment = "JulesEA";   // Order Comment

// Existing Inputs (Kept for compatibility where needed or commented out if replaced)
// input double LotSize = 0.01; // Replaced by InpLotSize
// input int MA_Period = 50;    // Replaced
// input long MagicNumber = ... // Replaced by InpMagicNumber

// Trading Hours (Legacy - can be removed or kept)
input bool UseTradingHours = false;
input ENUM_HOUR TradingHourStart = h07;
input ENUM_HOUR TradingHourEnd = h19;

// ATR Settings (Legacy - needed for Utils/Handlers)
input int ATRPeriod = 100;
input ENUM_TIMEFRAMES ATRTimeFrame = PERIOD_CURRENT;
input double ATRMultiplierSL = 2;
input double ATRMultiplierTP = 3;

// Risk Management (Legacy)
input ENUM_RISK_DEFAULT_SIZE RiskDefaultSize = RISK_DEFAULT_FIXED;
input double DefaultLotSize = 0.01;
input ENUM_RISK_BASE RiskBase = RISK_BASE_BALANCE;
input int MaxRiskPerTrade = 2;
input double MinLotSize = 0.01;
input double MaxLotSize = 100;
input int MaxPositions = 10; // Increased default

// SL/TP (Legacy)
input ENUM_MODE_SL StopLossMode = SL_FIXED;
input int DefaultStopLoss = 0;
input int MinStopLoss = 0;
input int MaxStopLoss = 5000;
input ENUM_MODE_TP TakeProfitMode = TP_FIXED;
input int DefaultTakeProfit = 0;
input int MinTakeProfit = 0;
input int MaxTakeProfit = 5000;

// Partial Close (Legacy)
input bool UsePartialClose = false;
input double PartialClosePerc = 50;
input double ATRMultiplierPC = 1;

// Additional (Legacy)
input int Slippage = 5;


// Global Variables
CTrade Trade; // Trade object.
int ATRHandle; // Indicator handle for ATR.
int IndicatorHandle = -1; // Global indicator handle for the EA's main signal indicator.
double ATR_current, ATR_previous; // ATR values.
double Indicator_current, Indicator_previous; // Indicator values.

// Backward Compatibility Mappings (Temporary until refactor)
double LotSize = InpLotSize;
long MagicNumber = InpMagicNumber;
int MA_Period = 14;
int DelayMinutes = 0;
int MaxOpenTrades = InpMaxTrades;
double TakeProfitUSD = InpMinProfit;
string OrderNote = InpComment;
int MaxSpread = (int)InpMaxSpreadPoints;

enum PendingSignal { PENDING_NONE, PENDING_BUY, PENDING_SELL };
PendingSignal pending = PENDING_NONE;
datetime pendingSince = 0;
int pendingDelay = 0;

// Here go all the event handling functions. They all run on specific events generated for the expert advisor.
// All event handlers are optional and can be removed if you don't need to process that specific event.

//+-------------------------------------------------------------------+
//| Expert initialization handler                                     |
//| Here goes the code that runs just once each time you load the EA. |
//+-------------------------------------------------------------------+
int OnInit()
{
    MathSrand(GetTickCount()); // Seed random number generator
    // EventSetTimer(60); // Starting a 60-second timer.
    // EventSetMillisecondTimer(500); // Starting a 500-millisecond timer.

    if (!Prechecks()) // Check if everything is OK with input parameters.
    {
        return INIT_FAILED; // Don't initialize the EA if checks fail.
    }

    if (!InitializeHandles()) // Initialize indicator handles.
    {
        PrintFormat("Error initializing indicator handles - %s - %d", GetLastErrorText(GetLastError()), GetLastError());
        return INIT_FAILED;
    }

    SetTradeObject();

    return INIT_SUCCEEDED; // Successful initialization.
}

//+---------------------------------------------------------------------+
//| Expert deinitialization handler                                     |
//| Here goes the code that runs just once each time you unload the EA. |
//+---------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Normally, there isn't much stuff you need to do on deinitialization.
}

//+------------------------------------------------------------------+
//| Expert tick handler                                              |
//| Here goes the code that runs every tick.                         |
//+------------------------------------------------------------------+
void OnTick()
{
    ProcessTick(); // Calling the EA's main processing function here. It's defined farther below.
}

//+------------------------------------------------------------------+
//| Timer event handler                                              |
//| Here goes the code that runs on timer.                           |
//+------------------------------------------------------------------+
void OnTimer()
{
    // For example, you can update a display timer here if you have one in your EA.
}

//+------------------------------------------------------------------------------+
//| Trade event handler                                                          |
//| Here goes the code that runs each time something related to trading happens. |
//+------------------------------------------------------------------------------+
void OnTrade()
{
    // For example, if you want to do something when a pending order gets triggered, you can do it here without overloading the OnTick() handler too much.
}

//+--------------------------------------------------------------------------------+
//| Backtest end handler                                                           |
//| Here goes the code that runs each time a backtest in Strategy Tester finishes. |
//| The goal is to calculate the value of a custom optimization criterion.         |
//+--------------------------------------------------------------------------------+
double OnTester()
{
    double NetProfit = TesterStatistics(STAT_PROFIT);
    double InitialDeposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
    double MaxDrawDownPerc = TesterStatistics(STAT_EQUITYDD_PERCENT);
    double TotalTrades = TesterStatistics(STAT_TRADES);
    if (InitialDeposit == 0) return 0; // Avoiding division by zero.
    if (TotalTrades == 0) return -100; // Discard a backtest with zero trades.
    if ((TotalTrades > 0) && (MaxDrawDownPerc == 0)) MaxDrawDownPerc = 0.01; // Avoiding division by zero.

    double NetProfitPerc = NetProfit / InitialDeposit * 100;

    double Max = 0;
    if (NetProfitPerc > 0) Max = NetProfitPerc / MaxDrawDownPerc; // Adjust net profit by maximum drawdown.
    if (NetProfitPerc < 0) Max = NetProfitPerc;

    return Max; // Return the value as a custom optimization criterion.
}


// Here go all custom functions. They all are called either from the above-defined event handlers or from other custom functions.

// Helper to get rates safely with retry
bool GetRates(string symbol, ENUM_TIMEFRAMES timeframe, int count, MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);

   for (int attempt = 0; attempt < 5; attempt++) // Retry loop
   {
       int copied = CopyRates(symbol, timeframe, 0, count, rates);
       if (copied == count) return true;

       if (GetLastError() == 4401) // History not found/not ready
       {
           PrintFormat("History not ready (%s, %d). Attempt %d...", symbol, timeframe, attempt + 1);
           Sleep(100);
           continue;
       }

       PrintFormat("Error CopyRates (%d/%d): %d", copied, count, GetLastError());
       return false;
   }

   return false;
}

// Task 4: Time Filter (Start Gate)
bool CheckGate()
{
   if (!InpEnableSundayGate) return true;

   MqlDateTime dt;
   TimeCurrent(dt);

   // Calculate minutes from start of the week (Sunday 00:00)
   long currentMinutes = dt.day_of_week * 1440 + dt.hour * 60 + dt.min;
   long gateMinutes = InpGateDay * 1440 + InpGateHour * 60 + InpGateMinute;

   if (currentMinutes < gateMinutes)
   {
       // Gate Closed
       PrintFormat("GATE CLOSED until Mon 05:00 (Config: Day %d %02d:%02d)",
           InpGateDay, InpGateHour, InpGateMinute);
       return false;
   }

   // Gate Open
   return true;
}

// Task 5: Get MA Value with retry
double GetMA()
{
    double buf[1];
    for (int attempt = 0; attempt < 3; attempt++)
    {
        if (CopyBuffer(IndicatorHandle, 0, 0, 1, buf) == 1) return buf[0];
        if (GetLastError() == 4806 || GetLastError() == 4807) // No data yet
        {
             Sleep(50);
             continue;
        }
        break;
    }

    PrintFormat("Error getting MA: %d", GetLastError());
    return -1.0; // Return error code
}

// Helper: Get ATR Value Robustly
double GetATR()
{
    double buf[1];
    if (CopyBuffer(ATRHandle, 0, 0, 1, buf) != 1) return -1.0;
    return buf[0];
}

// Entry and exit processing
void ProcessTick()
{
    // Check for New Bar
    if (IsNewBar())
    {
        Print("NEW BAR: ", TimeToString(TimeCurrent()));

        // Task 3: Rates Verification (Need Rates for subsequent steps)
        MqlRates rates[];
        if (!GetRates(Symbol(), Period(), InpTrendPeriod + 5, rates)) return;

        // Task 4: Gate Check
        bool gateOpen = CheckGate();
        if (gateOpen) Print("GATE OPENED");

        // Task 5: MA Filter
        double maValue = GetMA();
        if (maValue < 0.0) // Check for error code
        {
            Print("Error: MA Calculation Failed. Skipping signal.");
            return;
        }

        double price = rates[0].close;
        int allowedDir = 0; // 0=None, 1=Buy, -1=Sell

        if (price < maValue) allowedDir = 1;
        else if (price > maValue) allowedDir = -1;

        // Task 6: Trend Confirmation (Body Sum of last InpTrendPeriod closed candles)
        double bodySum = 0;
        for (int i = 1; i <= InpTrendPeriod; i++)
        {
            if (i < ArraySize(rates))
               bodySum += (rates[i].close - rates[i].open);
        }

        bool trendPass = false;
        if (allowedDir == 1 && bodySum > 0) trendPass = true;
        if (allowedDir == -1 && bodySum < 0) trendPass = true;

        PrintFormat("Filter Summary: Gate=%s | Price=%.5f MA=%.5f | Dir=%d | BodySum=%.5f Trend=%s",
            gateOpen ? "OPEN" : "CLOSED", price, maValue, allowedDir, bodySum, trendPass ? "PASS" : "FAIL");

        // Task 7: Reversal Candle Detection
        if (gateOpen && trendPass)
        {
            PendingSignal newPending = PENDING_NONE;

            // Buy Signal: Dip Buy (Price < MA) -> Trend Up (BodySum > 0) -> Turn (Bearish then Bullish)
            if (allowedDir == 1)
            {
                // Check if Candle 1 is Bullish and Candle 2 was Bearish
                if (rates[1].close > rates[1].open && rates[2].close < rates[2].open)
                {
                    newPending = PENDING_BUY;
                }
            }
            // Sell Signal: Rally Sell (Price > MA) -> Trend Down (BodySum < 0) -> Turn (Bullish then Bearish)
            else if (allowedDir == -1)
            {
                 if (rates[1].close < rates[1].open && rates[2].close > rates[2].open)
                 {
                     newPending = PENDING_SELL;
                 }
            }

            if (newPending != PENDING_NONE)
            {
                if (pending != PENDING_NONE)
                {
                    PrintFormat("WARNING: Pending Signal OVERWRITE! Old: %d New: %d", pending, newPending);
                }

                pending = newPending;
                pendingSince = TimeCurrent();
                pendingDelay = (int)(MathRand() % (InpDelaySeconds + 1));
                PrintFormat("SIGNAL: %s Reversal Detected. Pending in %d sec.",
                    pending == PENDING_BUY ? "BUY" : "SELL", pendingDelay);
            }
        }
    }

    // Task 8: Process Pending Execution
    if (pending != PENDING_NONE)
    {
        long elapsed = TimeCurrent() - pendingSince;
        if (elapsed >= pendingDelay)
        {
            PrintFormat("Pending Delay (%d sec) elapsed. Executing Trade...", pendingDelay);
            ExecuteTrades();
            pending = PENDING_NONE;
        }
    }

    // Existing Management Logic (To be refactored later)
    if (CountPositions())
    {
        CheckExitSignal();
    }
}

// Task 9/10: Execution Logic
void ExecuteTrades()
{
    // Task 12: Spread Filter
    if (InpMaxSpreadPoints > 0)
    {
        long spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
        if (spread > InpMaxSpreadPoints)
        {
            PrintFormat("Execution Blocked by Spread: %d > %.0f", spread, InpMaxSpreadPoints);
            return;
        }
    }

    // Recalculate BodySum (Trend Strength)
    MqlRates rates[];
    if (!GetRates(Symbol(), Period(), InpTrendPeriod + 1, rates)) return;

    double bodySum = 0;
    for (int i = 1; i <= InpTrendPeriod; i++)
    {
         if (i < ArraySize(rates))
             bodySum += (rates[i].close - rates[i].open);
    }

    double avgBody = MathAbs(bodySum) / InpTrendPeriod;

    // Task 18: Robust ATR Usage
    double atr = GetATR(); // Use the robust helper
    if (atr <= 0.0)
    {
        PrintFormat("Error: Invalid ATR (%.5f) for volatility calculation. Skipping trade.", atr);
        return; // Fail-safe: Do not trade without valid volatility data
    }

    double score = avgBody / atr;

    // Map Score (e.g. 0.2 to 1.0) to Trades
    double minScore = 0.2;
    double maxScore = 1.0;

    double factor = (score - minScore) / (maxScore - minScore);
    if (factor < 0) factor = 0;
    if (factor > 1) factor = 1;

    int tradeCount = (int)(InpMinTrades + factor * (InpMaxTrades - InpMinTrades));

    PrintFormat("[TRADE_CALC] BodySum=%.5f Avg=%.5f ATR=%.5f Score=%.2f -> Trades: %d",
        bodySum, avgBody, atr, score, tradeCount);

    // Execute Loop
    int currentOpen = CountPositions();
    int limit = MaxPositions; // Global limit

    int opened = 0;
    for (int i = 0; i < tradeCount; i++)
    {
        if (currentOpen + opened >= limit)
        {
            Print("Max Global Positions reached. Stopping batch.");
            break;
        }

        bool res = false;
        // SL and TP set to 0 (Unset) as per strategy design "Approach A".
        if (pending == PENDING_BUY)
             res = Trade.Buy(InpLotSize, Symbol(), 0, 0, 0, InpComment);
        else if (pending == PENDING_SELL)
             res = Trade.Sell(InpLotSize, Symbol(), 0, 0, 0, InpComment);

        if (res) opened++;
        else Print("Order failed: ", Trade.ResultRetcodeDescription());
    }
    PrintFormat("Batch Finished. Opened %d/%d trades.", opened, tradeCount);
}

int CountPositions()
{
    int count = 0;
    int TotalPositions = PositionsTotal();
    for (int i = 0; i < TotalPositions; i++)
    {
        string Instrument = PositionGetSymbol(i);
        if (Instrument == "")
        {
            PrintFormat(__FUNCTION__, ": ERROR - Unable to select the position - %s - %d.", GetLastErrorText(GetLastError()), GetLastError());
        }
        else
        {
            // Skip positions in other symbols.
            if (Instrument != Symbol()) continue;
            // Skip counting positions with a different Magic number if the EA has non-zero Magic number set.
            if ((MagicNumber != 0) && (PositionGetInteger(POSITION_MAGIC) != MagicNumber)) continue;
            count++;
        }
    }
    return count;
}

// Initialize handles. Indicator handles have to be initialized at the beginning of the EA's operation.
bool InitializeHandles()
{
    // Indicator handle is the main handle for the signal generating indicator.
    // Task 5: 7-Hour MA Filter (H1 Timeframe, InpMAHours period)
    IndicatorHandle = iMA(Symbol(), PERIOD_H1, InpMAHours, 0, MODE_SMA, PRICE_CLOSE);
    if (IndicatorHandle == INVALID_HANDLE)
    {
        PrintFormat("Unable to create main indicator handle - %s - %d.", GetLastErrorText(GetLastError()), GetLastError());
        return false;
    }
    // ATR handle for stop-loss and take-profit.
    if ((StopLossMode == SL_AUTO) || (TakeProfitMode == TP_AUTO) || (UsePartialClose)) // Only initialize ATR handles when ATR is used.
    {
        ATRHandle = iATR(Symbol(), ATRTimeFrame, ATRPeriod);
        if (ATRHandle == INVALID_HANDLE)
        {
            PrintFormat("Unable to create ATR handle - %s - %d.", GetLastErrorText(GetLastError()), GetLastError());
            return false;
        }
    }
    return true;
}

// Trading functions

// Set the basic parameters of the Trade object.
void SetTradeObject()
{
    // All future trade operations will take into account these parameters - Magic number and deviation/slippage.
    Trade.SetExpertMagicNumber(MagicNumber);
    Trade.SetDeviationInPoints(Slippage);
}

// Open a position with a buy order.
bool OpenBuy()
{
    double Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double OpenPrice = Ask; // Buy at Ask.
    double StopLossPrice = StopLoss(ORDER_TYPE_BUY, OpenPrice); // Calculate SL based on direction, price, and SL rules.
    double TakeProfitPrice = TakeProfit(ORDER_TYPE_BUY, OpenPrice); // Calculate TP based on direction, price, and TP rules.
    double Size = LotSize(StopLossPrice, OpenPrice); // Calculate position size based on the SL, price, and the given rules.
    // Adjust for tick size granularity.
    double TickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    if (TickSize > 0)
    {
        StopLossPrice = NormalizeDouble(MathRound(StopLossPrice / TickSize) * TickSize, Digits());
        TakeProfitPrice = NormalizeDouble(MathRound(TakeProfitPrice / TickSize) * TickSize, Digits());
    }
    // Use the standard Trade object to open the position with calculated parameters.
    if (!Trade.Buy(Size, Symbol(), OpenPrice, StopLossPrice, TakeProfitPrice, OrderNote))
    {
        PrintFormat("Unable to open BUY: %s - %d", Trade.ResultRetcodeDescription(), Trade.ResultRetcode());
        return false;
    }
    return true;
}

// Open a position with a sell order.
bool OpenSell()
{
    double Ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double Bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double OpenPrice = Bid; // Sell at Bid.
    double StopLossPrice = StopLoss(ORDER_TYPE_SELL, OpenPrice); // Calculate SL based on direction, price, and SL rules.
    double TakeProfitPrice = TakeProfit(ORDER_TYPE_SELL, OpenPrice); // Calculate TP based on direction, price, and TP rules.
    double Size = LotSize(StopLossPrice, OpenPrice); // Calculate position size based on the SL, price, and the given rules.
    // Adjust for tick size granularity.
    double TickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    if (TickSize > 0)
    {
        StopLossPrice = NormalizeDouble(MathRound(StopLossPrice / TickSize) * TickSize, Digits());
        TakeProfitPrice = NormalizeDouble(MathRound(TakeProfitPrice / TickSize) * TickSize, Digits());
    }
    // Use the standard Trade object to open the position with calculated parameters.
    if (!Trade.Sell(Size, Symbol(), OpenPrice, StopLossPrice, TakeProfitPrice, OrderNote))
    {
        PrintFormat("Unable to open SELL: %s - %d", Trade.ResultRetcodeDescription(), Trade.ResultRetcode());
        return false;
    }
    return true;
}

// Close the specified position completely.
//!! Unused. Can be uncommented and used to close specific positions.
/* bool ClosePosition(ulong ticket)
{
    if (!Trade.PositionClose(ticket))
    {
        PrintFormat(__FUNCTION__, ": ERROR - Unable to close position: %s - %d", Trade.ResultRetcodeDescription(), Trade.ResultRetcode());
        return false;
    }
    return true;
}*/

void CloseAllSell()
{
    int total = PositionsTotal();

    // Start a loop to scan all the positions.
    // The loop starts from the last, otherwise it could skip positions.
    for (int i = total - 1; i >= 0; i--)
    {
        // If the position cannot be selected log an error.
        if (PositionGetSymbol(i) == "")
        {
            PrintFormat(__FUNCTION__, ": ERROR - Unable to select the position - %s - %d.", GetLastErrorText(GetLastError()), GetLastError());
            continue;
        }
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue; // Only close current symbol trades.
        if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue; // Only close Sell positions.
        if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue; // Only close own positions.

        for (int try = 0; try < 10; try++)
        {
            bool result = Trade.PositionClose(PositionGetInteger(POSITION_TICKET));
            if (!result)
            {
                PrintFormat(__FUNCTION__, ": ERROR - Unable to close position: %s - %d", Trade.ResultRetcodeDescription(), Trade.ResultRetcode());
            }
            else break;
        }
    }
}

void CloseAllBuy()
{
    int total = PositionsTotal();

    // Start a loop to scan all the positions.
    // The loop starts from the last, otherwise it could skip positions.
    for (int i = total - 1; i >= 0; i--)
    {
        // If the position cannot be selected log an error.
        if (PositionGetSymbol(i) == "")
        {
            PrintFormat(__FUNCTION__, ": ERROR - Unable to select the position - %s - %d.", GetLastErrorText(GetLastError()), GetLastError());
            continue;
        }
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue; // Only close current symbol trades.
        if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue; // Only close Buy positions.
        if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue; // Only close own positions.

        for (int try = 0; try < 10; try++)
        {
            bool result = Trade.PositionClose(PositionGetInteger(POSITION_TICKET));
            if (!result)
            {
                PrintFormat(__FUNCTION__, ": ERROR - Unable to close position: %s - %d", Trade.ResultRetcodeDescription(), Trade.ResultRetcode());
            }
            else break;
        }
    }
}

// Close all positions opened by this EA.
void CloseAllPositions()
{
    int total = PositionsTotal();

    // Start a loop to scan all the positions.
    // The loop starts from the last, otherwise it could skip positions.
    for (int i = total - 1; i >= 0; i--)
    {
        // If the position cannot be selected log an error.
        if (PositionGetSymbol(i) == "")
        {
            PrintFormat(__FUNCTION__, ": ERROR - Unable to select the position - %s - %d.", GetLastErrorText(GetLastError()), GetLastError());
            continue;
        }
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue; // Only close current symbol trades.
        if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue; // Only close own positions.

        for (int try = 0; try < 10; try++)
        {
            bool result = Trade.PositionClose(PositionGetInteger(POSITION_TICKET));
            if (!result)
            {
                PrintFormat(__FUNCTION__, ": ERROR - Unable to close position: %s - %d", Trade.ResultRetcodeDescription(), Trade.ResultRetcode());
            }
            else break;
        }
    }
}

// Partially close a position with a given ticket.
bool PartialClose(ulong ticket, double percentage)
{
    if (!PositionSelectByTicket(ticket))
    {
        PrintFormat("ERROR - Unable to select position by ticket #%d: %s - %d", ticket, GetLastErrorText(GetLastError()), GetLastError());
        return false;
    }
    double OriginalSize = PositionGetDouble(POSITION_VOLUME);
    double Size = OriginalSize * percentage / 100;
    double LotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double MaxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double MinLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    Size = MathFloor(Size / LotStep) * LotStep;
    if (Size < MinLot) return false;
    if (!Trade.PositionClosePartial(ticket, Size))
    {
        PrintFormat("ERROR - Unable to partially close position #%d: %s - %d", ticket, Trade.ResultRetcodeDescription(), Trade.ResultRetcode());
        return false;
    }
    return true;
}

// Calculate a stop-loss price for an order.
double StopLoss(ENUM_ORDER_TYPE order_type, double open_price)
{
    double StopLossPrice = 0;
    if (StopLossMode == SL_FIXED) // Easy way.
    {
        if (DefaultStopLoss == 0) return 0;
        if (order_type == ORDER_TYPE_BUY)
        {
            StopLossPrice = open_price - DefaultStopLoss * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        }
        if (order_type == ORDER_TYPE_SELL)
        {
            StopLossPrice = open_price + DefaultStopLoss * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        }
    }
    else // Special cases.
    {
        StopLossPrice = DynamicStopLossPrice(order_type, open_price);
    }
    return NormalizeDouble(StopLossPrice, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
}

// Calculate the take-profit price for an order.
double TakeProfit(ENUM_ORDER_TYPE order_type, double open_price)
{
    double TakeProfitPrice = 0;
    if (TakeProfitMode == TP_FIXED) // Easy way.
    {
        if (DefaultTakeProfit == 0) return 0;
        if (order_type == ORDER_TYPE_BUY)
        {
            TakeProfitPrice = open_price + DefaultTakeProfit * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        }
        if (order_type == ORDER_TYPE_SELL)
        {
            TakeProfitPrice = open_price - DefaultTakeProfit * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        }
    }
    else // Special cases.
    {
        TakeProfitPrice = DynamicTakeProfitPrice(order_type, open_price);
    }
    return NormalizeDouble(TakeProfitPrice, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
}

// Calculate the position size for an order.
double LotSize(double stop_loss, double open_price)
{
    double Size = DefaultLotSize;
    if (RiskDefaultSize == RISK_DEFAULT_AUTO) // If the position size is dynamic.
    {
        if (stop_loss != 0) // Calculate position size only if SL is non-zero, otherwise there will be a division by zero error.
        {
            double RiskBaseAmount = 0;
            // TickValue is the value of the individual price increment for 1 lot of the instrument expressed in the account currency.
            double TickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
            // Define the base for the risk calculation depending on the parameter chosen
            if (RiskBase == RISK_BASE_BALANCE) RiskBaseAmount = AccountBalance();
            else if (RiskBase == RISK_BASE_EQUITY) RiskBaseAmount = AccountEquity();
            else if (RiskBase == RISK_BASE_FREEMARGIN) RiskBaseAmount = AccountFreeMargin();
            double SL = MathAbs(open_price - stop_loss) / SymbolInfoDouble(Symbol(), SYMBOL_POINT); // SL as a number of points.
            // Calculate the Position Size.
            Size = (RiskBaseAmount * MaxRiskPerTrade / 100) / (SL * TickValue);
        }
        // If the stop loss is zero, then use the default size.
        if (stop_loss == 0)
        {
            Size = DefaultLotSize;
        }
    }

    // Normalize the Lot Size to satisfy the allowed lot increment and minimum and maximum position size.
    double LotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    double MaxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double MinLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    Size = MathFloor(Size / LotStep) * LotStep;
    // Limit the lot size in case it is greater than the maximum allowed by the user.
    if (Size > MaxLotSize) Size = MaxLotSize;
    // Limit the lot size in case it is greater than the maximum allowed by the broker.
    if (Size > MaxLot) Size = MaxLot;
    // If the lot size is too small, then set it to 0 and don't trade.
    if ((Size < MinLotSize) || (Size < MinLot)) Size = 0;

    return Size;
}

// Utility functions

// Checks to run at initialization to complete it.
bool Prechecks()
{
    // An example of a check to run here.
    if (MaxLotSize < MinLotSize)
    {
        Print("MaxLotSize cannot be less than MinLotSize");
        return false;
    }
    return true;
}

// Retrieve indicator data necessary for entry, update, and exit.
// Boolean type, so it can return true if all the data is available or false if it is not.
// Other advantage of this function is to move part of repetitive code into one location to make it leaner.
bool GetIndicatorsData()
{
    double buf[2]; // Needed for CopyBuffer().
    int count; // Will store the number of array elements returned by CopyBuffer().
    bool AllDataAvailable = false;
    int MaxAttemptsForData = 5;
    int DelayBetweenAttempts = 200; // Milliseconds.
    int Attempt = 0;

    while ((!AllDataAvailable) && (Attempt < MaxAttemptsForData))
    {
        AllDataAvailable = true;

        if ((StopLossMode == SL_AUTO) || (TakeProfitMode == TP_AUTO) || (UsePartialClose)) // Only copy ATR buffers when ATR is used.
        {
            count = CopyBuffer(ATRHandle, 0, 0, 2, buf); // Copy using ATR indicator handle 2 latest values from 0th buffer to the buf array.
            if ((count < 2) || (buf[0] == NULL) || (buf[0] == EMPTY_VALUE))
            {
                Print("Unable to get ATR values.");
                AllDataAvailable = false;
            }
            else
            {
                ATR_current = buf[1];
                ATR_previous = buf[0];
            }
        }

        // This is where the main indicator data is read.
        // !! Uncomment and modify to use indicator values in your entry and exit signals
        /*count = CopyBuffer(IndicatorHandle, 0, 1, 2, buf); // Copying using main indicator handle 2 latest completed candles (hence starting from the 1st, and not 0th, candle) from 0th buffer to the buf array.
        if (count < 2)
        {
            Print("Main indicator buffer not ready yet.");
            AllDataAvailable = false;
        }
        else
        {
            Indicator_current = buf[1];
            Indicator_previous = buf[0];
        }*/

        if (AllDataAvailable) return true;

        Attempt++;
        Sleep(DelayBetweenAttempts);
    }

    if (!AllDataAvailable)
    {
        Print("Unable to get some data for the entry signal, skipping candle.");
        return false;
    }

    return true;
}

// Entry signal
void CheckEntrySignal()
{
    if ((UseTradingHours) && (!IsCurrentTimeInInterval(TradingHourStart, TradingHourEnd))) return; // Trading hours restrictions for entry.

    bool BuySignal = false;
    bool SellSignal = false;

    // Buy signal conditions

    // This is where you should insert your entry signal for BUY orders.
    // Include a condition to open a buy order, the condition will have to set BuySignal to true or false.

    //!! Uncomment and modify this buy entry signal check line:
    //if ((Indicator_current > iClose(Symbol(), Period(), 1)) && (Indicator_previous <= iClose(Symbol(), Period(), 2))) BuySignal = true; // Check if the indicator's value crossed the Close price level from below.

    if (BuySignal)
    {
        OpenBuy();
    }

    // Sell signal conditions

    // This is where you should insert your entry signal for SELL orders.
    // Include a condition to open a sell order, the condition will have to set SellSignal to true or false.

    //!! Uncomment and modify this sell entry signal check line:
    //if ((Indicator_current < iClose(Symbol(), Period(), 1)) && (Indicator_previous >= iClose(Symbol(), Period(), 2))) SellSignal = true; // Check if the indicator's value crossed the Close price level from above.

    if (SellSignal)
    {
        OpenSell();
    }
}

// Exit signal
void CheckExitSignal()
{
    int total = PositionsTotal();
    for(int i=total-1; i>=0; i--)
    {
        string symbol = PositionGetSymbol(i);
        if(symbol == Symbol() && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            long openTime = (long)PositionGetInteger(POSITION_TIME);
            long elapsed = TimeCurrent() - openTime;

            // Task 11: Dynamic Take Profit
            // If trade is young (high momentum/volatility expectation), aim for MaxProfit.
            // If trade stalls (elapsed > Time), accept MinProfit.
            double target = InpMinProfit;
            string type = "Slow/Min";

            if (elapsed < InpMomentumTime)
            {
                target = InpMaxProfit;
                type = "Fast/Max";
            }

            if(profit >= target)
            {
                ulong ticket = PositionGetInteger(POSITION_TICKET);
                PrintFormat("Dynamic TP Hit (%s): Ticket %d | Profit=%.2f >= Target=%.2f (Elapsed %d sec)",
                    type, ticket, profit, target, elapsed);

                if(Trade.PositionClose(ticket))
                {
                    Print("Position closed successfully.");
                }
                else
                {
                    Print("Position close failed: ", Trade.ResultRetcodeDescription());
                }
            }
        }
    }
}

// Dynamic stop-loss calculation
double DynamicStopLossPrice(ENUM_ORDER_TYPE type, double open_price)
{
    double atr = GetATR();
    if (atr <= 0) atr = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 100; // Fallback for SL calc only

    double StopLossPrice = 0;
    if (type == ORDER_TYPE_BUY)
    {
        StopLossPrice = open_price - atr * ATRMultiplierSL;
    }
    else if (type == ORDER_TYPE_SELL)
    {
        StopLossPrice = open_price + atr * ATRMultiplierSL;
    }
    return NormalizeDouble(StopLossPrice, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
}

// Dynamic take-profit calculation
double DynamicTakeProfitPrice(ENUM_ORDER_TYPE type, double open_price)
{
    double atr = GetATR();
    if (atr <= 0) atr = SymbolInfoDouble(Symbol(), SYMBOL_POINT) * 100;

    double TakeProfitPrice = 0;
    if (type == ORDER_TYPE_BUY)
    {
        TakeProfitPrice = open_price + atr * ATRMultiplierTP;
    }
    else if (type == ORDER_TYPE_SELL)
    {
        TakeProfitPrice = open_price - atr * ATRMultiplierTP;
    }
    return NormalizeDouble(TakeProfitPrice, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
}

// Partially close all positions opened by this EA.
void PartialCloseAll()
{
    int total = PositionsTotal();

    // Start a loop to scan all the positions.
    // The loop starts from the last, otherwise it could skip positions.
    for (int i = total - 1; i >= 0; i--)
    {
        // If the position cannot be selected log an error.
        if (PositionGetSymbol(i) == "")
        {
            Print(__FUNCTION__, ": ERROR - Unable to select the position - ", GetLastError());
            continue;
        }
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue; // Only close current symbol trades.
        if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue; // Only close own positions.

        int position_ticket = (int)PositionGetInteger(POSITION_TICKET);

        // Retrieve the history of deals and orders for that position to check if it hasn't been already partially closed.
        if (!HistorySelectByPosition(PositionGetInteger(POSITION_IDENTIFIER)))
        {
            PrintFormat("ERROR - Unable to get position history for %d - %s - %d", position_ticket, GetLastErrorText(GetLastError()), GetLastError());
            continue;
        }

        bool need_partial_close = true;

        // Process partial close for a long position.
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            for (int j = HistoryDealsTotal() - 1; j >= 0; j--)
            {
                long deal_ticket = (int)HistoryDealGetTicket(j);
                if (!deal_ticket)
                {
                    PrintFormat("Unable to get deal for %d - %s - %d", position_ticket, GetLastErrorText(GetLastError()), GetLastError());
                    break;
                }
                if (HistoryDealGetInteger(deal_ticket, DEAL_TYPE) == DEAL_TYPE_SELL) // Looks like this long position has already been partially closed at least once.
                {
                    need_partial_close = false;
                    break; // No need to partially close this position.
                }
            }
            // Condition for partial close of a long position.
            if ((need_partial_close) && (SymbolInfoDouble(Symbol(), SYMBOL_BID) - PositionGetDouble(POSITION_PRICE_OPEN) > ATR_previous * ATRMultiplierPC))
            {
                PartialClose(position_ticket, PartialClosePerc);
            }
        }
        // Process partial close for a short position.
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            for (int j = HistoryDealsTotal() - 1; j >= 0; j--)
            {
                long deal_ticket = (int)HistoryDealGetTicket(j);
                if (!deal_ticket)
                {
                    PrintFormat("Unable to get deal for %d - %s - %d", position_ticket, GetLastErrorText(GetLastError()), GetLastError());
                    return;
                }
                if (HistoryDealGetInteger(deal_ticket, DEAL_TYPE) == DEAL_TYPE_BUY) // Looks like this short position has already been partially closed at least once.
                {
                    need_partial_close = false;
                    break; // No need to partially close this position.
                }
            }
            // Condition for partial close of a short position.
            if ((need_partial_close) && (PositionGetDouble(POSITION_PRICE_OPEN) - SymbolInfoDouble(Symbol(), SYMBOL_ASK) > ATR_previous * ATRMultiplierPC))
            {
                PartialClose(position_ticket, PartialClosePerc);
            }
            return;
        }
    }
}

// Check for a new bar.
bool IsNewBar()
{
    static datetime last_time = 0;
    datetime current_time = iTime(Symbol(), Period(), 0);
    if(last_time != current_time)
    {
        last_time = current_time;
        return true;
    }
    return false;
}
//+------------------------------------------------------------------+