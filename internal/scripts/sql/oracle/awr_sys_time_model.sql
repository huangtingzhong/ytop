-- File Name: awr_sys_time_model.sql
-- Purpose: Oracle AWR Sys Time Model
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info.sql

set echo off
store set sqlplusset replace
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000

ACCEPT begin_snap prompt 'Enter Search Begin Snapshot  (i.e. 2) : '
ACCEPT end_snap prompt 'Enter Search End Snapshot  (i.e. 4) : '
ACCEPT instance_number prompt 'Enter Search Instance Number  (i.e. 1(default)) : ' default '1'

variable bid  number;
variable eid  number;
variable inst_num  number;

begin
  :bid  :=  &begin_snap ;
  :eid  :=  &end_snap;
  :inst_num:=&instance_number;
end;
/
col dbtime new_v dbtimei
SELECT e.VALUE - b.VALUE dbtime
  FROM dba_hist_sys_time_model b, dba_hist_sys_time_model e
 WHERE     b.stat_name = 'DB time'
       AND e.stat_name = 'DB time'
       AND B.snap_id = :bid
       and e.instance_number=b.instance_number and e.instance_number=:inst_num
       AND e.snap_id = :eid;       
/* Formatted on 2013/2/24 17:38:35 (QP5 v5.215.12089.38647) */
variable dbtime  number;
begin
  :dbtime  :=  &dbtimei;
end;
/
col stat_name for a50 heading 'Statistic Name'
col time for 99999999999.99 heading 'Time (s)'
col d1 for 99999.99 heading '% of DB Time'
SELECT stat_name,
         seconds time ,
         DECODE ( (dbt + bglast), 0, percent, TO_NUMBER (NULL))  d1,
         (dbt + bglast) order_col
    FROM (SELECT b.stat_name,
                 (b.VALUE - a.VALUE) / 1000000 AS seconds,
                 100 * ( (b.VALUE - a.VALUE) / :dbtime) AS percent,
                 DECODE (b.stat_name, 'DB time', 1, 0) dbt,
                 DECODE (INSTR (b.stat_name, 'background'), 1, 2, 0) bglast
            FROM dba_hist_sys_time_model a, dba_hist_sys_time_model b
           WHERE     a.dbid = (select dbid from v$database)
                 AND b.dbid = (select dbid from v$database)
                 AND a.instance_number = :inst_num
                 AND b.instance_number = :inst_num
                 AND a.snap_id = :bid
                 AND b.snap_id = :eid
                 AND a.stat_id = b.stat_id
                 AND b.VALUE - a.VALUE > 0)
ORDER BY order_col ASC, seconds DESC, stat_name
/
clear    breaks  
@sqlplusset

