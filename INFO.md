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

- **`update_db.py` is single-shot (no `while` loop).** It runs top-to-bottom
  once and exits. GitHub Actions (`on: schedule: cron "*/15 * * * *"`) is the external
  scheduler — spins up a fresh runner every 15 min, runs the script once, tears down.
- Secrets (`DATABASE_URL`, GCP service-account JSON) live in GitHub repo Secrets,
  injected as env vars — never committed. `workflow_dispatch` added for manual runs.
- Testability: ingest and top_events-update are separate functions, runnable locally
  without Actions. Populate the fact table with a few manual ingest runs, then exercise
  `update_top_events()` against it. Actions is only the clock, not part of correctness.
- **Cron timing (2026-08-05):** the ingest query pins the newest complete window
  (`MentionTimeDate = MAX(...)`). GDELT's BigQuery load lags the window close by a
  VARIABLE 2-12 min, so schedule each run in the **second half** of the 15-min window
  (~10-12 min past each :00/:15/:30/:45 boundary), not right after it. Firing too early
  can let a slow GDELT load push the next run onto a newer window and skip the one
  between. Real fix (V2): track last-ingested window and backfill gaps.

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

## 2026-08-05 — Ingest the SECOND-newest window, not MAX (window completeness research)

- **Finding (measured, see `docs/research/window_completeness.md`):** a 15-min window
  appears in BQ 5–10 min *before* its `MentionTimeDate` label, but with a **partial**
  count that GDELT tops up over the next few minutes (observed 3740 → 5430, ~31%
  undercount). A window is complete **only once a newer window exists**.
- **Decision:** supersedes the earlier `WHERE MentionTimeDate = MAX(...)`. Ingest the
  **second-newest** distinct window (`... ORDER BY MentionTimeDate DESC LIMIT 1 OFFSET 1`)
  — the newest window that already has a successor, hence settled. Costs ~15 min extra
  staleness for a complete, stable article count.
- Reinforces the "run in the second half of the window" cron note: both target settled
  data. Also keeps the single-window grain (`GROUP BY GlobalEventID`) correct.
- **TODO:** update `gdelt_ingest.sql` (user-owned) `WHERE` from `= MAX` to the
  second-newest subquery.

## 2026-08-07 — Step B built (`refresh_top_events.sql` + `update_top_events_table()`); `is_dead` dropped

- **New file `data-pipeline/sql/refresh_top_events.sql`** (renamed from the `get_top10_events.sql`
  stub). Computes the top-10 per timeframe and upserts into `top_events`. Runs on **Neon**, not BQ.
- **Compute pushed entirely into Postgres** — `INSERT ... SELECT ... ON CONFLICT`, so no rows are
  shipped to Python and back. `update_top_events_table()` just reads the file and `cur.execute()`s
  it inside one `with conn:` transaction.
- **Single-pass scoring (`FILTER`).** Instead of three near-identical CTEs (one scan per timeframe),
  one scan over the last 7 days with `SUM(...) FILTER (WHERE time_window_15min >= now() - INTERVAL ...)`
  yields articles_1h/1d/1w together (conditional aggregation). Then three cheap `ORDER BY ... LIMIT 10`
  rankings over the in-memory result.
- **`weight` factored out:** `ABS(goldstein) * normalizing_coef` is constant per event, so it's computed
  once per event and multiplied by each timeframe's article SUM. `country_baseline` LEFT JOIN, missing
  country → `COALESCE(..., 1.0)`.
- **`DISTINCT ON (global_event_id) ... ORDER BY global_event_id, time_window_15min DESC`** gives the
  event's LATEST fact row in one shot — used for both the display snapshot AND the current `avg_tone`.
  Fixes the "which avg_tone?" question: `MAX(avg_tone)` is wrong (largest value, not newest);
  DISTINCT ON picks the newest window.
- **UPSERT semantics — the key point.** `ON CONFLICT (global_event_id) DO UPDATE SET` lists ONLY the
  volatile columns (`avg_tone`, `articles_*`, `relevance_*`). Display snapshot,
  `time_added_to_top_events`, `best_urls_json`, `ai_summary` are absent → set once on first insert,
  never overwritten. This is why we UPSERT and do **not** DELETE+INSERT: delete+insert would wipe the
  expensive `best_urls_json` (URL algorithm) and `ai_summary` (LLM tokens). New entrants insert those
  as NULL; step C later fills them `WHERE ai_summary IS NULL`.
