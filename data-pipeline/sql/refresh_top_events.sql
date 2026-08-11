-- Rebuilds the leaderboard of top_events from the fact table articles_table_15_min.
-- For each timeframe (1H / 1D / 1W) it ranks events by relevance and keeps the top 10;
-- an event can be in several timeframes at once, so the merged result is 10-30 DISTINCT
-- events. A timeframe's articles_/relevance_ columns are 0 when the event is not in
-- that timeframe's top 10.
--
--   Relevance(event, tf) = ABS(goldstein_scale) * (SUM(articles_count over tf) / tf_hours) * normalizing_coef
--     - tf_hours = length of the timeframe in HOURS (1h=1, 1d=24, 1w=168). Dividing the
--       article total by the timeframe length turns it into an articles-PER-HOUR rate, so
--       relevance is comparable ACROSS timeframes (a longer window no longer wins just by
--       summing more windows). Dividing by a constant does NOT change the ranking WITHIN a
--       timeframe -- only the cross-timeframe scale.
--     - goldstein_scale and normalizing_coef are constant per event, so they factor
--       out of the SUM as a single per-event `weight`.
--     - normalizing_coef comes from country_baseline (Filter 2); missing country -> 1.0.
--
-- This is INSERT ... SELECT ... ON CONFLICT: the compute AND the upsert both run inside
-- Postgres, so no rows are shipped out to Python and back.
--
-- TWO statements, executed in ONE transaction by update_top_events_table():
--   1) reset every row's volatile leaderboard columns to 0, so an event that fell out of
--      ALL top-10s stops showing stale numbers (we removed the is_dead tombstone; this
--      full reset is the simpler MVP replacement for "keep recomputing dead rows").
--   2) upsert the current top-10-per-timeframe with fresh values.
--
-- Never overwritten here (set once on first insert): the display snapshot
-- (goldstein, geo, actors...), time_added_to_top_events, best_urls_json, ai_summary.
-- The enrichment step (C) fills best_urls_json / ai_summary later WHERE ai_summary IS NULL.

-- 1) Reset the volatile columns for every row.
UPDATE top_events SET
    articles_1h = 0, articles_1d = 0, articles_1w = 0,
    relevance_1h = 0, relevance_1d = 0, relevance_1w = 0;

