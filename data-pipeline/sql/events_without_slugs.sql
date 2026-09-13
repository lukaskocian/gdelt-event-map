SELECT 
    global_event_id
FROM
    top_events
WHERE
    best_urls_json IS NULL

    AND

    (relevance_1h > 0
    OR relevance_1d > 0
    OR relevance_1w > 0)