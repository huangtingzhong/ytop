-- File Name: stream_on.sql
-- Purpose: PostgreSQL Enable logical replication stream
-- Created: 20260516  by  huangtingzhong

SELECT pg_wal_replay_resume();
SELECT pg_is_wal_replay_paused();
