UPDATE top_events 
SET best_urls_json = %(best_slugs)s
WHERE global_event_id = %(global_event_id)s