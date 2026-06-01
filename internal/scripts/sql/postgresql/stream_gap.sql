-- File Name: stream_gap.sql
-- Purpose: PostgreSQL Show logical replication lag
-- Created: 20260516  by  huangtingzhong

select application_name,state,pg_current_wal_lsn() as current_wal,replay_lsn,replay_lag,
  pg_size_pretty((pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn))) as size
  from pg_stat_replication order by pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn) desc;


select pg_walfile_name(sent_Lsn) sent_wal,pg_walfile_name(write_Lsn) write_wal,pg_walfile_name(replay_Lsn) replay_wal,write_Lag,replay_lag from pg_stat_replication;
