-- File Name: sess_archive.sql
-- Purpose: Oracle session Archive
-- Created: 20260516  by  huangtingzhong

set lines 200
set echo off
col inst_id for 9999
col state for a10
select * from gv$archive_processes where status='ACTIVE'
/
