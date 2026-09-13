DELETE FROM
    articles_table_15_min
WHERE
    time_window_15min < NOW() - INTERVAL '1 week'