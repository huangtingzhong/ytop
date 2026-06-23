-- File Name: ag_rb.sql
-- Purpose: MSSQL AG diagnostic ring buffer
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag_rb.sql -w 300 -W
-- MinVersion: 2012 (HADR ring buffer)
-- Variables:
--   &ag_name  AG name (empty = all)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Get-DbaAgRingBuffer
--
SET NOCOUNT ON;

IF CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) <> 1
BEGIN
    PRINT 'Always On not enabled; sys.dm_hadr_ring_buffer_events unavailable';
    RETURN;
END

IF OBJECT_ID('sys.dm_hadr_ring_buffer_events') IS NULL
BEGIN
    PRINT 'sys.dm_hadr_ring_buffer_events not available on this build';
    RETURN;
END

PRINT '---------- ag ring buffer (top 50) ----------';
EXEC sp_executesql N'
SELECT TOP 50
    LEFT(CAST(record AS NVARCHAR(200)), 200) AS record_snip,
    timestamp
FROM sys.dm_hadr_ring_buffer_events
ORDER BY timestamp DESC';
