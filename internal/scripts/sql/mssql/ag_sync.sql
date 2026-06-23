-- File Name: ag_sync.sql
-- Purpose: MSSQL AG database sync health and queue depth
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag_sync.sql -w 300 -W
-- MinVersion: 2012 (Always On)
-- Variables:
--   &ag_name  AG name (empty = all)
--   &dbname  database name (empty = all)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Get-DbaAgDatabase
-- Oracle ref: arch_dest_status
--
SET NOCOUNT ON;

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) <> 1
BEGIN
    PRINT 'Always On not enabled (requires 2012+ Enterprise)';
    RETURN;
END

DECLARE @ag_filter SYSNAME, @db_filter SYSNAME;
SET @ag_filter = NULLIF(RTRIM('&ag_name'), '');
SET @db_filter = NULLIF(RTRIM('&dbname'), '');

PRINT '---------- ag database sync ----------';
EXEC sp_executesql N'
SELECT LEFT(ag.name, 15) AS ag, LEFT(DB_NAME(drs.database_id), 18) AS dbname,
       LEFT(ar.replica_server_name, 22) AS replica,
       LEFT(drs.synchronization_state_desc, 12) AS sync,
       CAST(drs.log_send_queue_size AS VARCHAR(8)) AS send_q_kb,
       CAST(drs.redo_queue_size AS VARCHAR(8)) AS redo_q_kb,
       CASE WHEN drs.is_suspended = 1 THEN ''YES'' ELSE ''NO'' END AS suspended
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
JOIN sys.availability_groups ag ON ar.group_id = ag.group_id
WHERE (@ag = '''' OR ag.name = @ag)
  AND (@db = '''' OR DB_NAME(drs.database_id) = @db)
ORDER BY ag.name, DB_NAME(drs.database_id), ar.replica_server_name',
    N'@ag SYSNAME, @db SYSNAME',
    @ag = @ag_filter,
    @db = @db_filter;
