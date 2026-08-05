# Project Log — GDELT Event Map

## 2026-08-02 — Storage & compute architecture decided

Moved from a single "One Big Table" to a **three-table model**:

- **`articles_table_15_min`** — fact table, 1 row / event / 15-min window, TTL 7 days.
  `urls` column **removed** (moved to `top_events`). Added
  `UNIQUE(event_id, window_time)` to enable idempotent UPSERT.
- **`country_baseline`** — slowly-changing dimension: `country_code → normalizing_coef`.
  Refreshed periodically by `normalizer.py`; joined at read time.
- **`top_events`** — curated leaderboard + dimension. Only events that ever hit a
  top-10. Never pruned. Self-sufficient for rendering (snapshots display
  attributes because the fact table is pruned after 7 days). Holds filtered
  `urls`, `ai_summary` (memoized once per event), and `relevance_1h/1d/1w`
  (current value only, NULL when not in that timeframe's top-10).

### Key decisions & rationale
- **Relevance is a read-time aggregate, not a stored per-row column.**
  `R = goldstein_scale * SUM(articles_count in timeframe) * normalizing_coef`.
  Computed every 15 min via SQL `GROUP BY event_id … LIMIT 10`, materialized into
  `top_events`. (Corrected an earlier plan to store relevance per row — invalid
  because relevance is defined over a SUM across window rows.)
- **LLM summary + URL filtering are memoized per `event_id`** in `top_events`, so
  an event flapping in/out of the top-10 does not re-trigger paid LLM calls.
- **Normalization baseline is precomputed** (slowly-changing), not recomputed per
  15-min tick.
- **Extraction format from BigQuery: `list[dict]` / plain Python** (small data;
  keeps GitHub Actions runner lean — no pandas/pyarrow). pandas reserved for the
  heavier, infrequent `normalizer.py` job.
- Idempotency strategy: **UPSERT (`ON CONFLICT`)**.

### URL enrichment strategy (2026-08-02)
- URLs come from `gdelt-bq.gdeltv2.eventmentions_partitioned.MentionIdentifier`,
  NOT from `events.SOURCEURL` (single link). Use the **_partitioned** table — the
  plain `eventmentions` is not partitioned, so `_PARTITIONTIME` errors and every
  query scans full history.
- Grain of eventmentions is event × document × **sentence** × time, so
  `(GLOBALEVENTID, MentionIdentifier)` is NOT unique → `DISTINCT` collapses the
  many duplicate URL rows before Python filtering.
- Perf: filtering ~10k URLs in Python is ~tens of ms; bottleneck is I/O (BQ query
  seconds, LLM calls seconds) — do not micro-optimize the filter (Amdahl). Real
  latency risk is sequential LLM calls → parallelize them.
- Fetched **only** when an event enters `top_events`, in **one batched query**
  (`GLOBALEVENTID IN (…)`) with a **bounded `_PARTITIONTIME` window** — because BQ
  bills by columns × partitions scanned, so N per-event queries = N× the scan cost.
- Dedup with `DISTINCT` in SQL; filter to "informative" URLs (headline in slug) in
  **Python** (flexible/testable heuristic); store only the filtered result in
  `top_events.urls`. MVP: fetched once on entry, not refreshed.
- Ranking uses `ABS(goldstein)` (impact magnitude), not raw signed goldstein.
- URL lookup window **locked to 24h**; measured ~20 MB/query (≈58 GB/mo ≈ 6% of
  the 1 TB free tier — negligible). Known limitation: an event entering the 1w
  top-10 that had no articles in the last 24h gets an empty URL list (OK for MVP).
- Partition pruning granularity is **DAY** on GDELT `_partitioned` tables: a
  sub-day filter (e.g. last 15 min) does NOT reduce scanned bytes — it re-reads the
  current day partition each run. Cheap here only because a day is ~20 MB.

### articles_count source (2026-08-02)
- Decided: **COUNT(DISTINCT MentionIdentifier) from eventmentions_partitioned per
  15-min window**, SUM'd across windows at read time. Captures ongoing momentum of
  trending events (unlike `events.NumMentions`, a one-time snapshot at detection).
- Consequence / next: event metadata (goldstein, country_code, cameo, avg_tone,
  actors) lives in `events`, not `eventmentions`. Plan: JOIN eventmentions(counts)
  with events(metadata, bounded recent partitions) at ingest, and memoize metadata
  in Neon so old-but-still-active events keep metadata without wide event scans.

## 2026-08-03 — Pipeline refined (from iPad architecture sketch)

- **Ingestion is ONE BigQuery query** producing ~200 fact rows/tick:
  eventmentions (last 15 min, `Confidence > 60`) → `GROUP BY GLOBALEVENTID`,
  `COUNT(DISTINCT MentionIdentifier)` → `JOIN events` for metadata → keep **top ~200**
  by **raw** article count (**Filter 1**). (Normalization was later moved out of
  Filter 1 to read-time Filter 2 — see 2026-08-04.) Chose the JOIN-at-ingest /
  denormalized fact table over a separate events_dim.
- **Metadata JOIN gotcha:** `events` emits one row per event at detection, so a
  `JOIN events(last day)` returns NULL metadata for events that keep trending past
  a day. Fix = fetch metadata only for NEW event_ids (always in a recent partition)
  and reuse already-stored metadata for known events (memoization). Metadata is
  immutable per event.
- **top_events schema extended:** added `articles_1h/1d/1w`, `relevance_1h/1d/1w`,
  `time_added`, and `is_dead`. Leaderboard columns (articles_/relevance_) are
  recomputed every 15 min **for all live rows** (not just current top-10) — required
  so articles_* can fall to 0 and trigger the tombstone.
- **is_dead tombstone:** true when `time_added` > 7 days ago AND `articles_1h/1d/1w`
  all 0. Dead rows are kept (history) but skipped in the per-tick recompute.
- **Filter 1 side effect:** an event outside the top-200 in a given window loses
  that window's row → its 1W SUM is slightly undercounted. 200 is a tunable knob.
- **COUNT must be `COUNT(DISTINCT MentionIdentifier)`** (eventmentions grain is
  sentence-level; plain COUNT inflates the article count).

### Metadata window & reference data (2026-08-03)
- Metadata JOIN window = **1 day** (research: ~97% of events appearing in
  `eventmentions` in the last 15 min have their `events` row within the last day).
  Events with no metadata (~3%) are dropped — acceptable.
- **Reuse nuance:** metadata is immutable, so once captured it should be reused from
  Neon for an event across its whole lifetime. A multi-day-trending event must NOT
  be re-dropped on day 2+ (its `events` row leaves the 1-day window), otherwise its
  1W SUM is undercounted. The 1-day window is for fetching NEW events; known events
  reuse stored metadata. (To be nailed down in the metadata research.)
- **Reference data — repo is the single source of truth, Neon is a loaded copy:**
  - country coefficients → seeded directly in `data-pipeline/sql/init_db.sql`
    (INSERT of every FIPS country, all `1.0` for now) into `country_baseline`; the
    relevance query JOINs the table. (Superseded the earlier CSV plan on 2026-08-04.)
  - CAMEO codes → `data-pipeline/reference/cameo_codes.csv`, read directly for
    display (no Neon table unless a SQL join is later needed).
- Normalizing coefficients are **clamped to [0.2, 5.0]** (upper 5, lower 0.2) so
  micro-states (e.g. Vatican) don't hit absurd extremes.
- Research to reproduce & document under `docs/research/`: metadata coverage,
  top-200 cutoff, normalization coefficients (see README TODO).

## 2026-08-04 — avg_tone moved out of the fact table

- Removed `avg_tone` from `articles_table_15_min` (it would sit on every 15-min row
  but ~99% never reach top_events → wasted). In `top_events` it moves from the
  snapshot (green) group to the **set-once (red)** group, alongside `urls` and
  `ai_summary` — captured on entry, not refreshed.
- Clarification: avg_tone does NOT require the GKG table. A simple tone is available
  as `events.AvgTone`, or as `AVG(MentionDocTone)` from `eventmentions`. GKG is only
  needed for richer emotional/GCAM dimensions (logged as a future improvement).
- Sourcing: compute `AVG(MentionDocTone)` in the step-C enrichment query that
  already scans eventmentions(24h) for URLs → free, and "current at entry".

## 2026-08-04 — Renamed mentions → articles (metric = distinct articles)

- Our metric is distinct **articles** (`COUNT(DISTINCT MentionIdentifier)`), a cleaner
  importance proxy than raw mentions (robust to sentence-level inflation).
  `MentionIdentifier` = the source document (article URL); multiple sentence rows of
  the same event in one article share it, so DISTINCT collapses to article count.
- Renames applied across .md and .sql (`gdelt_ingest.sql` renamed by the user):
  - table `mentions_table_15_min` → `articles_table_15_min`
  - column `number_of_mentions` → `articles_count` (Neon) / `ArticlesCount` (BQ alias)
  - column `mention_time` → `window_time` (Neon) / `TimeDate15min` (BQ alias)
  - `norm_num_of_mentions` → `norm_articles_count` / `NormArticlesCount` (BQ alias)
  - top_events `mentions_1h/1d/1w` → `articles_1h/1d/1w`
- Postgres columns stay snake_case; BQ aliases use GDELT-style PascalCase; the Python
  loader bridges the two (avoids the Postgres identifier case-folding footgun).
- GDELT's own names (`eventmentions`, `MentionIdentifier`, `MentionTimeDate`,
  `MentionDocTone`) are external — kept as-is.
