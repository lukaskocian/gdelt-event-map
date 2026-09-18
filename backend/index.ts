import {sql} from "bun";
import {Elysia} from "elysia";
import { cors } from "@elysia/cors";

let time_cache_updated : number | null = null;
let cached_data : any;

// shared function - for users | for /db_health endpoint (for Google Cloud CRON JOB)
const get_db_health = async () => {

    // last window
    const db_health = await sql`

        SELECT
            MAX(time_window_15min) AS latest_15min_window,
            EXTRACT( EPOCH FROM (NOW() - MAX(time_window_15min)) ) / 60 AS lag_minutes,
            COUNT(DISTINCT time_window_15min) FILTER (WHERE time_window_15min > NOW() - INTERVAL '1 day')
        FROM
            articles_table_15_min
    `

    return db_health[0]
}

const get_data_from_db = async () => {

    const events = await sql`

        WITH week_top_10 AS (
            SELECT
                global_event_id
            FROM
                top_events
            ORDER BY
                relevance_1w DESC
            LIMIT 10
        ),
        
        day_top_10 AS (
            SELECT
                global_event_id
            FROM
                top_events
            ORDER BY
                relevance_1d DESC
            LIMIT 10
        ),
        
        hour_top_10 AS (
            SELECT
                global_event_id
            FROM
                top_events
            ORDER BY
                relevance_1h DESC
            LIMIT 10
        ),

        relevant_event_ids AS (
            SELECT global_event_id FROM week_top_10
            UNION 
            SELECT global_event_id FROM hour_top_10
            UNION
            SELECT global_event_id FROM day_top_10
        )

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
            ai_summary,
            ai_evidence_quality,
            avg_tone,
            articles_1h,
            articles_1d,
            articles_1w,
            relevance_1h,
            relevance_1d,
            relevance_1w
        FROM
            top_events
        JOIN
            relevant_event_ids USING (global_event_id)
        LEFT JOIN
            event_cameo_codes USING (event_code)
    `;
    
    const db_health = await get_db_health();

    const result = {
        events : events,
        health : db_health
    }

    return result;
}

const get_data = () => {

    if (time_cache_updated == null || ((Date.now() - time_cache_updated) / 1000) > 60)  
    {
        // update cached data
        cached_data = get_data_from_db();
        time_cache_updated = Date.now();
    }

    return cached_data
}

const app = new Elysia()
                .use(cors())
                .get("/", () => get_data())
                .get("/db_health", () => get_db_health())
                .get("/backend_health", () => {})
                .listen(process.env.PORT ?? 3000);

console.log(
  `🦊 Elysia is running at ${app.server?.hostname}:${app.server?.port}`
);