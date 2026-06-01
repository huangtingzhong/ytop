-- File Name: we_index.sql
-- Purpose: PostgreSQL We Index
-- Created: 20260516  by  huangtingzhong

SELECT
    p.datid::regclass AS dbname,
    p.index_relid::regclass AS indexname,
    p.relid::regclass AS tablename,
    p.phase,
    p.lockers_total || ':' || p.lockers_done AS locker_total_done,
    p.blocks_total || ':' || p.blocks_done AS block_total_done,
    p.tuples_total || ':' || p.tuples_done AS tuple_total_done,
    round(100.0 * p.tuples_done / nullif(p.tuples_total, 0), 2) AS "% Complete",
    a.usename,
    a.client_addr,
    EXTRACT(EPOCH FROM now() - a.backend_start) AS runtime_s,
    a.state,
    a.wait_event,
    a.query
FROM
    pg_stat_progress_create_index p
JOIN
    pg_stat_activity a
ON
  a.pid = p.pid OR p.pid = a.leader_pid;