- Temporal dedup: model is each article processed once, in one 15-min window, so
  summing per-window article counts does NOT double-count. **Verified empirically
  (2026-08-04): 0 articles span >1 window.** Result was trivially clean, so the
  ad-hoc query was removed rather than kept as a research writeup.
- `NormArticlesCount` dropped: normalization happens at read-time Filter 2, folded
  straight into relevance (see 2026-08-04 decision below). gdelt_ingest.sql outputs
  only the raw `ArticlesCount`.

## 2026-08-04 — Normalization moved to Filter 2; Filter 1 is a raw top-200 in BQ

- **Final decision: no normalization at Filter 1.** Filter 1 = raw top ~200 by
  `COUNT(DISTINCT MentionIdentifier)` DESC, done entirely in BigQuery
  (`gdelt_ingest.sql`), UPSERTed as-is into `articles_table_15_min`. Per-country
  normalization happens **only at Filter 2** — the `top_events` relevance query
  (`relevance = ABS(goldstein) * SUM(articles_count) * normalizing_coef`, JOIN
  `country_baseline`).
- **Why this is safe (empirical):** in a 15-min window only ~100 events have ≥2
  articles; the rest have exactly 1. A raw top-200 cut therefore comfortably covers
  every meaningful event, so it can't drop a low-media-volume event that would win
  after normalization (the earlier worry). 200 stays a tunable knob.
