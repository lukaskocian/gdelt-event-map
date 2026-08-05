# Window completeness — is `MentionTimeDate = MAX` safe to ingest?

**Question.** Our ingest query pins a single 15-minute window
(`WHERE MentionTimeDate = MAX(...)`). Is that window's article count **complete** the
moment it appears in BigQuery, or does GDELT keep filling it? If it keeps filling,
`= MAX` would ingest a partial, undercounted window.

## Method

Run this every ~1 minute and watch whether the newest window's `COUNT(*)` grows:

```sql
SELECT MentionTimeDate, COUNT(*) AS n
FROM `gdelt-bq.gdeltv2.eventmentions_partitioned`
WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
GROUP BY MentionTimeDate
ORDER BY MentionTimeDate DESC
LIMIT 3
```

## Result (2026-08-05, times converted to UTC; local was CEST = UTC+2)

| Observed at (UTC) | newest window | count | 2nd window | count | 3rd window | count |
|---|---|---|---|---|---|---|
| 17:40 – 17:49 | **17:45** | **3740** | 17:30 | 6635 | 17:15 | 5793 |
| 17:50 – 17:55 | **18:00** | 4187 | **17:45** | **5430** | 17:30 | 6635 |

Key movements:
- The **17:45** window was visible as the newest from 17:40 with count **3740** and held
  that value for ~10 min — then jumped to **5430** once the 18:00 window appeared.
- The **18:00** window appeared at 17:50 UTC — **10 minutes before** its own label time.
- **17:30 (6635)** and **17:15 (5793)** were stable across every reading.

## What this means

1. A window becomes visible in BQ **5–10 minutes before** its `MentionTimeDate` label.
2. When it first appears its count is **partial**; GDELT tops it up over the next few
   minutes (17:45: 3740 → 5430, a **~31% undercount** at first sight).
3. A window is **complete exactly once a newer window exists.** Every window that already
   had a successor (17:30, 17:15) was stable; only the current newest one was still moving.

## Decision

**Do NOT ingest `MentionTimeDate = MAX(...)`** — the newest window is the one still being
filled. Ingest the **second-newest** window instead (the newest one that already has a
successor, therefore settled):

```sql
WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
  AND MentionTimeDate = (
      SELECT DISTINCT MentionTimeDate
      FROM `gdelt-bq.gdeltv2.eventmentions_partitioned`
      WHERE _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
      ORDER BY MentionTimeDate DESC
      LIMIT 1 OFFSET 1        -- skip the still-filling newest window
  )
  AND Confidence > 60
```

Cost: ~15 min extra staleness (we always trail by one window), in exchange for a
**complete, stable** article count. Ties in with the "run in the second half of the
window" cron note in `fetch_and_upload.py` — both target settled data.

_Related: this also keeps the `GROUP BY GlobalEventID` grain correct, since exactly one
window is in scope per run._
