-- File Name: stream_info.sql
-- Purpose: PostgreSQL Show logical replication stream info
-- Created: 20260516  by  huangtingzhong

SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_is_wal_replay_paused();
SELECT
  CASE WHEN NOT pg_is_in_recovery() THEN 0
  WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
  ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())
  END AS replication_lag;
\x on
SELECT * FROM pg_stat_wal_receiver;
\x
