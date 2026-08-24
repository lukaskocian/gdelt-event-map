# Global Event Map

A real-time, full-stack data visualization dashboard that ingests, processes, and normalizes *MOST RELEVANT* global events based on GDELT 2.0 Database. Designed to bypass traditional media bias by utilizing demographic normalization and presenting the most critical global events dynamically on an interactive map. Most relevant events are summerized with LLM.

## Architecture & Tech Stack

*   **Data Pipeline:** Python, Google BigQuery, GitHub Actions (Cron Jobs)
*   **Database:** PostgreSQL (Serverless via Neon.tech)
*   **Backend:** Bun, ElysiaJS, TypeScript
*   **Frontend:** Vue.js, TypeScript
*   **AI Integration:** Gemini API

## Project Structure

```
gdelt-event-map/
├── .github/
│   └── workflows/
│       └── data_pipeline.yml         # GitHub Actions cron job (15-min execution interval)
├── data-pipeline/                    # PYTHON: Data ingestion & Filter 1 implementation
│   ├── sql/                          # BigQuery & Neon SQL (e.g., gdelt_ingest.sql, init_db.sql)
│   ├── reference/                    # Git-tracked reference data (source of truth)
│   │   ├── cameo_codes.csv           # CAMEO event code → human-readable meaning
│   │   └── gdelt_events_attributes.md # GDELT events attribute glossary (used ones flagged)
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
│   ├── ENGINEERING_JOURNAL.md        # Developer log: challenges faced and solutions
│   └── research/                     # Data-driven decisions (query → result → decision)
├── .gitignore                        # Ignored files (e.g., node_modules, .env, .DS_Store)
├── CLAUDE.md                         # System prompt and instructions for Claude CLI
└── README.md                         # Project overview, tech stack, and setup guide
```

## Core Engineering Concepts

1.  **Event Relevance formula** — computed at *read time* as a per-timeframe
    aggregate, **not** stored per row:

    ```
    R = ABS(goldstein_scale) * (SUM(articles_count over the timeframe) / timeframe_hours) * normalizing_coef
    ```

    Because the article total is a `SUM` over all 15-minute rows of an event
    within a window (1h / 1d / 1w), relevance is a `GROUP BY` aggregate, not a
    row attribute. The `SUM` is divided by the **timeframe length in hours**
    (`1h=1`, `1d=24`, `1w=168`) so relevance is an articles-**per-hour rate**, not a
    raw total — otherwise a longer window would always win just by summing more
    15-min rows, and the three timeframes would not be comparable. (Dividing by a
    constant does not reorder events *within* a timeframe — it only fixes the scale
    *across* timeframes.) It is recomputed every 15 minutes by the pipeline (SQL
    `GROUP BY global_event_id … ORDER BY relevance DESC LIMIT 10`) and materialized into
    `top_events`, from which the API reads cheaply.

2.  **Demographic Normalization** — raw article counts are biased toward
    media-heavy countries. A per-country `normalizing_coef` (baseline weight `W`)
    down-weights loud countries so a major event in a quiet country is not
    drowned out. The coefficient is a slowly-changing dimension: recomputed
    periodically by `normalizer.py` and stored in `country_baseline`, then joined
    at read time by the 15-minute job (a cheap lookup, never recomputed per tick).
    Normalization is applied **only at Filter 2** (the relevance computation), never
    at ingest — Filter 1 keeps raw counts, so the fact table stays source-of-truth
    and re-tuning coefficients never requires re-ingesting.

