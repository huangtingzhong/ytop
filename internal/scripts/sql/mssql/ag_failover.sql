-- File Name: ag_failover.sql
-- Purpose: MSSQL AG manual failover (CHANGE)
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag_failover.sql -w 300 -W
--
-- Variables:
--   &ag_name  AG name (required)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Invoke-DbaAgFailover
--
SET NOCOUNT ON;
-- *** P2 CHANGE SCRIPT - requires confirmation before use ***

PRINT 'Template only - implement with ALTER AVAILABILITY GROUP ... FAILOVER after confirmation';
