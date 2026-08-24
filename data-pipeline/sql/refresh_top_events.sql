-- For each timeframe (1H / 1D / 1W) chooses top 10 MOST RELEVANT events from articles_table_15_min
-- and inserts them into top_events or updates their relevance in top_events if they are already there

-- an event can be in several timeframes at once, so the merged result is 10-30 DISTINCT
-- events (rows). A timeframe's articles_/relevance_ columns are 0 when the event is not in
-- that timeframe's top 10.

-- RELEVANCE(event, tf) = ABS(goldstein_scale) * (SUM(articles_count over tf) / tf_hours) * normalizing_coef

-- TWO statements, executed in ONE transaction by update_top_events_table():
--   1) reset every row's volatile leaderboard columns to 0, so an event that fell out of
--      ALL top-10s stops showing stale numbers 
--   2) upsert the current top-10-per-timeframe with fresh values.


BEGIN;

UPDATE top_events
SET
    articles_1h = 0,
    articles_1d = 0,
    articles_1w = 0,
    relevance_1h = 0,
    relevance_1d = 0,
    relevance_1w = 0;

INSERT INTO top_events (
    global_event_id,
    date_added,
    avg_tone,
    goldstein_scale,
    source_url,
    event_code,
    action_geo_full_name,
    action_geo_type,
    action_geo_country_code,
    action_geo_lat,
    action_geo_long,
    actor1_name,
    actor1_geo_full_name,
    actor1_country_code,
    actor2_name,
    actor2_geo_full_name,
    actor2_country_code,
    articles_1h,
    relevance_1h,
    articles_1d,
    relevance_1d,
    articles_1w,
    relevance_1w,
    time_added_to_top_events,
    best_urls_json,
    ai_summary
)


WITH number_of_articles_per_timeframe AS (
    SELECT
        global_event_id,
        -- COALESCE ... events with 0 articles will have number 0 instead of NULL
        COALESCE(SUM(articles_count) FILTER (WHERE time_window_15min >= NOW() - INTERVAL '1 week'), 0) AS articles_1w, -- articles_table_15_min should not have more than 1week of data but this FILTER is for safety
        COALESCE(SUM(articles_count) FILTER (WHERE time_window_15min >= NOW() - INTERVAL '1 day'), 0) as articles_1d,
        COALESCE(SUM(articles_count) FILTER (WHERE time_window_15min >= NOW() - INTERVAL '1 hour'), 0) as articles_1h,
        MAX(action_geo_country_code) AS action_geo_country_code,
        MAX(goldstein_scale) AS goldstein_scale
    FROM
        articles_table_15_min -- the table holds data just 1 week
    GROUP BY
        global_event_id
),

relevance_per_article_per_timeframe AS (
    SELECT
        global_event_id,
        articles_1w,
        articles_1d,
        articles_1h,
        action_geo_country_code,
        goldstein_scale,

        articles_1w / 168.0 * (SELECT normalizing_coef FROM country_baseline WHERE country_code = action_geo_country_code) * ABS(goldstein_scale) AS relevance_1w,
        articles_1d / 24.0 * (SELECT normalizing_coef FROM country_baseline WHERE country_code = action_geo_country_code) * ABS(goldstein_scale) AS relevance_1d,
        articles_1h * (SELECT normalizing_coef FROM country_baseline WHERE country_code = action_geo_country_code) * ABS(goldstein_scale) AS relevance_1h
    FROM
        number_of_articles_per_timeframe
),

top_1w AS (
    SELECT
        global_event_id,
        relevance_1w,
        articles_1w
    FROM
       relevance_per_article_per_timeframe
    ORDER BY
        relevance_1w DESC
    LIMIT 10
),

top_1d AS (
    SELECT
        global_event_id,
        relevance_1d,
        articles_1d
    FROM
       relevance_per_article_per_timeframe
    ORDER BY
        relevance_1d DESC
    LIMIT 10
),

top_1h AS (
    SELECT
        global_event_id,
        relevance_1h,
        articles_1h
    FROM
       relevance_per_article_per_timeframe
    ORDER BY
        relevance_1h DESC
    LIMIT 10
),

top_1w_1d_1h AS (

    SELECT global_event_id FROM top_1w
    UNION
    SELECT global_event_id FROM top_1d
    UNION
    SELECT global_event_id FROM top_1h
),

gdelt_data_top_10_to_30 AS ( -- almost ready but without relevance and articles count

    SELECT DISTINCT ON (global_event_id)
        *
    FROM
        articles_table_15_min
    WHERE
        global_event_id IN (SELECT global_event_id FROM top_1w_1d_1h)
    ORDER BY
        global_event_id, time_window_15min DESC
)

SELECT
    g.global_event_id,
    g.date_added,
    g.avg_tone,
    g.goldstein_scale,
    g.source_url,
    g.event_code,
    g.action_geo_full_name,
    g.action_geo_type,
    g.action_geo_country_code,
    g.action_geo_lat,
    g.action_geo_long,
    g.actor1_name,
    g.actor1_geo_full_name,
    g.actor1_country_code,
    g.actor2_name,
    g.actor2_geo_full_name,
    g.actor2_country_code,
    
    COALESCE(h.articles_1h, 0) AS articles_1h,
    COALESCE(h.relevance_1h, 0) AS relevance_1h,

    COALESCE(d.articles_1d, 0) AS articles_1d,
    COALESCE(d.relevance_1d, 0) AS relevance_1d,
    
    COALESCE(w.articles_1w, 0) AS articles_1w,
    COALESCE(w.relevance_1w, 0) AS relevance_1w,

    NOW() AS time_added_to_top_events,

    NULL AS best_urls_json,
    NULL AS ai_summary

FROM 
    gdelt_data_top_10_to_30 g
LEFT JOIN top_1h h USING (global_event_id)
LEFT JOIN top_1d d USING (global_event_id)
LEFT JOIN top_1w w USING (global_event_id)

ON CONFLICT (global_event_id) DO UPDATE SET
    articles_1h  = EXCLUDED.articles_1h,
    relevance_1h = EXCLUDED.relevance_1h,
    articles_1d  = EXCLUDED.articles_1d,
    relevance_1d = EXCLUDED.relevance_1d,
    articles_1w  = EXCLUDED.articles_1w,
    relevance_1w = EXCLUDED.relevance_1w,
    avg_tone = EXCLUDED.avg_tone;
    
COMMIT;