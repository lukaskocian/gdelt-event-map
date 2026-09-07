# SCHEDULING (GitHub Actions cron):
# see docs/research/window_completeness.md before setting GH Actions

import os
from dotenv import load_dotenv
from google.cloud import bigquery
import datetime
import psycopg

def load_env_vars():

    load_dotenv()

    google_credentials = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    db_url = os.getenv("DATABASE_URL")

    if not google_credentials:
        print("Error: GOOGLE_APPLICATION_CREDENTIALS was not found. Check file .env")
        raise

    if not db_url:
        print("Error: DATABASE_URL was not found. Check file .env")
        raise

    return google_credentials, db_url


def update_articles_table_15min(google_credentials, db_url):

    client = bigquery.Client(credentials=google_credentials)

    sql_path = os.path.join(os.path.dirname(__file__), "sql", "gdelt_ingest.sql")
    try:
        with open(sql_path, "r", encoding='utf-8') as file:
            read_query = file.read()
    except Exception as e:
        print(f"Error: can not read gdelt_ingest.sql - {e}")
        raise

    # limit query to max 1GB
    job_config = bigquery.QueryJobConfig(
        maximum_bytes_billed=10**9
    )

    query_job = client.query(query=read_query, job_config=job_config)
    results = query_job.result()
    rows = [dict(row) for row in results]

    print(f"{datetime.datetime.now()} BQ Billed: {query_job.total_bytes_billed / 10**6:.2f} MB")

    if not rows:
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

    sql_path = os.path.join(os.path.dirname(__file__), "sql", "refresh_top_events.sql")
    try:
        with open(sql_path, "r", encoding="utf-8") as file:
            query = file.read()
    except Exception as e:
        print(f"Error: Can not load refresh_top_events.sql - {e}")
        raise

    try:
        with psycopg.connect(db_url) as conn:
            conn.execute(query)
    except Exception as e:
        print(f"Error: Problem in update_top_events_table() - {e}")
        raise


if __name__ == "__main__":
    print(datetime.datetime.now(), "*** STARTING fetch_and_upload.py ***")

    google_credentials, db_url = load_env_vars()

    update_articles_table_15min(google_credentials, db_url) # bigquery -> python -> Neon articles_table_15_min
    update_top_events_table(db_url) # all in PostgreSQL (Neon) between tables top_events and articles_table_15_min
    # add URLs and AI summary: Neon top_events -> python -> bigquery get links -> python filter links -> LLM API -> Neon fill URL and summary data
    # delete old rows from articles table 15 min
    print(datetime.datetime.now(), "*** SUCCESS ***")
