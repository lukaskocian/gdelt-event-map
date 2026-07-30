This project uses GDELT database to find the most relevant events around the world and plot them on a map.

## Project Structure

```
gdelt-event-map/
├── .github/
│   └── workflows/
│       └── data_pipeline.yml         # GitHub Actions cron job (15-min execution interval)
├── data-pipeline/                    # PYTHON: Data ingestion & Filter 1 implementation
│   ├── sql/                          # BigQuery SQL queries (e.g., fetch_top_events.sql)
│   ├── llm_summarizer/               # LLM API integration for automated event descriptions
│   ├── normalizer.py                 # Calculates demographic baseline weights (W)
│   ├── fetch_and_update.py           # Main ETL script: fetches data & updates PostgreSQL
│   └── requirements.txt              # Python dependencies
├── backend/                          # TYPESCRIPT: API Server & Filter 2 implementation
│   ├── database/                     # PostgreSQL connection setup and query builders
│   ├── routes/                       # API endpoints (e.g., GET /api/events?timeframe=1D)
│   ├── utils/                        # Helper functions (e.g., CAMEO code mapper)
│   └── server.ts                     # Main Express/Node.js application entry point
├── frontend/                         # VUE.JS: Interactive Web Map Client
│   ├── public/                       # Static assets
│   ├── src/
│   │   ├── components/               # Vue components (e.g., Map.vue, EventCard.vue)
│   │   ├── api/                      # Backend API client functions
│   │   └── styles/                   # Global stylesheets
│   └── package.json                  # Node dependencies and build scripts
├── docs/                             # PORTFOLIO DOCUMENTATION
│   ├── ARCHITECTURE.md               # System design, block diagrams, and data flow
│   ├── BASELINE_WEIGHTS.md           # Mathematical model for demographic normalization
│   └── ENGINEERING_JOURNAL.md        # Developer log: challenges faced and solutions
├── .gitignore                        # Ignored files (e.g., node_modules, .env, .DS_Store)
├── CLAUDE.md                         # System prompt and instructions for Claude CLI
└── README.md                         # Project overview, tech stack, and setup guide
```

*Sources:*

https://www.gdeltproject.org/data/lookups/CAMEO.eventcodes.txt

http://data.gdeltproject.org/documentation/GDELT-Event_Codebook-V2.0.pdf