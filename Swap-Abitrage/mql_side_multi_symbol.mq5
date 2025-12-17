//+------------------------------------------------------------------+
//|                                      SwapArbBridge_Multi.mq5    |
//|                                  Copyright 2025, Swap Arbitrage |
//+------------------------------------------------------------------+
#property copyright "Swap Arbitrage Bridge Multi-Symbol"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

input string BROKER_ID = "BROKER_A";        // "BROKER_A" oder "BROKER_B"
input int    STATUS_INTERVAL = 30;          // Sekunden
input ulong  MAGIC = 123456;                // Unique pro Broker
input string SYMBOL_PREFIX = "";            // z.B. "" oder "EURUSD," für Filter

// Global
datetime last_status = 0;
string symbols[];  // Dynamische Symbol-Liste

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(MAGIC);
   LoadTradableSymbols();
   Print("=== SwapArbBridge Multi gestartet für ", BROKER_ID, " (", ArraySize(symbols), " Symbole) ===");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Lädt alle handelbaren Symbole (optional gefiltert)               |
//+------------------------------------------------------------------+
void LoadTradableSymbols() {
   ArrayFree(symbols);
   for(int i = SymbolsTotal(true)-1; i >= 0; i--) {
      string sym = SymbolName(i, true);
      
      // Prefix-Filter (z.B. "EURUSD,GBPUSD")
      if(StringLen(SYMBOL_PREFIX) > 0) {
         if(StringFind("," + SYMBOL_PREFIX + ",", "," + sym + ",") < 0) continue;
      }
      
      // Nur Forex Majors + CFDs mit Swaps
      if(StringFind(sym, "USD") >= 0 || StringFind(sym, "JPY") >= 0 || 
         StringFind(sym, "XAU") >= 0 || StringFind(sym, "XAG") >= 0) {
         ArrayResize(symbols, ArraySize(symbols) + 1);
         symbols[ArraySize(symbols)-1] = sym;
      }
   }
   ArraySort(symbols);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   if(TimeCurrent() - last_status >= STATUS_INTERVAL) {
      SendStatusToPython();
      last_status = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Sendet Multi-Symbol Status als JSON-Array                        |
//+------------------------------------------------------------------+
void SendStatusToPython() {
   string json_array = "[";
   
   for(int s = 0; s < ArraySize(symbols); s++) {
      string sym_status = CreateSymbolStatusJSON(symbols[s]);
      if(sym_status != "") {
         json_array += sym_status;
         if(s < ArraySize(symbols)-1) json_array += ",";
      }
   }
   json_array += "]";
   
   if(StringLen(json_array) > 2) {  // Mind. 1 Symbol
      string status_file = "SwapArb\\status_" + BROKER_ID + ".json";
      int handle = FileOpen(status_file, FILE_WRITE | FILE_TXT | FILE_COMMON);
      
      if(handle != INVALID_HANDLE) {
         FileWriteString(handle, json_array);
         FileClose(handle);
         Print("Status (", ArraySize(symbols), " Symbole) → ", status_file);
         
         ReadCommandsFromFile();
      }
   }
}

//+------------------------------------------------------------------+
//| Erstellt JSON für EIN Symbol                                     |
//+------------------------------------------------------------------+
string CreateSymbolStatusJSON(string sym) {
   double long_lots = 0, short_lots = 0;
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   // Positionen dieses Symbols zählen
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == MAGIC && 
            PositionGetString(POSITION_SYMBOL) == sym) {
            double lots = PositionGetDouble(POSITION_VOLUME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               long_lots += lots;
            else
               short_lots += lots;
         }
      }
   }
   
   // Swap Rates
   double swap_long = SymbolInfoDouble(sym, SYMBOL_SWAP_LONG);
   double swap_short = SymbolInfoDouble(sym, SYMBOL_SWAP_SHORT);
   
   if(swap_long == 0 && swap_short == 0) return "";  // Skip Symbole ohne Swaps
   
   string json = StringFormat(
      "{\"symbol\":\"%s\",\"long_lots\":%.2f,\"short_lots\":%.2f,"
      "\"free_margin\":%.0f,\"swap_long\":%.4f,\"swap_short\":%.4f}",
      sym, long_lots, short_lots, free_margin, swap_long, swap_short
   );
   
   return json;
}

