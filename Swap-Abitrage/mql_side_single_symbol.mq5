//+------------------------------------------------------------------+
//|                                            SwapArbBridge_EA.mq5 |
//|                                  Copyright 2025, Swap Arbitrage |
//+------------------------------------------------------------------+
#property copyright "Swap Arbitrage Bridge"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

input string BROKER_ID = "BROKER_A";     // "BROKER_A" oder "BROKER_B"
input int    STATUS_INTERVAL = 30;       // Sekunden
input ulong  MAGIC = 123456;             // Unique pro Broker
input string SYMBOL = "EURUSD";          // Haupt-Symbol

// Global
datetime last_status = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(MAGIC);
   Print("=== SwapArbBridge gestartet für ", BROKER_ID, " auf ", SYMBOL, " ===");
   return(INIT_SUCCEEDED);
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
//| Sendet Status in lokale Datei und liest Commands                 |
//+------------------------------------------------------------------+
void SendStatusToPython() {
   string json = CreateStatusJSON();
   if(json == "") return;
   
   // Status schreiben (wird automatisch erstellt)
   string status_file = "SwapArb\\status_" + BROKER_ID + ".json";
   int handle = FileOpen(status_file, FILE_WRITE | FILE_TXT | FILE_COMMON);
   
   if(handle != INVALID_HANDLE) {
      FileWriteString(handle, json);
      FileClose(handle);
      Print("Status → ", status_file);
      
      // Commands lesen
      ReadCommandsFromFile();
   } else {
      Print("❌ Datei-Fehler: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Erstellt JSON mit Positionen, Margin, Swaps                      |
//+------------------------------------------------------------------+
string CreateStatusJSON() {
   double long_lots = 0, short_lots = 0;
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   // Positionen zählen
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == MAGIC && 
            PositionGetString(POSITION_SYMBOL) == SYMBOL) {
            double lots = PositionGetDouble(POSITION_VOLUME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               long_lots += lots;
            else
               short_lots += lots;
         }
      }
   }
   
   // Swap Rates (tägliche Swaps)
   double swap_long = SymbolInfoDouble(SYMBOL, SYMBOL_SWAP_LONG);
   double swap_short = SymbolInfoDouble(SYMBOL, SYMBOL_SWAP_SHORT);
   
   string json = StringFormat(
      "{\"broker\":\"%s\",\"symbol\":\"%s\",\"long_lots\":%.2f,\"short_lots\":%.2f,"
      "\"free_margin\":%.0f,\"swap_long\":%.4f,\"swap_short\":%.4f,\"timestamp\":%lld}",
      BROKER_ID, SYMBOL, long_lots, short_lots, free_margin, swap_long, swap_short, TimeCurrent()
   );
   
   return json;
}

//+------------------------------------------------------------------+
//| Liest Kommandos aus Python-Datei                                 |
//+------------------------------------------------------------------+
void ReadCommandsFromFile() {
   string cmd_file = "SwapArb\\commands_" + BROKER_ID + ".json";
   int handle = FileOpen(cmd_file, FILE_READ | FILE_TXT | FILE_COMMON);
   
   if(handle != INVALID_HANDLE) {
      string response = FileReadString(handle);
      FileClose(handle);
      
      if(StringLen(response) > 10) {  // Nicht leer
         Print("← Command: ", response);
         ParseAndExecuteCommand(response);
         
         // Datei leeren (bestätigt)
         FileDelete(cmd_file, FILE_COMMON);
         Print("✅ Command ausgeführt");
      }
   }
}

//+------------------------------------------------------------------+
//| Parst Python Response und führt Kommandos aus                    |
//+------------------------------------------------------------------+
void ParseAndExecuteCommand(string response) {
   if(StringFind(response, "\"cmd\":\"open\"") >= 0) {
      ENUM_ORDER_TYPE type = (StringFind(response, "\"type\":\"buy\"") >= 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double lots = ExtractDouble(response, "\"lots\":");
      
      if(lots > 0) {
         if(type == ORDER_TYPE_BUY) {
            if(trade.Buy(lots, SYMBOL, 0, 0, 0, "SwapArb")) Print("✅ BUY ", lots);
            else Print("❌ BUY Fehler: ", trade.ResultRetcode());
         } else {
            if(trade.Sell(lots, SYMBOL, 0, 0, 0, "SwapArb")) Print("✅ SELL ", lots);
            else Print("❌ SELL Fehler: ", trade.ResultRetcode());
         }
      }
   }
   
   if(StringFind(response, "\"cmd\":\"close\"") >= 0) {
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Schließt alle Positionen dieses EAs                             |
//+------------------------------------------------------------------+
void CloseAllPositions() {
   int closed = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && 
         PositionGetInteger(POSITION_MAGIC) == MAGIC &&
         PositionGetString(POSITION_SYMBOL) == SYMBOL) {
         if(trade.PositionClose(ticket)) closed++;
      }
   }
   Print("✅ ", closed, " Positionen geschlossen");
}

//+------------------------------------------------------------------+
//| Extrahiert double-Wert nach "key:" aus JSON-String               |
//+------------------------------------------------------------------+
double ExtractDouble(string text, string key) {
   int pos = StringFind(text, key);
   if(pos < 0) return 0;
   pos += StringLen(key);
   int end = StringFind(text, ",", pos);
   if(end < 0) end = StringFind(text, "}", pos);
   string num = StringSubstr(text, pos, end-pos);
   return StringToDouble(num);
}
