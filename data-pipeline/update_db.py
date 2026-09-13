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
        raise ValueError(f"Can not read {file_name} - {e}")

    return query

def load_env_vars():

    load_dotenv()

    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        raise ValueError("DATABASE_URL was not found. Check file .env")

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
                cur.executemany(
                    query=write_query, 
                    params_seq=rows
                )
    except Exception as e:
        raise ValueError(f"Problem in update_articles_table_15min() - {e}")

def update_top_events_table(db_url):
    # refresh the top_events leaderboard from articles_table_15_min.
    # Everything happens inside Postgres via refresh_top_events.sql (reset + upsert),

    try:
        with psycopg.connect(db_url) as conn:
            conn.execute(
                query=get_query_from_sql_file("refresh_top_events.sql")
            )
    except Exception as e:
        raise ValueError(f"Problem in update_top_events_table() - {e}")

def add_slugs(db_url, bq_client):

    try:
        with psycopg.connect(db_url) as conn:
            result = conn.execute(
                query=get_query_from_sql_file("events_without_slugs.sql")
            )
            event_ids_without_urls = [i[0] for i in result.fetchall()]
    except Exception as e:
        raise ValueError(f"add_slugs() getting global_event_id - {e}")

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

    try:
        with psycopg.connect(db_url) as conn:
            with conn.cursor() as cur:
                cur.executemany(
                    query=get_query_from_sql_file("upload_slugs.sql"),
                    params_seq=params
                )
    except Exception as e:
        raise ValueError(f"Can not upload URLs to top_events table - {e}")
    
def add_ai_summary(db_url):

    try:
        with psycopg.connect(
                db_url,
                row_factory=dict_row # output format is [{col_1 : val, col_2 : val ,...}, same for other events...]
            ) as conn:
            result = conn.execute(
                query=get_query_from_sql_file("data_for_summary.sql")
            )
            top_events_without_ai_summary_data = result.fetchall()
    except Exception as e:
        raise ValueError(f"add_ai_summary() getting top_events data - {e}")

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

    try:
        with psycopg.connect(db_url) as conn:
            with conn.cursor() as cur:
                cur.executemany(
                    query=get_query_from_sql_file("upload_summaries.sql"),
                    params_seq=params
                )
    except Exception as e:
        raise ValueError(f"Can not upload AI summaries to top_events table - {e}")

def delete_old_rows_table_15min(db_url):

    try:
        with psycopg.connect(db_url) as conn:
            conn.execute(
                query=get_query_from_sql_file("delete_old_rows.sql")
            )
    except Exception as e:
        raise ValueError(f"Problem in delete_old_rows_table_15min() - {e}")


if __name__ == "__main__":
    print(datetime.datetime.now(), "*** STARTING update_db.py ***")

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