-- 2) Recompute the leaderboard and upsert it.
INSERT INTO top_events (
    global_event_id,
    date_added, goldstein_scale, event_code, source_url,
    action_geo_full_name, action_geo_type, action_geo_country_code,
    action_geo_lat, action_geo_long,
    actor1_name, actor1_geo_full_name, actor1_country_code,
    actor2_name, actor2_geo_full_name, actor2_country_code,
    avg_tone,
    articles_1h, articles_1d, articles_1w,
    relevance_1h, relevance_1d, relevance_1w
)
WITH per_event AS (
    -- ONE pass over the last 7 days. FILTER splits that single scan into the three
    -- timeframes (conditional aggregation) instead of scanning the table three times.
    SELECT
        a.global_event_id,
        COALESCE(SUM(a.articles_count) FILTER (WHERE a.time_window_15min >= now() - INTERVAL '1 hour'), 0) AS articles_1h,
        COALESCE(SUM(a.articles_count) FILTER (WHERE a.time_window_15min >= now() - INTERVAL '1 day'),  0) AS articles_1d,
        COALESCE(SUM(a.articles_count),                                                                 0) AS articles_1w,
        -- per-event weight = |goldstein| * normalizing_coef  (both constant per event)
        COALESCE(ABS(MAX(a.goldstein_scale)), 0) * COALESCE(MAX(c.normalizing_coef), 1.0) AS weight
    FROM articles_table_15_min a
    LEFT JOIN country_baseline c ON a.action_geo_country_code = c.country_code
    WHERE a.time_window_15min >= now() - INTERVAL '7 days'   -- widest timeframe bounds the scan
    GROUP BY a.global_event_id
),
scored AS (
    -- Relevance is a per-HOUR rate, not a raw total: divide each timeframe's article SUM
    -- by the timeframe length in hours (1h=1, 1d=24, 1w=168) so the three timeframes are
    -- comparable (articles/hour). Ranking WITHIN a timeframe is unchanged (constant divisor).
    SELECT
        global_event_id,
        articles_1h, articles_1d, articles_1w,
        weight * articles_1h / 1.0   AS relevance_1h,   -- 1h  = 1 hour
        weight * articles_1d / 24.0  AS relevance_1d,   -- 1d  = 24 hours
        weight * articles_1w / 168.0 AS relevance_1w    -- 1w  = 168 hours
    FROM per_event
),
-- one top-10 per timeframe
top_1h AS (SELECT global_event_id, articles_1h, relevance_1h FROM scored ORDER BY relevance_1h DESC LIMIT 10),
top_1d AS (SELECT global_event_id, articles_1d, relevance_1d FROM scored ORDER BY relevance_1d DESC LIMIT 10),
top_1w AS (SELECT global_event_id, articles_1w, relevance_1w FROM scored ORDER BY relevance_1w DESC LIMIT 10),
-- distinct set of every event that made ANY top-10 (10-30 events)
ids AS (
    SELECT global_event_id FROM top_1h
    UNION
    SELECT global_event_id FROM top_1d
    UNION
    SELECT global_event_id FROM top_1w
),
snapshot AS (
    -- one display row per event = its MOST RECENT 15-min window.
    -- DISTINCT ON keeps the first row per global_event_id given the ORDER BY, so
    -- "ORDER BY ..., time_window_15min DESC" => the latest window (and its avg_tone).
    -- This is how we "pick the latest avg_tone" instead of MAX(avg_tone) (wrong: that
    -- returns the largest tone value, not the newest one).
    SELECT DISTINCT ON (a.global_event_id)
        a.global_event_id,
        a.date_added, a.goldstein_scale, a.event_code, a.source_url,
        a.action_geo_full_name, a.action_geo_type, a.action_geo_country_code,
        a.action_geo_lat, a.action_geo_long,
        a.actor1_name, a.actor1_geo_full_name, a.actor1_country_code,
        a.actor2_name, a.actor2_geo_full_name, a.actor2_country_code,
        a.avg_tone
    FROM articles_table_15_min a
    WHERE a.global_event_id IN (SELECT global_event_id FROM ids)
    ORDER BY a.global_event_id, a.time_window_15min DESC
)
SELECT
    s.global_event_id,
    s.date_added, s.goldstein_scale, s.event_code, s.source_url,
    s.action_geo_full_name, s.action_geo_type, s.action_geo_country_code,
    s.action_geo_lat, s.action_geo_long,
    s.actor1_name, s.actor1_geo_full_name, s.actor1_country_code,
    s.actor2_name, s.actor2_geo_full_name, s.actor2_country_code,
    s.avg_tone,
    COALESCE(h.articles_1h,  0) AS articles_1h,
    COALESCE(d.articles_1d,  0) AS articles_1d,
    COALESCE(w.articles_1w,  0) AS articles_1w,
    COALESCE(h.relevance_1h, 0) AS relevance_1h,
    COALESCE(d.relevance_1d, 0) AS relevance_1d,
    COALESCE(w.relevance_1w, 0) AS relevance_1w
FROM snapshot s
LEFT JOIN top_1h h USING (global_event_id)
LEFT JOIN top_1d d USING (global_event_id)
LEFT JOIN top_1w w USING (global_event_id)
ON CONFLICT (global_event_id) DO UPDATE SET
    -- ONLY the volatile columns are refreshed on an existing event.
    -- Display snapshot, best_urls_json, ai_summary, time_added_to_top_events are
    -- deliberately absent here => they keep their first-insert values forever.
    avg_tone     = EXCLUDED.avg_tone,
    articles_1h  = EXCLUDED.articles_1h,
    articles_1d  = EXCLUDED.articles_1d,
    articles_1w  = EXCLUDED.articles_1w,
    relevance_1h = EXCLUDED.relevance_1h,
    relevance_1d = EXCLUDED.relevance_1d,
    relevance_1w = EXCLUDED.relevance_1w;
