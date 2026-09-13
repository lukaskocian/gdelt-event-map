# SCHEDULING (GitHub Actions cron):
# see docs/research/window_completeness.md before setting GH Actions

import os
from dotenv import load_dotenv
from google.cloud import bigquery
import datetime
import psycopg
from psycopg.types.json import Jsonb
from psycopg.rows import dict_row
import json

from gemini_summary_maker import get_summary

def get_query_from_sql_file(file_name):

    if not file_name.endswith(".sql"):
        raise ValueError(f"Invalid file type: '{file_name}'. The file must end with .sql")

    try:
        sql_path_get_slugs = os.path.join(os.path.dirname(__file__), "sql", file_name)
        with open(sql_path_get_slugs, "r", encoding="utf-8") as file:
            query = file.read()
    except Exception as e:
        print(f"Error: can not read {file_name} - {e}")
        raise

    return query

def load_env_vars():

    load_dotenv()

    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        print("Error: DATABASE_URL was not found. Check file .env")
        raise

    bq_client = bigquery.Client() #finds api key by itself

    return db_url, bq_client

def update_articles_table_15min(db_url, bq_client):

    # limit query to max 1GB
    job_config = bigquery.QueryJobConfig(
        maximum_bytes_billed=10**9
    )

    query_job = bq_client.query(
        query = get_query_from_sql_file("gdelt_ingest.sql"), 
        job_config = job_config
    )

    results = query_job.result()
    rows = [dict(row) for row in results]

    print(f"{datetime.datetime.now()} gdelt_ingest.sql BQ Billed: {query_job.total_bytes_billed / 10**6:.2f} MB")

    if len(rows) == 0:
        print("There are no new articles.")
        return

    columns = list(rows[0].keys())
    sequence_s = ", ".join([f"%({col})s" for col in columns]) # %(col_name1)s, %(col_name2)s, ...
    sequence_excluded = ", ".join([f"{col} = EXCLUDED.{col}" for col in columns]) # col1 = EXCLUDED.col1, col2 = EXCLUDED.col2, ...

    # note: Changing column order in gdelt_ingest.sql won't break the insert,
    #       because we use named parameters (see sequence_s).
    write_query = f"""
            INSERT INTO articles_table_15_min ({", ".join(columns)})
            VALUES ({sequence_s})
            ON CONFLICT (global_event_id, time_window_15min)
            DO UPDATE SET {sequence_excluded}
    """
    try:
        with psycopg.connect(db_url) as conn:
            with conn.cursor() as cur:
                cur.executemany(write_query, rows)
    except Exception as e:
        print(f"Error: Problem in update_articles_table_15min() - {e}")
        raise

def update_top_events_table(db_url):
    # refresh the top_events leaderboard from articles_table_15_min.
    # Everything happens inside Postgres via refresh_top_events.sql (reset + upsert),

    try:
        with psycopg.connect(db_url) as conn:
            conn.execute(
                get_query_from_sql_file("refresh_top_events.sql")
            )
    except Exception as e:
        print(f"Error: Problem in update_top_events_table() - {e}")
        raise

def add_slugs(db_url, bq_client):

    query = """
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
    """

    try:
        with psycopg.connect(db_url) as conn:
            result = conn.execute(query)
            event_ids_without_urls = [i[0] for i in result.fetchall()]
    except Exception as e:
        print(f"ERROR: add_slugs() getting global_event_id - {e}")
        raise

    if len(event_ids_without_urls) == 0:
        print("All top events have their URLs.")
        return

    get_slugs_query = get_query_from_sql_file("get_slugs.sql")

    # limit query to max 1GB, add query parms
    job_config = bigquery.QueryJobConfig(
        maximum_bytes_billed=10**9,
        query_parameters=[
            bigquery.ArrayQueryParameter(
                name = "event_ids",
                array_type = "INT64",
                values = event_ids_without_urls
            )
        ]
    )

    query_job = bq_client.query(query=get_slugs_query, job_config=job_config)
    results = query_job.result()
    print(f"{datetime.datetime.now()} get_slugs.sql BQ Billed: {query_job.total_bytes_billed / 10**6:.2f} MB")

    params = [
        {
            "global_event_id": row["global_event_id"],
            "best_slugs": Jsonb([dict(slug) for slug in row["best_slugs"]]),
        }
        for row in results
    ]

    if len(params) == 0:
        print("BigQuery returned no slugs")
        return

    upload_slugs_query = f"""

        UPDATE top_events 
        SET best_urls_json = %(best_slugs)s
        WHERE global_event_id = %(global_event_id)s

    """

    try:
        with psycopg.connect(db_url) as conn:
            with conn.cursor() as cur:
                cur.executemany(upload_slugs_query, params)
    except Exception as e:
        print(f"ERROR: Can not upload URLs to top_events table - {e}")
        raise
    
def add_ai_summary(db_url):

    query = """
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
    """

    try:
        with psycopg.connect(
                db_url,
                row_factory=dict_row # output format is [{col_1 : val, col_2 : val ,...}, same for other events...]
            ) as conn:
            result = conn.execute(query)
            top_events_without_ai_summary_data = result.fetchall()
    except Exception as e:
        print(f"ERROR: add_ai_summary() getting top_events data - {e}")
        raise

    if len(top_events_without_ai_summary_data) == 0:
        print("All top events have their AI Summary")
        return

    summaries_json = get_summary(top_events_without_ai_summary_data)
    summaries = json.loads(summaries_json)["sumlist"]

    params = [
        {
            "global_event_id": summary["global_event_id"],
            "ai_summary": summary["ai_summary"],
            "ai_evidence_quality": summary["ai_evidence_quality"],
        }
        for summary in summaries
    ]

    if len(params) == 0:
        print("Gemini returned no summaries")
        return

    upload_summaries_query = """

        UPDATE top_events
        SET ai_summary = %(ai_summary)s,
            ai_evidence_quality = %(ai_evidence_quality)s
        WHERE global_event_id = %(global_event_id)s

    """

    try:
        with psycopg.connect(db_url) as conn:
            with conn.cursor() as cur:
                cur.executemany(upload_summaries_query, params)
    except Exception as e:
        print(f"ERROR: Can not upload AI summaries to top_events table - {e}")
        raise

def delete_old_rows_table_15min(db_url):

    query = """
        DELETE FROM
            articles_table_15_min
        WHERE
            time_window_15min < NOW() - INTERVAL '1 week';
    """

    try:
        with psycopg.connect(db_url) as conn:
            conn.execute(query)
    except Exception as e:
        print(f"Error: Problem in delete_old_rows_table_15min() - {e}")
        raise


if __name__ == "__main__":
    print(datetime.datetime.now(), "*** STARTING fetch_and_upload.py ***")

    db_url, bq_client = load_env_vars()

    # bigquery -> python -> Neon articles_table_15_min
    update_articles_table_15min(db_url, bq_client)

    # all in PostgreSQL (Neon) between tables top_events and articles_table_15_min
    update_top_events_table(db_url)

    # after a week rows from articles_table_15_min are deleted
    delete_old_rows_table_15min(db_url)

    # top_events event ids -> python -> bigquery find URLs + extract slugs -> python -> add slugs to top_events
    add_slugs(db_url, bq_client)

    # top_events -> python -> Gemini API -> python -> top_events
    add_ai_summary(db_url)

    print(datetime.datetime.now(), "*** SUCCESS ***")
