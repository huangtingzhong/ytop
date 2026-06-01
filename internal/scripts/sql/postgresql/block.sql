-- File Name: block.sql
-- Purpose: PostgreSQL Block
-- Created: 20260516  by  huangtingzhong

WITH sos AS (
    SELECT array_cat(array_agg(pid),
           array_agg((pg_blocking_pids(pid))[array_length(pg_blocking_pids(pid), 1)])) pids
    FROM pg_locks
    WHERE NOT granted
)
SELECT a.pid, a.usename, a.datname, a.state,
       a.wait_event_type || ': ' || a.wait_event AS wait_event,
 --      current_timestamp-a.state_change time_in_state,
 --      current_timestamp-a.xact_start time_in_xact,
       abs(round(EXTRACT(EPOCH FROM (now() - NULLIF(state_change, now()))))) AS time_state_s,
        abs(round(EXTRACT(EPOCH FROM (now() - NULLIF(xact_start, now()))))) AS time_xact_s,
       CASE
        WHEN l.locktype = 'relation' THEN l.relation::regclass::text
        WHEN l.locktype = 'tuple' THEN l.relation::regclass::text || ' page:' || l.page || ' tuple:' || l.tuple
        WHEN l.locktype = 'page' THEN l.relation::regclass::text || ' page:' || l.page
        ELSE l.locktype
    END AS locked_object,
       l.locktype,l.mode, l.page||'.'||l.tuple h_p_t,l1.relation::regclass::text||':'||l1.page||':'||l1.tuple w_p_t,
       pg_blocking_pids(l.pid) blocking_pids,
       (pg_blocking_pids(l.pid))[array_length(pg_blocking_pids(l.pid), 1)] last_session,
       coalesce((pg_blocking_pids(l.pid))[1] || '.' ||
                  coalesce(case when l.locktype = 'transactionid' then 1
                           else array_length(pg_blocking_pids(l.pid), 1) + 1 end,
                           0),
                a.pid || '.0') lock_depth,
       a.query
FROM pg_stat_activity a
     JOIN sos s on (a.pid = any(s.pids))
     LEFT OUTER JOIN pg_locks l on (a.pid = l.pid and not l.granted)
     LEFT join  pg_locks l1 on (l.pid=l1.pid and not l.granted and l1.granted and l1.locktype='tuple')
ORDER BY lock_depth;
