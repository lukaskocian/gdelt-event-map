WITH raw_slugs AS (
  SELECT 
    GLOBALEVENTID,
    Confidence,
    SentenceID,

    NULLIF(
      TRIM(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            LOWER(REGEXP_EXTRACT(MentionIdentifier, r'([^/?#]+)/?(?:[?#].*)?$')),
            r'\.(html?|php|aspx)$', ''),
          r'[^a-z]+', '-'),
        '-'),
      '')
    AS slug

  FROM 
    `gdelt-bq.gdeltv2.eventmentions_partitioned`
  WHERE 
    _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
    AND Confidence > 60
    AND GLOBALEVENTID IN UNNEST(@event_ids) -- UNNEST makes the inputed array a table
),

no_empty_slugs_and_duplicates AS (
  SELECT
    GLOBALEVENTID,
    slug,
    MAX(Confidence) AS Confidence,
    MIN(SentenceID) AS SentenceID
  FROM
    raw_slugs
  WHERE
    slug IS NOT NULL
  GROUP BY -- deduplication
    GLOBALEVENTID, slug
),

slug_importance_added AS (
    SELECT
        GLOBALEVENTID,
        slug,
        ROW_NUMBER() OVER(
            PARTITION BY GLOBALEVENTID
            ORDER BY SentenceID ASC, Confidence DESC
        ) AS slug_importance -- most important has number 1
    FROM
        no_empty_slugs_and_duplicates
)

SELECT
    GLOBALEVENTID,
    STRING_AGG(slug, ', ') AS best_slugs
FROM
   slug_importance_added
WHERE
    slug_importance <= 10
GROUP BY
    GLOBALEVENTID


