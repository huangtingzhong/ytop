-- File Name: awr_latch_activity.sql
-- Purpose: Oracle AWR Latch Activity
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
col name for a40 heading "Latch Name"
col gets for 999999999999 heading "Get Requests"
col missed for 9999.99 heading "Pct Get Miss"
col sleeps for 99999.99 heading "Avg Slps /Miss"
col wt for 9999999.99 heading "	Wait Time (s)"
col nowai for 99999999 heading "NoWait Requests"
col imiss for 9999999.99 heading "Pct NoWait Miss"
/* Formatted on 2013/2/24 22:58:26 (QP5 v5.215.12089.38647) */
  SELECT b.latch_name name,
         e.gets - b.gets gets,
         TO_NUMBER (
            DECODE (e.gets,
                    b.gets, NULL,
                    (e.misses - b.misses) * 100 / (e.gets - b.gets)))
            missed,
         TO_NUMBER (
            DECODE (e.misses,
                    b.misses, NULL,
                    (e.sleeps - b.sleeps) / (e.misses - b.misses)))
            sleeps,
         (e.wait_time - b.wait_time) / 1000000 wt,
         e.immediate_gets - b.immediate_gets nowai,
         TO_NUMBER (
            DECODE (
               e.immediate_gets,
               b.immediate_gets, NULL,
                 (e.immediate_misses - b.immediate_misses)
               * 100
               / (e.immediate_gets - b.immediate_gets)))
            imiss
    FROM dba_hist_latch b, dba_hist_latch e
   WHERE     b.snap_id = :bid
         AND e.snap_id = :eid
         /*AND b.dbid = :dbid
         AND e.dbid = :dbid*/
         AND b.instance_number = :inst_num
         AND e.instance_number = :inst_num
         AND b.latch_hash = e.latch_hash
         AND (e.gets - b.gets + e.immediate_gets - b.immediate_gets) > 0
ORDER BY b.latch_name
 /
 clear    breaks  
@sqlplusset
