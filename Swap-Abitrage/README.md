**SOFTWARE**

MetaTrader 5 (neueste Version) - 2x Installation
Python 3.8+ 
Git (optional, für Versionierung)

**1. MT5 Terminals einrichten**

1. Lade MT5 von 2 verschiedenen Brokern herunter/installieren
2. Terminal A: Broker A Account → Chart EURUSD öffnen
3. Terminal B: Broker B Account → Chart EURUSD öffnen
4. BEIDE Terminals: Tools → Options → Expert Advisors → "Allow DLL imports" ✓

**2. MQL5 EA deployen**

1. MetaEditor öffnen (F4 in MT5)
2. SwapArbBridge_Multi.mq5 kopieren/pasten
3. F7 kompilieren → SwapArbBridge_Multi.ex5

TERMINAL A:
- EA auf EURUSD Chart → BROKER_ID="BROKER_A"
- SYMBOL_PREFIX="EURUSD,GBPUSD,AUDUSD,XAUUSD"

TERMINAL B: 
- EA auf EURUSD Chart → BROKER_ID="BROKER_B" 
- Gleiche SYMBOL_PREFIX

**3. Python Server**

Windows/Linux Terminal
pip install flask pathlib
Code in swaparb_master.py speichern
python swaparb_master.py

**📁 Dateistruktur (automatisch)**

~/.SwapArb/ (oder C:\Users\[Name]\SwapArb\)

├── status_BROKER_A.json     ← EA A schreibt (alle 30s)  
├── status_BROKER_B.json     ← EA B schreibt (alle 30s)  
├── commands_BROKER_A.json   ← Python → EA A  
└── commands_BROKER_B.json   ← Python → EA B

**Python Config (swaparb_master.py)**

SYMBOLS = ["EURUSD", "GBPUSD", "AUDUSD"]  # Muss EA entsprechen!
MIN_SWAP_DIFF = 0.5  # Min. Vorteil pro Lot/Tag
MAX_LOTS = 1.0       # Max Position pro Symbol


**✅ Test-Checklist**

[ ] MT5 Terminal A läuft → Experts Tab: "12 Symbole gestartet"
[ ] MT5 Terminal B läuft → Experts Tab: "12 Symbole gestartet"  
[ ] ~/.SwapArb/ Ordner existiert → status_*.json erscheinen (alle 30s)
[ ] Python Log: "5 Symbole Broker A" + "5 Symbole Broker B"
[ ] Python Log: "💰 EURUSD: Swap-Diff 0.750 → Commands geschickt"
[ ] MT5 Logs: "✅ BUY 0.5 EURUSD ausgeführt"

**🛡️ Sicherheits- / Risiko-Settings**

swaparb_master.py anpassen:
MAX_LOTS = 0.01      # Demo: Micro-Lots nur!
MIN_SWAP_DIFF = 1.0  # Nur starke Arbitrage
Margin-Check: lots = min(MAX_LOTS, margin/2000)

**📊 Monitoring**

tail -f ~/.SwapArb/*.json    # Linux: Live Dateien
Oder Python Logs beobachten
