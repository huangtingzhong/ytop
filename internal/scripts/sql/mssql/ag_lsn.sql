-- File Name: ag_lsn.sql
-- Purpose: MSSQL AG listener and sync lag
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag_lsn.sql -w 300 -W
-- MinVersion: 2012 (Always On)
-- Variables:
--   &ag_name  availability group name (empty = all)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Get-DbaAgListener, Get-DbaAgReplica
--
SET NOCOUNT ON;

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) <> 1
BEGIN
    PRINT 'Always On not enabled on this instance (requires 2012+ Enterprise)';
    RETURN;
END

DECLARE @ag_filter SYSNAME;
SET @ag_filter = NULLIF(RTRIM('&ag_name'), '');

PRINT '---------- ag listeners ----------';
EXEC sp_executesql N'
SELECT LEFT(ag.name, 20) AS ag, LEFT(l.dns_name, 25) AS listener,
       CAST(l.port AS VARCHAR(6)) AS port,
       LEFT(ISNULL(ip.ip_address, ''''), 18) AS ip,
       LEFT(ISNULL(ip.ip_subnet_mask, ''''), 12) AS subnet
FROM sys.availability_groups ag
JOIN sys.availability_group_listeners l ON ag.group_id = l.group_id
LEFT JOIN sys.availability_group_listener_ip_addresses ip ON l.listener_id = ip.listener_id
WHERE (@ag = '''' OR ag.name = @ag)
ORDER BY ag.name, l.dns_name, ip.ip_address',
    N'@ag SYSNAME', @ag = @ag_filter;

PRINT '---------- ag sync lag (non-primary replicas) ----------';
EXEC sp_executesql N'
SELECT LEFT(ag.name, 15) AS ag, LEFT(DB_NAME(drs.database_id), 20) AS dbname,
       LEFT(ar.replica_server_name, 25) AS replica,
       LEFT(drs.synchronization_state_desc, 12) AS sync,
       CAST(drs.redo_queue_size AS VARCHAR(10)) AS redo_q_kb,
       CAST(drs.log_send_queue_size AS VARCHAR(10)) AS send_q_kb
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
JOIN sys.availability_groups ag ON ar.group_id = ag.group_id
WHERE drs.is_primary_replica = 0 AND (@ag = '''' OR ag.name = @ag)
ORDER BY ag.name, DB_NAME(drs.database_id), ar.replica_server_name',
    N'@ag SYSNAME', @ag = @ag_filter;