- **Supersedes** the earlier same-day plan to normalize in Python at ingest (Filter 1).
  That plan is dropped: keeping normalization at read time means re-tuning
  coefficients never requires re-ingesting, and the fact table stays raw
  source-of-truth.
- **Coefficient storage:** seeded **directly in `init_db.sql`** — an `INSERT` of every
  FIPS country with `normalizing_coef = 1.0` (placeholder), `ON CONFLICT DO NOTHING`.
  No CSV. `normalizer.py` later UPDATEs real weights (clamped [0.2, 5.0]).
  `NormArticlesCount` is dropped (normalization folds straight into relevance).

## 2026-08-04 — Scheduling: stateless single-shot script + GitHub Actions cron

- **`fetch_and_update.py` is single-shot (no `while` loop).** It runs top-to-bottom
  once and exits. GitHub Actions (`on: schedule: cron "*/15 * * * *"`) is the external
  scheduler — spins up a fresh runner every 15 min, runs the script once, tears down.
- Secrets (`DATABASE_URL`, GCP service-account JSON) live in GitHub repo Secrets,
  injected as env vars — never committed. `workflow_dispatch` added for manual runs.
- Testability: ingest and top_events-update are separate functions, runnable locally
  without Actions. Populate the fact table with a few manual ingest runs, then exercise
  `update_top_events()` against it. Actions is only the clock, not part of correctness.

