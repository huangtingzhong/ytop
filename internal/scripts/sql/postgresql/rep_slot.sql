-- File Name: rep_slot.sql
-- Purpose: PostgreSQL Show replication slot status
-- Created: 20260516  by  huangtingzhong

SELECT 
    rs.slot_name,
    rs.slot_type,
    rs.database,
    rs.active,
    rs.active_pid,
    rs.restart_lsn,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), rs.restart_lsn)) AS lag_size,
    rs.wal_status,
    COALESCE(sr.application_name, 'N/A') AS name,
    COALESCE(sr.client_addr::text, 'N/A') AS client_ip,
    COALESCE(sr.usename, 'N/A') AS username,
    COALESCE(sr.state, 'N/A') AS state,
    COALESCE(sr.sync_state, 'N/A') AS sync_state,
    CASE
        WHEN sr.reply_time IS NOT NULL THEN to_char(sr.reply_time, 'MM-DD HH24:MI')
        ELSE 'N/A'
    END AS reply_time,
    CASE
        WHEN sr.pid IS NOT NULL THEN
            pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sr.flush_lsn))
        ELSE 'N/A'
    END AS flush_lag,
    CASE
        WHEN sr.pid IS NOT NULL THEN
            pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sr.replay_lsn))
        ELSE 'N/A'
    END AS replay_lag,
    CASE
        WHEN rs.xmin IS NOT NULL THEN
            CASE
                WHEN EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(rs.xmin))) >= 86400 THEN
                    EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(rs.xmin)))::int / 86400 || ' D'
                WHEN EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(rs.xmin))) >= 3600 THEN
                    EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(rs.xmin)))::int / 3600 || ' H'
                WHEN EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(rs.xmin))) >= 60 THEN
                    EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(rs.xmin)))::int / 60 || ' M'
                ELSE
                    EXTRACT(EPOCH FROM (now() - pg_xact_commit_timestamp(rs.xmin)))::int || ' S'
            END
        ELSE 'N/A'
    END AS xmin_age
FROM pg_replication_slots rs
LEFT JOIN pg_stat_replication sr ON rs.active_pid = sr.pid
ORDER BY rs.slot_name;
