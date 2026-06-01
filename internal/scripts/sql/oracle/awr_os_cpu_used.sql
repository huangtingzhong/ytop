-- File Name: awr_os_cpu_used.sql
-- Purpose: Oracle AWR Os Cpu Used
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info.sql
set echo off
set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000
col snap_time for a16 heading 'Snap Time'
col load for 999.99
col busy_pct for 999.99 heading '%busy'
col user_pct for 999.99 heading '%user'
col sys_pct for 999.99 heading '%sys'
col idl_pct for 999.99 heading '%idle'
col wio_pct for 999.99 heading '%iowait'
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
  SELECT TO_CHAR (s.end_interval_time, 'mm-dd hh24:mi:ss') snap_time,
         load,
         DECODE (busy_time + idle_time,
                 0, TO_NUMBER (NULL),
                 busy_time / (busy_time + idle_time) * 100)
            busy_pct,
         DECODE (busy_time + idle_time,
                 0, TO_NUMBER (NULL),
                 user_time / (busy_time + idle_time) * 100)
            user_pct,
         DECODE (busy_time + idle_time,
                 0, TO_NUMBER (NULL),
                 sys_time / (busy_time + idle_time) * 100)
            sys_pct,
         DECODE (busy_time + idle_time,
                 0, TO_NUMBER (NULL),
                 idle_time / (busy_time + idle_time) * 100)
            idl_pct,
         DECODE (busy_time + idle_time,
                 0, TO_NUMBER (NULL),
                 wio_time / (busy_time + idle_time) * 100)
            wio_pct
    FROM (  SELECT snap_id,
                   instance_number,
                   dbid,
                   COUNT (*) cnt,
                   SUM (DECODE (stat_name, 'LOAD', VALUE, 0)) load,
                   SUM (DECODE (stat_name, 'BUSY_TIME', VALUE - prev_value, 0))
                      busy_time,
                   SUM (DECODE (stat_name, 'IDLE_TIME', VALUE - prev_value, 0))
                      idle_time,
                   SUM (DECODE (stat_name, 'USER_TIME', VALUE - prev_value, 0))
                      user_time,
                   SUM (DECODE (stat_name, 'SYS_TIME', VALUE - prev_value, 0))
                      sys_time,
                   SUM (DECODE (stat_name, 'IOWAIT_TIME', VALUE - prev_value, 0))
                      wio_time
              FROM (  SELECT snap_id,
                             instance_number,
                             dbid,
                             stat_name,
                             VALUE,
                             LAG (
                                VALUE,
                                1)
                             OVER (PARTITION BY stat_name, instance_number, dbid
                                   ORDER BY snap_id)
                                prev_value
                        FROM dba_hist_osstat
                       WHERE     snap_id BETWEEN :bid AND :eid
                             AND dbid = (SELECT dbid FROM v$database)
                             AND instance_number = :inst_num
                    ORDER BY stat_name, instance_number, snap_id)
          GROUP BY snap_id, dbid, instance_number) os,
         dba_hist_snapshot s
   WHERE     os.snap_id = s.snap_id
         AND os.instance_number = s.instance_number
         AND os.dbid = s.dbid
-- and os.snap_id         > :bid
ORDER BY os.instance_number, os.snap_id
/
clear    breaks  
