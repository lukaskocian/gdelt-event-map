-- QUERY FOR FINDING OUT NORM. COEFS FOR COUNTRIES (norm coef will be max 5 and min 0.2)
-- this query is based on ingest_gdelt.sql query for most of its part


CREATE TEMP FUNCTION URL_DECODE(url STRING)
RETURNS STRING
LANGUAGE js AS """
  try {
    return decodeURI(url);
  } catch (e) {
    return url;
  }
""";


WITH events AS (

    -- there can be more rows concerning one event and ONE ARTICLE in eventmentions_partitioned, therefore we use DISTINCT MentionIdentifier
    SELECT
        GlobalEventID AS global_event_id,

        -- deduplication using not whole URL (MentionIdentifier) but URL slug
        COUNT(DISTINCT IFNULL(
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
            ),
          MentionIdentifier
        )) AS articles_count

    FROM
        `gdelt-bq.gdeltv2.eventmentions_partitioned`
    WHERE
        -- the sample to calcualte from is 4 days for every year for past 10 years
        _PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 10 YEAR)
        AND EXTRACT(DAY FROM _PARTITIONDATE) = 23
        AND EXTRACT(MONTH FROM _PARTITIONDATE) IN (1, 4, 7, 10)

        AND Confidence > 60
    GROUP BY
        GlobalEventID

), events_with_country_name AS (

  SELECT
      t.global_event_id,
      t.articles_count,
      e.ActionGeo_CountryCode AS action_geo_country_code
  FROM
      events t
      JOIN `gdelt-bq.gdeltv2.events_partitioned` e ON t.global_event_id = e.GlobalEventID
  WHERE
      -- the sample to calcualte from is 4 days for every year for past 10 years
      e._PARTITIONDATE >= DATE_SUB(CURRENT_DATE(), INTERVAL 10 YEAR)
      AND EXTRACT(DAY FROM e._PARTITIONDATE) = 23
      AND EXTRACT(MONTH FROM e._PARTITIONDATE) IN (1, 4, 7, 10)

      AND e.ActionGeo_CountryCode IS NOT NULL
      AND e.GoldsteinScale IS NOT NULL -- because we calculate relevance based on goldstein scale

), articles_sum_per_country AS (

  SELECT
    action_geo_country_code,
    sum(articles_count) AS articles_sum
  FROM
    events_with_country_name
  GROUP BY
    action_geo_country_code

), population_of_countries AS (

  SELECT
    country_name,
    country_code,
    midyear_population AS population
  FROM
    `bigquery-public-data.census_bureau_international.midyear_population`
  WHERE
    year = 2026
)

SELECT
  p.country_name,
  p.country_code,
  p.population,
  a.articles_sum,
  COALESCE(
    GREATEST(0.2, LEAST(5.0, 
      (
        (population/articles_sum) * 
        ((SELECT SUM(articles_sum) FROM articles_sum_per_country) / (SELECT SUM(population) FROM population_of_countries))
    ))), 
  1.0) AS normalizing_coef
FROM
  articles_sum_per_country a
JOIN
  population_of_countries p ON a.action_geo_country_code = p.country_code
WHERE
  a.action_geo_country_code NOT IN 
  ('OS', 'AY' -- OS (Oceans), AY (Antarctica) are not countries
  , 'GP', 'RE', 'MB', 'MF', 'FG', 'SV', 'JN', 'VT', -- deleting small territories for simplicity
  'YI', -- deleting nonexisting country (Yugoslavia)
  'RB' -- old code for Serbia
  )
