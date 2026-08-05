-- Gets top 200 events of last 15 min from GDELT
-- note: renames from pascal case to snake case are because of compatibility with PostgreSQL DB in Neon

WITH Top200Events AS (

    -- there can be more rows concerning one event and ONE ARTICLE in eventmentions_partitioned, therefore we use DISTINCT MentionIdentifier
    SELECT
        GlobalEventID                     AS global_event_id,
        COUNT(DISTINCT MentionIdentifier) AS articles_count,
        
        -- MentionTimeDate is INT YYYYMMDDHHMMSS -> PARSE_TIMESTAMP to a UTC TIMESTAMP
        PARSE_TIMESTAMP('%Y%m%d%H%M%S', CAST(MAX(MentionTimeDate) AS STRING)) AS time_window_15min
    FROM
        `gdelt-bq.gdeltv2.eventmentions_partitioned`
    WHERE
        _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
        AND MentionTimeDate >= CAST(FORMAT_TIMESTAMP('%Y%m%d%H%M%S', TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 15 MINUTE)) AS INT64)
        AND Confidence > 60
    GROUP BY
        GlobalEventID
    ORDER BY
        articles_count DESC
    LIMIT 200
)

SELECT
    t.global_event_id,
    t.articles_count,
    t.time_window_15min,

    PARSE_TIMESTAMP('%Y%m%d%H%M%S', CAST(e.DateAdded AS STRING)) AS date_added,  -- INT YYYYMMDDHHMMSS -> TIMESTAMP (UTC)
    e.AvgTone               AS avg_tone,
    e.GoldsteinScale        AS goldstein_scale,
    e.SourceURL             AS source_url,       -- first URL that mentioned the event
    e.EventCode             AS event_code,

    e.ActionGeo_FullName    AS action_geo_full_name,
    e.ActionGeo_Type        AS action_geo_type,
    e.ActionGeo_CountryCode AS action_geo_country_code,
    e.ActionGeo_Lat         AS action_geo_lat,
    e.ActionGeo_Long        AS action_geo_long,

    e.Actor1Name            AS actor1_name,
    e.Actor1Geo_FullName    AS actor1_geo_full_name,
    e.Actor1CountryCode     AS actor1_country_code,

    e.Actor2Name            AS actor2_name,
    e.Actor2Geo_FullName    AS actor2_geo_full_name,
    e.Actor2CountryCode     AS actor2_country_code

FROM
    Top200Events t
    JOIN `gdelt-bq.gdeltv2.events_partitioned` e ON t.global_event_id = e.GlobalEventID
WHERE
    -- see docs/research for why we join Top200Events with events iniclized during last 24 h in GDELT event table
    e._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND e.ActionGeo_CountryCode IS NOT NULL -- because this project is a map