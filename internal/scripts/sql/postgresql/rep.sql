-- File Name: rep.sql
-- Purpose: PostgreSQL Show PostgreSQL replication overview
-- Created: 20260516  by  huangtingzhong

SELECT 
    sr.pid,
    sr.application_name AS name,
    sr.client_addr::text AS client_ip,
    sr.usename AS username,
    sr.state,
    sr.sync_state||':'||sr.sync_priority AS sync_state,
    CASE
        WHEN sr.reply_time IS NOT NULL THEN to_char(sr.reply_time, 'MM-DD HH24:MI')
        ELSE 'N/A'
    END AS reply_time,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sr.flush_lsn)) AS flush_lag,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sr.replay_lsn)) AS replay_lag,
    sr.sent_lsn,
    sr.write_lsn,
    sr.flush_lsn,
    sr.replay_lsn,
    COALESCE(rs.slot_name, 'No Slot') AS slot_name,
    COALESCE(rs.slot_type, 'N/A') AS slot_type,
    COALESCE(rs.wal_status, 'N/A') AS wal_status,
    CASE
        WHEN rs.restart_lsn IS NOT NULL THEN
            pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), rs.restart_lsn))
        ELSE 'N/A'
    END AS slot_lag,
    CASE
        WHEN sr.backend_xmin IS NOT NULL THEN
            CASE
                WHEN EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(sr.backend_xmin))) >= 86400 THEN
                    EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(sr.backend_xmin)))::int / 86400 || ' D'
                WHEN EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(sr.backend_xmin))) >= 3600 THEN
                    EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(sr.backend_xmin)))::int / 3600 || ' H'
                WHEN EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(sr.backend_xmin))) >= 60 THEN
                    EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(sr.backend_xmin)))::int / 60 || ' M'
                ELSE
                    EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(sr.backend_xmin)))::int || ' S'
            END
        ELSE NULL
    END AS xmin_age
FROM pg_stat_replication sr
LEFT JOIN pg_replication_slots rs ON sr.pid = rs.active_pid
ORDER BY sr.application_name, sr.client_addr;
