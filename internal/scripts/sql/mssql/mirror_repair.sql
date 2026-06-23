-- File Name: mirror_repair.sql
-- Purpose: MSSQL Repair mirroring (CHANGE)
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i mirror_repair.sql -w 300 -W
--
-- Variables:
--   &dbname  database name (required)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Repair-DbaDbMirror
--
SET NOCOUNT ON;
-- *** P2 CHANGE SCRIPT - requires confirmation before use ***

PRINT 'Template only - ALTER DATABASE ... SET PARTNER ... after confirmation';
