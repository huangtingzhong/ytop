-- File Name: awr_snap_error.sql
-- Purpose: Oracle AWR Snap Error
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set lines 200
select  * from dba_hist_snap_error where dbid =(select dbid from v$database) and snap_id=nvl('&snap_id',snap_id);
set verify on
set echo on
