-- File Name: ag.sql
-- Purpose: MSSQL Availability group summary
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag.sql -w 300 -W
-- MinVersion: 2012 (dynamic SQL when HADR enabled)
-- Variables:
--   &ag_name  availability group name (empty = all)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Get-DbaAvailabilityGroup
--
SET NOCOUNT ON;

DECLARE @ag_filter SYSNAME;
SET @ag_filter = NULLIF(RTRIM('&ag_name'), '');

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) <> 1
BEGIN
    PRINT 'Always On not enabled on this instance (requires 2012+ Enterprise)';
    RETURN;
END

PRINT '---------- availability groups ----------';
EXEC sp_executesql N'
SELECT LEFT(ag.name, 25) AS ag_name,
       LEFT(ISNULL(p.replica_server_name, ''''), 25) AS primary_replica,
       CAST(ag.automated_backup_preference AS VARCHAR(4)) AS auto_bak
FROM sys.availability_groups ag
OUTER APPLY (
    SELECT TOP 1 ar.replica_server_name
    FROM sys.availability_replicas ar
    JOIN sys.dm_hadr_availability_replica_states rs ON ar.replica_id = rs.replica_id
    WHERE ar.group_id = ag.group_id AND rs.role_desc = ''PRIMARY''
) p
WHERE (@ag = '''' OR ag.name = @ag)
ORDER BY ag.name',
    N'@ag SYSNAME', @ag = @ag_filter;
