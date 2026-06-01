-- File Name: awr_latch_sleep.sql
-- Purpose: Oracle AWR Latch Sleep
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
variable top_n number;

begin
  :bid  :=  &begin_snap ;
  :eid  :=  &end_snap;
  :inst_num:=&instance_number;
end;
/
col name for a40 heading 'latch name'
col gets for 999999999999 heading 'Get Requests'
col misses for 99999999999 heading 'Misses'
col sleeps for 9999999999 heading 'Sleeps'
col spin_gets for 99999999999 heading "Spin Gets"
/* Formatted on 2013/2/24 23:05:21 (QP5 v5.215.12089.38647) */
  SELECT b.latch_name name,
         e.gets - b.gets gets,
         e.misses - b.misses misses,
         e.sleeps - b.sleeps sleeps,
         e.spin_gets - b.spin_gets spin_gets
    FROM dba_hist_latch b, dba_hist_latch e
   WHERE     b.snap_id = :bid
         AND e.snap_id = :eid
         /*AND b.dbid = :dbid
         AND e.dbid = :dbid*/
         AND b.instance_number = :inst_num
         AND e.instance_number = :inst_num
         AND b.latch_hash = e.latch_hash
         AND e.sleeps - b.sleeps > 0
ORDER BY misses DESC, name
 /
 clear    breaks  
@sqlplusset
