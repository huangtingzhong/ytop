-- File Name: we.sql
-- Purpose: PostgreSQL Session wait and SQL overview
-- Created: 20260418  by  huangtingzhong

SELECT
    pid::text AS sid,
    SUBSTR(COALESCE(wait_event, state, ''), 1, 30) AS event,
    usename AS username,
    SUBSTR(COALESCE(query, ''), 1, 18) AS sql_text,
    CASE
        WHEN EXTRACT(EPOCH FROM (now() - query_start)) < 1
            THEN ROUND(EXTRACT(EPOCH FROM (now() - query_start)) * 1000) || 'MS'
        WHEN EXTRACT(EPOCH FROM (now() - query_start)) < 1000
            THEN ROUND(EXTRACT(EPOCH FROM (now() - query_start))::numeric, 2) || 'S'
        ELSE ROUND((EXTRACT(EPOCH FROM (now() - query_start)) / 1000)::numeric, 2) || 'KS'
    END AS exec_time,
    SUBSTR(COALESCE(application_name, ''), 1, 30) AS program,
    SUBSTR(COALESCE(client_addr::text, ''), 1, 20) AS client
FROM pg_stat_activity
WHERE state <> 'idle'
  AND pid <> pg_backend_pid()
ORDER BY query_start ASC;

-- Sessions with same query (potential contention)
SELECT
    SUBSTR(COALESCE(query, ''), 1, 60) AS sql_text,
    wait_event AS wait_event,
    COUNT(*) AS hcount
FROM pg_stat_activity
WHERE state <> 'idle'
  AND pid <> pg_backend_pid()
  AND query IS NOT NULL
GROUP BY query, wait_event
HAVING COUNT(*) > 1
ORDER BY hcount DESC;