- **`is_dead` tombstone REMOVED** (init_db.sql + README). MVP simplification: instead of tracking dead
  events and skipping them, each tick first `UPDATE top_events SET ... = 0` (reset all leaderboard
  columns), then upserts the current top-10s. An event that fell out of every top-10 just reads 0, so
  it never surfaces via `ORDER BY relevance_1x DESC LIMIT 10`. Full-table reset each tick is fine —
  `top_events` is tiny. Also dropped the green/yellow/red conceptual grouping (kept only the
  set-once vs per-tick update distinction in the README, since it's what justifies the memoization).
- **Design choice — 0 vs actual value when not in a timeframe's top-10:** a row shows a timeframe's
  articles_/relevance_ ONLY when it's in that timeframe's top-10, else 0 (user's spec). Alternative
  would be to always store the true per-timeframe SUM; rejected — the frontend only reads
  `ORDER BY relevance_1x DESC LIMIT 10`, so non-top values are never displayed anyway.
- **Bug caught in the draft:** the prototype filtered the window with
  `HAVING time_window_15min <= now() - 1 hour` — wrong twice: it's a per-row filter (belongs in
  `WHERE`, not `HAVING`, and the column isn't aggregated), and the direction is `>=` (within the last
  hour), not `<=`. Fixed in the rewrite.

## 2026-08-07 — Relevance is now a per-HOUR rate (divide by timeframe length)

- **Change:** `relevance = ABS(goldstein) * SUM(articles over tf) * normalizing_coef`
  → `ABS(goldstein) * (SUM(articles over tf) / tf_hours) * normalizing_coef`.
- **Why:** the raw `SUM` grows with the window length, so 1W would mechanically outrank 1D
  outrank 1H just by summing more 15-min rows. Dividing by the timeframe length converts the
  total into an **articles-per-hour rate**, making relevance **comparable across timeframes**.
- **Unit chosen = HOURS** (`1h=1, 1d=24, 1w=168`). Any consistent unit (windows 4/96/672,
  minutes 60/1440/10080, hours) is mathematically equivalent — it's a constant divisor per
  timeframe. Picked hours because "articles/hour" is the most interpretable news-velocity unit
  and keeps the numbers in a sane range.
- **Key property:** dividing by a constant does NOT change the ranking WITHIN a timeframe
  (top-10 per TF is identical) — it only fixes the scale ACROSS timeframes. So the frontend can
  now put all three leaderboards on one comparable relevance scale / color ramp.
- Updated: `refresh_top_events.sql` (formula + `scored` CTE), `README.md` (3 spots). Older log
  entries above keep the pre-division formula as history.

### Open questions / future
- Goldstein sign: `ORDER BY relevance DESC` currently favors cooperative events and
  buries conflicts. Decide whether to rank by `ABS(goldstein)` (impact magnitude).
- `relevance_1h/1d/1w` are overwritten each tick → no relevance *time series* is
  retained (fact table is pruned after 7 days). If historical relevance evolution
  is ever needed, add an append-only `event_relevance_history` table.


refresh_top_events.sql - instead of creating 3 tables (WITH) for each timeframe (scaing articles_table_15_min 3x), we use FILTER

refresh_top_events.sql - using COALESCE if country code is not in country_baseline => relevance is 0 (that way we can keep track of what countries we have there and ignore codes for eg. oceans, countries that can not be ploted on the map for some reason)

update_db.py (formally fetch_and_update.py)
    - migration from psycopg2 to psycopg3
    - update_articles_table_15min() - we use named parameters (see sequence_s) so the changing column order in gdelt_ingest.sql won't break the insert

PROBLEM! I did a research - through BQ Console I queried an article with most mentions over last hour.
The article had over 100 mentions but all where one article posted on several different platforms.
This program solves country bias but not bias of big news companies. (see docs/research/big_news_company)
SOLUTION: Edited gdelt_ingest.sql so insted doing article deduplication by whole URL we do it by URL slug