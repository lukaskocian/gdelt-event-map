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

if __name__ == "__main__":
    update_articles_table_15min()
