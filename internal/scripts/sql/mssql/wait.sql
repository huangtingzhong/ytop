-- File Name: wait.sql
-- Purpose: MSSQL Top wait statistics
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i wait.sql -w 300 -W
-- MinVersion: 2008
-- Variables:
--   &top_n  top N waits (empty = 20)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Get-DbaWaitStatistic
-- Oracle ref: ash_* (partial)
--
SET NOCOUNT ON;

DECLARE @top_n INT;
IF LEN(RTRIM('&top_n')) = 0 SET @top_n = 20;
ELSE IF ISNUMERIC(RTRIM('&top_n')) = 1 SET @top_n = CAST(RTRIM('&top_n') AS INT);
ELSE SET @top_n = 20;
IF @top_n < 1 SET @top_n = 20;

-- COL: wait_type a35 waits a12 wait_ms a12 signal_ms a12 pct a6 (~280)
PRINT '---------- top waits (excludes idle/benign) ----------';
;WITH w AS (
    SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        'CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK',
        'SLEEP_SYSTEMTASK','SQLTRACE_BUFFER_FLUSH','WAITFOR','LOGMGR_QUEUE',
        'CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH','XE_TIMER_EVENT',
        'BROKER_TO_FLUSH','BROKER_EVENTHANDLER','TRACEWRITE','FT_IFTS_SCHEDULER_IDLE_WAIT',
        'BROKER_RECEIVE_WAITFOR','ONDEMAND_TASK_QUEUE','DBMIRROR_EVENTS_QUEUE',
        'DBMIRRORING_CMD','DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        'SP_SERVER_DIAGNOSTICS_SLEEP','QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP','SQLTRACE_INCREMENTAL_FLUSH_SLEEP')
      AND wait_type NOT LIKE 'SLEEP_%'
      AND wait_type NOT LIKE 'XE_%'
      AND wait_type NOT LIKE 'HADR_%WORKER'
      AND wait_time_ms > 0
)
SELECT TOP (@top_n)
    LEFT(wait_type, 35) AS wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER(), 0) AS DECIMAL(5,1)) AS pct
FROM w
ORDER BY wait_time_ms DESC;

PRINT '---------- wait since startup (ms -> sec) hint ----------';
SELECT TOP 5 LEFT(wait_type, 35) AS wait_type,
       wait_time_ms / 1000 AS wait_sec,
       waiting_tasks_count AS tasks
FROM sys.dm_os_wait_stats
WHERE wait_time_ms > 0
ORDER BY wait_time_ms DESC;
