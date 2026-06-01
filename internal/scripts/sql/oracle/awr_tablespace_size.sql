-- File Name: awr_tablespace_size.sql
-- Purpose: Oracle AWR Tablespace Size
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info;
set echo off
set verify off lines 30000 pages 1000 heading on
undefine snap_id;
col snap_time for a18
col name for a20
col tb_size for 9999 heading 'TB_SIZE(G)'
col tb_maxsize for 999999 heading 'TB_MAX|SIZE(G)'
col tb_usedsize for 999999 heading 'TB_USED|SIZE(G)'
  SELECT TO_CHAR (d.BEGIN_INTERVAL_TIME, 'yyyy-mm-dd hh24:mi') snap_time,
         b.name,
         TRUNC (a.tablespace_size / 1024 / 1024 / 1024) tb_size,
         TRUNC (a.tablespace_maxsize / 1024 / 1024 / 1024) tb_maxsize,
         TRUNC (a.tablespace_usedsize / 1024 / 1024 / 1024) tb_usedsize,
         a.rtime
    FROM DBA_HIST_TBSPC_SPACE_USAGE a, v$tablespace b, dba_hist_snapshot d
   WHERE     a.tablespace_id(+) = b.ts#
         AND a.snap_id = D.SNAP_ID
         AND d.snap_id = NVL ('&snap_id', d.snap_id)
ORDER BY 1, 2;
undefine snap_id;