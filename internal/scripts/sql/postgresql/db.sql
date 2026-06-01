-- File Name: db.sql
-- Purpose: PostgreSQL Show database open mode and log status
-- Created: 20260516  by  huangtingzhong

SELECT 
    current_database() as database,
    current_user as user,
    CASE WHEN pg_is_in_recovery() THEN 'STANDBY' ELSE 'PRIMARY' END as role,
    version() as version,
    pg_size_pretty(pg_database_size(current_database())) as db_size,
    (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
    CASE 
        WHEN pg_is_in_recovery() THEN
            COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int, 0)
        ELSE 0
    END as replication_lag_seconds;
