-- File Name: checkpoint.sql
-- Purpose: PostgreSQL Show checkpoint progress information
-- Created: 20260516  by  huangtingzhong

-- SELECT 
--     (pg_control_checkpoint()).checkpoint_lsn AS checkpoint_lsn,
--     (pg_control_checkpoint()).redo_lsn AS redo_lsn,
--     (pg_control_checkpoint()).redo_wal_file AS redo_wal_file,
--     (pg_control_checkpoint()).timeline_id AS timeline_id,
--     (pg_control_checkpoint()).prev_timeline_id AS prev_timeline_id,
--     (pg_control_checkpoint()).full_page_writes AS full_page_writes,
--     (pg_control_checkpoint()).next_xid AS next_xid,
--     (pg_control_checkpoint()).next_oid AS next_oid,
--     (pg_control_checkpoint()).next_multixact_id AS next_multixact_id,
--     (pg_control_checkpoint()).next_multi_offset AS next_multi_offset,
--     (pg_control_checkpoint()).oldest_xid AS oldest_xid,
--     (pg_control_checkpoint()).oldest_xid_dbid AS oldest_xid_dbid,
--     (pg_control_checkpoint()).oldest_active_xid AS oldest_active_xid,
--     (pg_control_checkpoint()).oldest_multi_xid AS oldest_multi_xid,
--     (pg_control_checkpoint()).oldest_multi_dbid AS oldest_multi_dbid,
--     (pg_control_checkpoint()).oldest_commit_ts_xid AS oldest_commit_ts_xid,
--     (pg_control_checkpoint()).newest_commit_ts_xid AS newest_commit_ts_xid,
--     (pg_control_checkpoint()).checkpoint_time AS checkpoint_time;

\x on
select cc.* from pg_control_checkpoint() as cc;
\x off
