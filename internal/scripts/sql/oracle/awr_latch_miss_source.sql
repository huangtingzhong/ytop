-- File Name: awr_latch_miss_source.sql
-- Purpose: Oracle AWR Latch Miss Source
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info.sql

set echo off
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
variable top_n number;

begin
  :bid  :=  &begin_snap ;
  :eid  :=  &end_snap;
  :inst_num:=&instance_number;
end;
/
col name for a40 heading "Latch Name"
col where_from for a40 heading "Where"
col nwmisses for 999999999 heading "NoWait Misses"
col sleeps for 9999999 heading 'sleeps'
col waiter_sleeps fro 9999999 heading "Waiter Sleeps"
/* Formatted on 2013/2/24 23:09:06 (QP5 v5.215.12089.38647) */
  SELECT e.parent_name parent,
         e.where_in_code where_from,
         e.nwfail_count - NVL (b.nwfail_count, 0) nwmisses,
         e.sleep_count - NVL (b.sleep_count, 0) sleeps,
         e.wtr_slp_count - NVL (b.wtr_slp_count, 0) waiter_sleeps
    FROM dba_hist_latch_misses_summary b, dba_hist_latch_misses_summary e
   WHERE     b.snap_id(+) = :bid
         AND e.snap_id = :eid
         /*AND b.dbid(+) = :dbid
         AND e.dbid = :dbid
         AND b.dbid(+) = e.dbid*/
         AND b.instance_number(+) = :inst_num
         AND e.instance_number = :inst_num
         AND b.instance_number(+) = e.instance_number
         AND b.parent_name(+) = e.parent_name
         AND b.where_in_code(+) = e.where_in_code
         AND e.sleep_count > NVL (b.sleep_count, 0)
ORDER BY e.parent_name, sleeps DESC, e.where_in_code
 /
 clear    breaks  
