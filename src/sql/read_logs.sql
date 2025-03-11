SELECT
    strftime('%F %R:00', timestamp, 'unixepoch') as minute,
    count(*),
    avg(duration), min(duration), max(duration),
    avg(byte_size), min(byte_size), max(byte_size),
    sum(tokens)
FROM logs
WHERE timestamp > ?
GROUP BY minute;
