# fetch_and_upload.py — GDELT -> BigQuery -> Neon ingest (pipeline step A).
#
# WHICH WINDOW WE INGEST:
# The query pins the SECOND-newest 15-min window (MentionTimeDate = MAX minus one slot),
# NOT the newest. Measured finding (docs/research/window_completeness.md): a window shows
# up in BigQuery 5-10 min BEFORE its label but with a PARTIAL count that GDELT keeps
# topping up; a window is complete only once a newer window exists. So the newest window
# is always still filling (~31% undercount) — we take the one behind it, which is settled.
#
# SCHEDULING (GitHub Actions cron):
# Because we ingest the already-settled second-newest window, the exact run time is NOT
# critical for completeness — just fire ~every 15 min (e.g. cron "10,25,40,55 * * * *").
# Known MVP limitation: each run ingests one window; if GDELT's cadence and the cron drift
# so that two windows pass between runs, one window is skipped. Real fix (V2): remember the
# last-ingested window and backfill any gap.

import os
from dotenv import load_dotenv
from google.cloud import bigquery
import datetime
import psycopg2
from psycopg2.extras import execute_values
from contextlib import closing

# loads vars from .env (including GOOGLE_APPLICATION_CREDENTIALS)
load_dotenv()

def update_articles_table_15min():
    if not os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
        print("Error: GOOGLE_APPLICATION_CREDENTIALS was not found. Check file .env")
        return

    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        print("Error: DATABASE_URL was not found. Check file .env")
        return

    try:
        client = bigquery.Client()
        
        sql_path = os.path.join(os.path.dirname(__file__), "sql", "gdelt_ingest.sql")
        with open(sql_path, 'r', encoding='utf-8') as file:
            query = file.read()
        
        print(datetime.datetime.now(), " Connection to BigQuery")

        # limit query to max 1GB
        job_config = bigquery.QueryJobConfig(
            maximum_bytes_billed=10**9
        )

        query_job = client.query(query, job_config=job_config)
        results = query_job.result()
        rows = [dict(row) for row in results]

        print(f"{datetime.datetime.now()} Connection successful. Billed: {query_job.total_bytes_billed / 10**6:.2f} MB")
        print("results:\n")
        print(rows)

        if not rows:
            return # there are no new data


        columns = list(rows[0].keys())
        cols_sql = ", ".join(columns)
        pk = ("global_event_id", "time_window_15min")
        set_sql = ", ".join(f"{c} = EXCLUDED.{c}" for c in columns if c not in pk)

        sql = f"""
            INSERT INTO articles_table_15_min ({cols_sql})
            VALUES %s
            ON CONFLICT (global_event_id, time_window_15min)
            DO UPDATE SET {set_sql}
        """

        values = [[r[c] for c in columns] for r in rows]

        with closing(psycopg2.connect(db_url)) as conn:
            with conn:
                with conn.cursor() as cur:
                    execute_values(cur, sql, values)   # one round-trip for all ~200 rows

        print(f"{datetime.datetime.now()} Upserted {len(rows)} rows into articles_table_15_min")

    except Exception as e:
        print(f"Error in fetch_and_upload.py\n{e}")
        raise


def update_top_events_table():
    # Pipeline step B: refresh the top_events leaderboard from articles_table_15_min.
    # Everything happens inside Postgres via refresh_top_events.sql (reset + upsert),
    # so no rows are shipped to Python. Runs on Neon, NOT BigQuery.
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        print("Error: DATABASE_URL was not found. Check file .env")
        return

    try:
        sql_path = os.path.join(os.path.dirname(__file__), "sql", "refresh_top_events.sql")
        with open(sql_path, "r", encoding="utf-8") as file:
            query = file.read()   # holds BOTH statements: reset UPDATE + INSERT...ON CONFLICT

        print(datetime.datetime.now(), " Refreshing top_events on Neon")

        with closing(psycopg2.connect(db_url)) as conn:
            with conn:                     # one transaction: reset + upsert are atomic
                with conn.cursor() as cur:
                    cur.execute(query)     # no params -> both statements run in one round-trip
                    affected = cur.rowcount

        print(f"{datetime.datetime.now()} top_events refreshed (last statement affected {affected} rows)")

    except Exception as e:
        print(f"Error in update_top_events_table\n{e}")
        raise

if __name__ == "__main__":
    update_articles_table_15min()   # step A: ingest fact rows
    update_top_events_table()       # step B: recompute the leaderboard
