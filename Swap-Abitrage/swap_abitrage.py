import json
import time
import os
from pathlib import Path
from typing import Dict, List
import logging

# Logging einrichten
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger(__name__)

# SwapArb Ordner
BASE_DIR = Path.home() / "SwapArb"  # ~/.SwapArb/ oder C:\Users\[Name]\SwapArb\
BASE_DIR.mkdir(exist_ok=True)

SYMBOLS = ["EURUSD", "GBPUSD", "AUDUSD", "USDCAD", "XAUUSD"]  # Gleiche Liste wie EAs!
MIN_SWAP_DIFF = 0.5  # Min. Swap-Vorteil pro Tag/Lot
MAX_LOTS = 1.0       # Max Risiko pro Symbol

class SwapArbMaster:
    def __init__(self):
        self.status_a: Dict = {}
        self.status_b: Dict = {}
        self.positions: Dict = {}  # Tracking aktuelle Positionen
        
    def run(self):
        """Main Loop: Status lesen → entscheiden → Commands schreiben"""
        logger.info("🚀 SwapArb Master gestartet...")
        
        while True:
            try:
                self.read_status_files()
                self.analyze_and_trade()
                time.sleep(10)  # 10s Poll-Intervall
                
            except KeyboardInterrupt:
                logger.info("🛑 Beenden...")
                break
            except Exception as e:
                logger.error(f"❌ Fehler: {e}")
                time.sleep(5)

    def read_status_files(self):
        """Liest Status von beiden Brokern"""
        status_a_file = BASE_DIR / "status_BROKER_A.json"
        status_b_file = BASE_DIR / "status_BROKER_B.json"
        
        if status_a_file.exists():
            self.status_a = json.loads(status_a_file.read_text())
            logger.info(f"📊 Broker A: {len(self.status_a)} Symbole")
        
        if status_b_file.exists():
            self.status_b = json.loads(status_b_file.read_text())
            logger.info(f"📊 Broker B: {len(self.status_b)} Symbole")

    def analyze_and_trade(self):
        """Analysiert Swaps → generiert Commands"""
        if not self.status_a or not self.status_b:
            return
        
        commands_a = []
        commands_b = []
        
        # Jedes Symbol checken
        for symbol_data_a in self.status_a:
            symbol = symbol_data_a["symbol"]
            if symbol not in SYMBOLS:
                continue
                
            # Broker B Daten finden
            symbol_data_b = next((s for s in self.status_b if s["symbol"] == symbol), None)
            if not symbol_data_b:
                continue
            
            # Swap-Arbitrage Logik
            swap_diff, rec_a, rec_b = self.calculate_arbitrage(symbol_data_a, symbol_data_b)
            
            if swap_diff > MIN_SWAP_DIFF:
                logger.info(f"💰 {symbol}: Swap-Diff {swap_diff:.3f} → A:{rec_a} B:{rec_b}")
                commands_a.append(rec_a)
                commands_b.append(rec_b)
        
        # Commands schreiben
        if commands_a:
            self.write_commands("BROKER_A", commands_a)
        if commands_b:
            self.write_commands("BROKER_B", commands_b)

    def calculate_arbitrage(self, data_a, data_b) -> tuple:
        """Berechnet beste Hedge-Strategie"""
        symbol = data_a["symbol"]
        margin_a, margin_b = data_a["free_margin"], data_b["free_margin"]
        
        swap_long_a, swap_short_a = data_a["swap_long"], data_a["swap_short"]
        swap_long_b, swap_short_b = data_b["swap_long"], data_b["swap_short"]
        
        # Test 4 Kombinationen (pro Lot)
        strategies = [
            # BrokerA LONG + BrokerB SHORT
            (swap_long_a - swap_short_b, "buy", "sell"),
            # BrokerA SHORT + BrokerB LONG  
            (swap_short_a - swap_long_b, "sell", "buy"),
        ]
        
        best_diff = 0
        best_a_type, best_b_type = None, None
        
        for diff, a_type, b_type in strategies:
            if diff > best_diff and margin_a > MAX_LOTS * 1000 and margin_b > MAX_LOTS * 1000:
                best_diff = diff
                best_a_type, best_b_type = a_type, b_type
        
        lots = min(MAX_LOTS, margin_a / 2000, margin_b / 2000)  # Margin-Schutz
        
        if best_diff > 0:
            rec_a = {"symbol": symbol, "cmd": "open", "type": best_a_type, "lots": lots}
            rec_b = {"symbol": symbol, "cmd": "open", "type": best_b_type, "lots": lots}
            return best_diff, rec_a, rec_b
        
        return 0, None, None

    def write_commands(self, broker_id: str, commands: List[dict]):
        """Schreibt Commands in EA-Datei"""
        filename = BASE_DIR / f"commands_{broker_id}.json"
        filename.write_text(json.dumps(commands, indent=2))
        logger.info(f"📤 {len(commands)} Commands → {broker_id}")

# Start
if __name__ == "__main__":
    master = SwapArbMaster()
    master.run()
