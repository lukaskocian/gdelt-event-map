CREATE TEMP FUNCTION URL_DECODE(url STRING)
RETURNS STRING
LANGUAGE js AS """
  try {
    return decodeURI(url);
  } catch (e) {
    return url;
  }
""";


WITH raw_slugs AS (
  SELECT 
    GLOBALEVENTID,
    Confidence,
    SentenceID,
    MentionIdentifier,

  (
    -- we split the URL into several parts by /
    SELECT
        url_part
    FROM 
        UNNEST(
            SPLIT(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        URL_DECODE(MentionIdentifier),
                    r'[?#].*', ''), -- delete the url query/section part
                r'\.(html|htm|php|aspx|cms)$', ''), 
            '/')
        ) AS url_part
    WHERE 
        LENGTH(url_part) > 8
        AND REGEXP_CONTAINS(url_part, r'\p{L}') -- the part contains world character of any language
        AND NOT REGEXP_CONTAINS(url_part, r'^www') -- the part is not domain
    ORDER BY LENGTH(url_part) DESC
    LIMIT 1 -- if there are no url parts left => NULL

  ) AS slug

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
    MIN(SentenceID) AS SentenceID,
    MAX(MentionIdentifier) AS MentionIdentifier
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
        MentionIdentifier,
        ROW_NUMBER() OVER(
            PARTITION BY GLOBALEVENTID
            ORDER BY SentenceID ASC, Confidence DESC
        ) AS slug_importance -- most important has number 1
    FROM
        no_empty_slugs_and_duplicates
)

SELECT
    GLOBALEVENTID,
    ARRAY_AGG(
        STRUCT(
            slug,
            MentionIdentifier AS original_url
        )
        ORDER BY slug_importance ASC
    ) AS best_slugs
FROM
   slug_importance_added
WHERE
    slug_importance <= 10
GROUP BY
    GLOBALEVENTID


