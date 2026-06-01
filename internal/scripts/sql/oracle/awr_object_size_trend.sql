-- File Name: awr_object_size_trend.sql
-- Purpose: Oracle AWR Object Size Trend
-- Created: 20260516  by  huangtingzhong

set echo off
set echo off
set verify off
set serveroutput on
set feedback off
set lines 200
set pages 40
col end_interval_name for a15  heading "END_TIME"
column owner format a16
column table_name format a30
column start_day format a11
column block_increase format 9999999999
col tablespace_name for a15
break on end_interval_name on tablespace_name  on owner
select * from (
  select end_interval_name,tablespace_name,owner,table_name,round(sum(space_used_delta)/1024/1024/1024,2) space_used_delta_g ,round(sum(space_allocated_delta)/1024/1024/1024,2) space_allocated_delta_g,round(sum(db_block_changes_delta)/1024/1024/1024,2) db_block_changes_delta_g ,DENSE_RANK ()
                 OVER (
                    PARTITION BY end_interval_name
                    ORDER BY SUM (space_used_delta) DESC)
                    ORDERBY
  FROM (  SELECT TO_CHAR (sn.end_interval_time, 'YYYY-MM-DD')
                    end_interval_name,
                 tb.name tablespace_name,
                 obj.owner,case when obj.object_type like 'LOB%' then lb.table_name else obj.object_name end as table_name,
                 space_used_delta,space_allocated_delta,db_block_changes_delta
            FROM dba_hist_seg_stat a,
                 dba_hist_snapshot sn,
                 dba_objects obj,
                 v$tablespace tb,
                 dba_lobs lb
           WHERE     a.ts# = tb.ts#
                 AND obj.owner=lb.owner(+)
                 AND obj.object_name=lb.segment_name(+)
                 AND sn.snap_id = a.snap_id
                 AND obj.object_id = a.obj#
                 --  and obj.owner not in ('SYS', 'SYSTEM')
                 AND end_interval_time >=
                        TO_TIMESTAMP (
                           (TO_CHAR (SYSDATE - NVL ('&&day', 7), 'YYYY-MM-DD')),
                           'YYYY-MM-DD')
                 AND end_interval_time <=
                        TO_TIMESTAMP (
                           (TO_CHAR (
                                 SYSDATE
                               - (  NVL ('&&day', 7)
                                  - NVL ('&&interval_day', &&day)),
                               'YYYY-MM-DD')),
                           'YYYY-MM-DD')
                 AND tb.name = NVL (UPPER ('&&tablespace_name'), tb.name)
                 AND obj.OWNER = NVL (UPPER ('&&ownername'), obj.owner)
                 AND obj.OBJECT_NAME =
                        NVL (UPPER ('&&segmentname'), obj.object_name))
        group by end_interval_name,tablespace_name,owner,table_name) dd
 WHERE dd.orderby < NVL ('&&top', 40)
/
clear    breaks  
undefine tablespace_name;
undefine day;
undefine ownername;
undefine segmentname;
undefine top;
undefine interval_day
