This project uses GDELT database to find the most relevant events around the world and plot them on a map.

gdelt-sentiment-map/                  # Kořenová složka
├── .github/
│   └── workflows/
│       └── data_pipeline.yml         # Instrukce pro GitHub (cron job každých 15 min)
├── data-pipeline/                    # ZDE SE ODEHRÁVÁ TVŮJ FILTR 1
│   ├── sql/                          # Tvé BigQuery dotazy (např. fetch_top_events.sql)
│   ├── llm_summarizer/               # Kód pro napojení na LLM API a generování popisků
│   ├── normalizer.py                 # Skript pro výpočet vah (Baseline W)
│   ├── fetch_and_update.py           # Hlavní skript, který stáhne data a updatne lokální DB
│   └── requirements.txt              # Závislosti (např. google-cloud-bigquery)
├── backend/                          # ZDE SE ODEHRÁVÁ TVŮJ FILTR 2
│   ├── database/                     # Lokální databáze (např. mentions_table.sqlite)
│   ├── routes/                       # API endpointy (např. GET /api/events?timeframe=1D)
│   ├── utils/                        # Pomocné funkce (např. CAMEO code mapper)
│   └── server.js / main.py           # Vstupní bod pro tvůj API server
├── frontend/                         # TVŮJ WEB A MAPA
│   ├── public/
│   ├── src/
│   │   ├── components/               # React/Vue komponenty (Map.jsx, EventCard.jsx)
│   │   ├── api/                      # Funkce pro volání tvého backendu
│   │   └── styles/
│   └── package.json
├── docs/                             # DOKUMENTACE PRO PORTFOLIO
│   ├── ARCHITECTURE.md               # Bloková schémata, jak spolu části komunikují
│   ├── BASELINE_WEIGHTS.md           # Vysvětlení tvého matematického modelu s populací
│   └── ENGINEERING_JOURNAL.md        # Tvůj deník (problémy a jak jsi je řešil)
├── .gitignore
├── CLAUDE.md                         # Instrukce pro Claude CLI
└── README.md                         # Hlavní vizitka projektu (Co to je, jak to spustit)


*Sources:*
https://www.gdeltproject.org/data/lookups/CAMEO.eventcodes.txt

http://data.gdeltproject.org/documentation/GDELT-Event_Codebook-V2.0.pdf