3.  **Storage model — three tables** (fact + slowly-changing dimension +
    curated materialized leaderboard), replacing the earlier single-table design:

    **`articles_table_15_min`** — *fact* table, one row per event per 15-minute
    window. **TTL 7 days** (old rows are pruned). Populated each tick by one
    BigQuery query — `eventmentions` (last 15 min, `Confidence > 60`) →
    `GROUP BY GLOBALEVENTID`, `COUNT(DISTINCT MentionIdentifier)` →
    `JOIN events` for metadata → **keep the ~200 events with the highest _raw_
    article count (Filter 1)**. Normalization is deliberately **not** applied here:
    Filter 1 is a cheap raw cut in BigQuery, and per-country normalization happens
    later at read time (Filter 2, in the relevance computation) where the
    coefficients live. Curated links (`best_urls_json`) live in `top_events` instead.

    **Primary key is the natural composite `(global_event_id, time_window_15min)`** —
    no surrogate `id`. It expresses the grain, is the `ON CONFLICT` UPSERT target, and
    doubles as the `(global_event_id, …)` index, so we need neither a serial id nor a
    separate event-id index. Event metadata is denormalized onto the fact row (copied
    from `events`) so `top_events` can snapshot it on entry.

    | column | notes |
    |---|---|
    | `global_event_id` | GDELT `GlobalEventID` — PK part 1 |
    | `time_window_15min` | 15-min window timestamp (TZ-aware) — PK part 2 |
    | `articles_count` | distinct articles in this window |
    | `avg_tone` | GDELT `AvgTone` (read per-tick by `top_events`) |
    | `goldstein_scale` | event impact score (−10…+10) |
    | `date_added`, `source_url`, `event_code` | GDELT event metadata |
    | `action_geo_country_code` | FIPS country (joins `country_baseline`) |
    | `action_geo_full_name`, `action_geo_type`, `action_geo_lat`, `action_geo_long` | action location |
    | `actor1_name`, `actor1_geo_full_name`, `actor1_country_code` | actor 1 (CAMEO country) |
    | `actor2_name`, `actor2_geo_full_name`, `actor2_country_code` | actor 2 (CAMEO country) |

    **`country_baseline`** — slowly-changing dimension for normalization.

    | column | notes |
    |---|---|
    | `country_code` | primary key |
    | `normalizing_coef` | baseline weight `W`, refreshed by `normalizer.py` |
    | `updated_at` | last recompute |

    **`top_events`** — curated dimension + materialized leaderboard. Holds **only**
    events that have ever reached top-10 in any timeframe. **Never pruned** (small,
    valuable historical catalogue). Must be **self-sufficient for rendering**,
    because it outlives the fact table: it carries an immutable display snapshot of
    the event's attributes, copied on entry. `time_added_to_top_events`,
    `best_urls_json` and `ai_summary` are set **once** per event (memoized) so an
    event flapping in and out of the top-10 does not trigger repeated LLM calls. The
    leaderboard columns (`articles_*`, `relevance_*`) plus `avg_tone` are recomputed
    every 15 min: each tick resets every row's leaderboard columns to 0, then upserts
    the current top-10-per-timeframe — so an event that dropped out of all top-10s
    simply reads 0 (no tombstone / no "dead" bookkeeping needed for the MVP).
    (`avg_tone` is the one GDELT event attribute that **drifts** as new articles arrive,
    so unlike the immutable snapshot fields it is refreshed per tick.)

    | column | category | notes |
    |---|---|---|
    | `global_event_id` | key | primary key (one row per event) |
    | `goldstein_scale`, `event_code`, `date_added`, `source_url` | snapshot | immutable display copy from `articles_table_15_min` |
    | `action_geo_*`, `actor1_*`, `actor2_*` | snapshot | location + actor display attributes |
    | `time_added_to_top_events` | set once | when **we** first added it to `top_events` (≠ GDELT `date_added`) |
    | `best_urls_json` | set once | JSONB, top ~5 links (word-content + Confidence) |
    | `ai_summary` | set once | LLM summary, generated once per event |
    | `avg_tone` | per-tick | GDELT `AvgTone`, refreshed from the event's latest fact row |
    | `articles_1h/1d/1w` | per-tick | SUM of articles in each window (0 when not in that timeframe's top-10) |
    | `relevance_1h/1d/1w` | per-tick | `ABS(goldstein) * (SUM(articles) / timeframe_hours) * normalizing_coef`, i.e. articles/hour (0 when not in that timeframe's top-10) |

### Pipeline schedule

```
EVERY 15 MIN  (fetch_and_update.py):

  A. INGEST articles_table_15_min  (one BigQuery query — Filter 1):
     1. eventmentions_partitioned, last 15 min, WHERE Confidence > 60
     2. GROUP BY GLOBALEVENTID, COUNT(DISTINCT MentionIdentifier) AS articles_count
     3. JOIN events_partitioned for metadata (country, goldstein, cameo, actors);
        reuse already-stored metadata for events we've seen before, so
        long-running events are not lost to old event partitions
     4. ORDER BY raw articles_count DESC, LIMIT ~200  [Filter 1 — RAW cut, no
        normalization; empirically ~100 events have ≥2 articles, so 200 is a safe cap]
     5. UPSERT those rows into articles_table_15_min

  B. UPDATE top_events  (refresh_top_events.sql over articles_table_15_min — Filter 2,
     normalization here; the whole step is one Postgres transaction, no data leaves the DB):
     6. one pass over the last 7 days: per event SUM(articles_count) split per timeframe
        (1h/1d/1w) with FILTER, JOIN country_baseline and apply per-country normalization;
        divide by the timeframe length in hours so relevance is a per-hour rate:
        relevance = ABS(goldstein) * (SUM(articles) / tf_hours) * normalizing_coef   [Filter 2]
     7. rank each timeframe, keep top-10; UNION them into 10-30 distinct events; take each
        event's latest fact row (DISTINCT ON) for its display snapshot + current avg_tone
     8. reset every top_events row's leaderboard columns to 0, then UPSERT the current
        top-10s (DO UPDATE SET touches ONLY avg_tone + articles_*/relevance_*, so
        best_urls_json, ai_summary and the display snapshot are never overwritten)

  C. ENRICH new entrants only:
     9. one batched BigQuery query over eventmentions_partitioned (last 24h,
        GLOBALEVENTID IN (…)): filter top 5 URLs (word-content + Confidence)
        → top_events.best_urls_json (fetched once on entry, not refreshed — MVP)
    10. LLM (Gemini) summary from those URLs → top_events.ai_summary  (once per event)

PERIODICALLY  (normalizer.py, daily/weekly):
  recompute country_baseline.normalizing_coef from historical article volumes
```

**URL sourcing & cost.** The list of article links for an event lives in
`gdelt-bq.gdeltv2.eventmentions` (`MentionIdentifier`), not in `events`. BigQuery
bills by **columns × partitions scanned**, not by the `WHERE GLOBALEVENTID` filter,
so URLs are fetched **only** for events that reach `top_events`, in a **single
batched query** per tick (one partition scan for all ~10 events, vs. N scans for N
per-event queries), with a **bounded `_PARTITIONTIME` window** to cap cost.

## Open Research & TODO

Data-driven decisions to be reproduced and documented under `docs/research/`
(each writeup: **question → query → result table → decision**):

- [ ] **Country_baselines check** - check if table Country_baselines has all country codes, events in countries that are not in the table will not get into top events
- [ ] **Metadata coverage** — one SQL query confirming what share of events appearing
  in `eventmentions` (last 15 min) have their `events` row within the last day
  (observed ≈97%). Justifies the **1-day** metadata JOIN window; the ~3% without
  metadata are dropped. Open sub-question: reuse stored metadata for multi-day
  trending events so they aren't dropped on day 2+ (see INFO.md). →
  `docs/research/metadata_coverage.md`
- [ ] **Top-200 ingest cutoff (Filter 1)** — reproduce and document why ~200 is the
  cutoff (beyond it events have ≈1 article). 200 is a tunable knob. →
  `docs/research/top_n_cutoff.md`
- [ ] **Country normalization coefficients** — derive per-country `normalizing_coef`,
  document the methodology, and commit the concrete values to the
  `country_baseline` seed in `data-pipeline/sql/init_db.sql` (currently all `1.0`
  placeholders; `normalizer.py` refreshes them). Clamped to **[0.2, 5.0]** so
  micro-states (e.g. Vatican) don't hit absurd extremes. Applied at **Filter 2**
  (relevance), not at ingest. → `docs/research/normalization_coefficients.md`

**Reference data location:** the repo is the single source of truth (git-tracked,
transparent). Country `normalizing_coef` values are seeded **directly in
`data-pipeline/sql/init_db.sql`** (an `INSERT` of every FIPS country, all `1.0` for
now) and live in the `country_baseline` table the relevance query JOINs;
`cameo_codes.csv` is read directly for display.

## Future Improvements

Ideas intentionally left out of the MVP to keep it simple and cheap:

- **Refresh the "set once" attributes over an event's lifetime.** `best_urls_json`
  and `ai_summary` are frozen when an event enters `top_events` (only `avg_tone` is
  already refreshed per tick). A future version could periodically refresh links and
  summary too, so they track how the story evolves instead of reflecting only the
  moment of entry.
- **Richer tone / emotion analysis via the GKG table.** Replace the single
  `avg_tone` scalar with GDELT GKG (GCAM) emotional dimensions for a deeper read of
  each event's sentiment (more expensive — a separate table and join).
- **Tone history popup.** Today the displayed tone is a single number — the latest
  `AvgTone` from the `events` table (an average across all articles at that moment).
  Clicking "Tone" on a topped event could open a small panel with a **time-series of
  how the tone evolved** since the event first appeared. The `articles_table_15_min`
  fact table already stores `avg_tone` per 15-min window, so the last **7 days** of
  history are available for free by querying that event's rows ordered by
  `time_window_15min`; a longer horizon would need an append-only history table (same
  pattern as the relevance time-series below).
- **Precise geo pins.** Store `ActionGeo_Lat` / `ActionGeo_Long` for exact map
  placement instead of country-level positioning.
- **Relevance time-series.** Keep an append-only history of per-event relevance so
  the map can show how an event trended over time (today the leaderboard columns are
  overwritten each tick).
- **Distinct-source count instead of article count.** Rank by how many independent
  outlets (`MentionSourceName`) cover an event, not just how many articles — a
  stronger "bypass media bias" signal (50 articles from one outlet ≠ 50 outlets).
- **User-tunable relevance weights.** Expose the goldstein/articles weighting so a
  user can re-rank (conflict vs. cooperation) live on the frontend.
- **Frontend caveats for the 1H timeframe.** (a) A small "!" badge flagging that data
  trails the real world by ~30 min (GDELT publish lag + our processing). (b) A note
  that the 1H window is **diurnally skewed**: when a large part of the world is asleep,
  news volume drops, so short-window rankings over-represent whichever regions are
  currently awake. A future version could normalize for time-of-day.

*Relevant Links:*
https://www.gdeltproject.org/data/lookups/CAMEO.eventcodes.txt
http://data.gdeltproject.org/documentation/GDELT-Event_Codebook-V2.0.pdf