//+------------------------------------------------------------------+
//| Liest Kommandos (jetzt mit Symbol)                               |
//+------------------------------------------------------------------+
void ReadCommandsFromFile() {
   string cmd_file = "SwapArb\\commands_" + BROKER_ID + ".json";
   int handle = FileOpen(cmd_file, FILE_READ | FILE_TXT | FILE_COMMON);
   
   if(handle != INVALID_HANDLE) {
      string response = FileReadString(handle);
      FileClose(handle);
      
      if(StringLen(response) > 10) {
         Print("← Commands: ", StringSubstr(response, 0, 100), "...");
         ParseAndExecuteCommands(response);  // Plural!
         
         FileDelete(cmd_file, FILE_COMMON);
         Print("✅ Commands ausgeführt");
      }
   }
}

//+------------------------------------------------------------------+
//| Parst Array von Commands (Multi-Symbol)                          |
//+------------------------------------------------------------------+
void ParseAndExecuteCommands(string response) {
   // Einfaches Array-Parsing: [{"symbol":"EURUSD","cmd":"open",...}, {...}]
   int cmd_count = 0;
   
   while(StringLen(response) > 0) {
      int start = StringFind(response, "{\"symbol\":");
      if(start < 0) break;
      
      int end = StringFind(response, "}", start);
      if(end < 0) break;
      
      string single_cmd = StringSubstr(response, start, end - start + 1);
      ExecuteSingleCommand(single_cmd);
      cmd_count++;
      
      response = StringSubstr(response, end + 1);
   }
   
   Print("✅ ", cmd_count, " Commands ausgeführt");
}

//+------------------------------------------------------------------+
//| Führt einzelnes Command für Symbol aus                           |
//+------------------------------------------------------------------+
void ExecuteSingleCommand(string cmd) {
   string sym = ExtractString(cmd, "\"symbol\":\"", "\"");
   if(sym == "") return;
   
   if(StringFind(cmd, "\"cmd\":\"open\"") >= 0) {
      ENUM_ORDER_TYPE type = (StringFind(cmd, "\"type\":\"buy\"") >= 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double lots = ExtractDouble(cmd, "\"lots\":");
      
      if(lots > 0) {
         if(type == ORDER_TYPE_BUY) {
            if(trade.Buy(lots, sym, 0, 0, 0, "SwapArb")) Print("✅ BUY ", lots, " ", sym);
         } else {
            if(trade.Sell(lots, sym, 0, 0, 0, "SwapArb")) Print("✅ SELL ", lots, " ", sym);
         }
      }
   }
   
   if(StringFind(cmd, "\"cmd\":\"close\"") >= 0) {
      CloseSymbolPositions(sym);
   }
}

//+------------------------------------------------------------------+
//| Schließt Positionen eines Symbols                                |
//+------------------------------------------------------------------+
void CloseSymbolPositions(string sym) {
   int closed = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && 
         PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         PositionGetString(POSITION_SYMBOL) == sym) {
         if(trade.PositionClose(ticket)) closed++;
      }
   }
   if(closed > 0) Print("✅ ", closed, " Positionen ", sym, " geschlossen");
}

//+------------------------------------------------------------------+
//| String-Extraktor (für symbol in JSON)                            |
//+------------------------------------------------------------------+
string ExtractString(string text, string start_key, string end_key) {
   int start = StringFind(text, start_key);
   if(start < 0) return "";
   start += StringLen(start_key);
   int end = StringFind(text, end_key, start);
   if(end < 0) return "";
   return StringSubstr(text, start, end - start);
}
