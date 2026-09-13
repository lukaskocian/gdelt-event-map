SELECT 
    global_event_id,
    date_added,
    goldstein_scale,
    event_code,
    event_description,
    source_url,
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
    time_added_to_top_events,
    best_urls_json,
    avg_tone,
    articles_1h,
    articles_1d,
    articles_1w,
    relevance_1h,
    relevance_1d,
    relevance_1w
FROM
    top_events
LEFT JOIN
    event_cameo_codes USING (event_code)
WHERE
    ai_summary IS NULL

    AND

    (relevance_1h > 0
    OR relevance_1d > 0
    OR relevance_1w > 0)