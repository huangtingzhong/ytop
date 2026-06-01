-- File Name: stream_off.sql
-- Purpose: PostgreSQL Disable logical replication stream
-- Created: 20260516  by  huangtingzhong

SELECT pg_wal_replay_pause();
SELECT pg_is_wal_replay_paused();
