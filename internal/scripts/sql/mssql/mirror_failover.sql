-- File Name: mirror_failover.sql
-- Purpose: MSSQL Mirror failover (CHANGE)
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i mirror_failover.sql -w 300 -W
--
-- Variables:
--   &dbname  database name (required)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Invoke-DbaDbMirrorFailover
--
SET NOCOUNT ON;
-- *** P2 CHANGE SCRIPT - requires confirmation before use ***

PRINT 'Template only - ALTER DATABASE ... SET PARTNER FAILOVER after confirmation';
