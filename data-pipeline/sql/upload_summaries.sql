UPDATE top_events
SET ai_summary = %(ai_summary)s,
    ai_evidence_quality = %(ai_evidence_quality)s
WHERE global_event_id = %(global_event_id)s