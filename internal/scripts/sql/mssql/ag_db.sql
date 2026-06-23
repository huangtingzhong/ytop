-- File Name: ag_db.sql
-- Purpose: MSSQL AG database sync status
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag_db.sql -w 300 -W
-- MinVersion: 2012 (Always On)
-- Variables:
--   &ag_name  AG name (empty = all)
--   &dbname  database name (empty = all)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Get-DbaAgDatabase
--
SET NOCOUNT ON;

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) <> 1
BEGIN
    PRINT 'Always On not enabled on this instance (requires 2012+ Enterprise)';
    RETURN;
END

-- COL: ag a15 db a20 replica a22 role a10 sync a12 suspend a6 joined a6 (~280)
DECLARE @ag_filter SYSNAME, @db_filter SYSNAME;
SET @ag_filter = NULLIF(RTRIM('&ag_name'), '');
SET @db_filter = NULLIF(RTRIM('&dbname'), '');

PRINT '---------- ag databases ----------';
EXEC sp_executesql N'
SELECT LEFT(ag.name, 15) AS ag,
       LEFT(DB_NAME(drs.database_id), 20) AS dbname,
       LEFT(ar.replica_server_name, 22) AS replica,
       LEFT(rs.role_desc, 10) AS role,
       LEFT(drs.synchronization_state_desc, 12) AS sync,
       CASE WHEN drs.is_suspended = 1 THEN ''YES'' ELSE ''NO'' END AS suspended,
       CASE WHEN drs.is_database_joined = 1 THEN ''YES'' ELSE ''NO'' END AS joined
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states rs ON ar.replica_id = rs.replica_id
JOIN sys.dm_hadr_database_replica_states drs ON ar.replica_id = drs.replica_id
WHERE (@ag = '''' OR ag.name = @ag)
  AND (@db = '''' OR DB_NAME(drs.database_id) = @db)
ORDER BY ag.name, DB_NAME(drs.database_id), ar.replica_server_name',
    N'@ag SYSNAME, @db SYSNAME',
    @ag = @ag_filter,
    @db = @db_filter;