## 2026-08-05 — Naming finalized, composite PK, richer metadata, per-tick avg_tone

- **Full GDELT-faithful naming adopted; the `CountryCode` shortcut is dropped.** Now
  that we also pull actor country codes, every attribute keeps its GDELT name in
  snake_case: `country_code → action_geo_country_code`, `cameo_code → event_code`,
  `event_id → global_event_id`, `window_time → time_window_15min`, `actors` split into
  `actor1_name`/`actor2_name`. Rule + canonical table live in `at_names.txt`; full
  events glossary in `data-pipeline/reference/gdelt_events_attributes.md`.
- **`articles_table_15_min` PK = natural composite `(global_event_id, time_window_15min)`;
  surrogate `id` dropped.** The composite key IS the grain, is the `ON CONFLICT` target,
  and doubles as the `(global_event_id, …)` index — so it also lets us drop the separate
  `idx_event_id`. Nothing FKs to the fact table, so no propagation cost.
- **New `events` metadata added to BOTH tables** (from `gdelt_ingest.sql`): `date_added`,
  `source_url`, `action_geo_full_name/type/lat/long`, `actor1/2_geo_full_name`,
  `actor1/2_country_code`. Denormalized onto the fact row (tens of MB total — fine; a
  narrow fact + event_dim is the textbook alternative if it grew).
- **`avg_tone` moved to the per-tick group in `top_events`** (refreshed each tick from the
  event's latest fact row), because it is the ONE events attribute that drifts as new
  articles arrive — `goldstein_scale`, geo and actors are immutable and stay snapshot.
  Cost is ~zero (column already on the fact row; step B already reads the latest row).
  Semantics: "current tone" (latest window), not a timeframe-weighted average.
- **`top_events` renames:** `time_added → time_added_to_top_events` (our timestamp, ≠ GDELT
  `date_added`), `urls → best_urls_json`.
- Country-code systems differ: `action_geo_country_code` is FIPS (joins `country_baseline`);
  actor `*_country_code` are CAMEO — display only, do NOT join.
- Note (`gdelt_ingest.sql`, user-owned): SELECT was missing commas between the `e.*`
  columns — flagged for the user to fix; naming itself is correct.

## 2026-08-05 — Case translation happens in the BQ SELECT (`AS`), not in Python

- **Decision (revised):** alias every column to snake_case in the BigQuery query
  (`e.Actor1Name AS actor1_name`), so BQ output = Neon columns = Python dict keys are
  all uniformly snake_case. Supersedes the earlier plan to map PascalCase→snake_case in
  the Python loader.
- **Why:** the loader becomes a pure pass-through (`dict(row)` keys already match the
  Neon columns) — no mapping table, so no "forgot a field" drift. The mapping lives at
  the source (the SELECT), co-located with the extraction. Since essentially one query
  loads Neon (`gdelt_ingest.sql`; enrichment C computes `best_urls_json` in Python),
  there is no alias duplication. If multiple queries ever shared fields, centralizing
  the map in Python would win instead.
- Tone history (future): the fact table already stores `avg_tone` per 15-min window, so
  a per-event tone time-series is available for the 7-day TTL for free — logged as a
  Future Improvement (clickable "Tone" popup).

### Open questions / future
- Goldstein sign: `ORDER BY relevance DESC` currently favors cooperative events and
  buries conflicts. Decide whether to rank by `ABS(goldstein)` (impact magnitude).
- `relevance_1h/1d/1w` are overwritten each tick → no relevance *time series* is
  retained (fact table is pruned after 7 days). If historical relevance evolution
  is ever needed, add an append-only `event_relevance_history` table.
