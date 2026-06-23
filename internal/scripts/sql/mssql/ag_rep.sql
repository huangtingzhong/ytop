-- File Name: ag_rep.sql
-- Purpose: MSSQL AG replica status
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag_rep.sql -w 300 -W
-- MinVersion: 2012 (Always On; DMV for role/sync)
-- Variables:
--   &ag_name  availability group name (empty = all)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Get-DbaAgReplica
--
SET NOCOUNT ON;

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) <> 1
BEGIN
    PRINT 'Always On not enabled on this instance (requires 2012+ Enterprise)';
    RETURN;
END

-- COL: ag a18 replica a25 role a10 conn a10 sync a12 avail a10 (~280)
DECLARE @ag_filter SYSNAME;
SET @ag_filter = NULLIF(RTRIM('&ag_name'), '');

PRINT '---------- ag replicas ----------';
EXEC sp_executesql N'
SELECT LEFT(ag.name, 18) AS ag,
       LEFT(ar.replica_server_name, 25) AS replica,
       LEFT(rs.role_desc, 10) AS role,
       LEFT(rs.connected_state_desc, 10) AS conn,
       LEFT(rs.synchronization_health_desc, 12) AS sync,
       LEFT(ar.availability_mode_desc, 10) AS avail_mode
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states rs ON ar.replica_id = rs.replica_id
WHERE (@ag = '''' OR ag.name = @ag)
ORDER BY ag.name, ar.replica_server_name',
    N'@ag SYSNAME', @ag = @ag_filter;
