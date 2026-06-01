-- File Name: awr_event_foreground_sum.sql
-- Purpose: Oracle AWR Event Foreground Sum
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

variable begin_snap  number;
variable end_snap  number;
variable instance_number  number;

begin
  :begin_snap  :=  &begin_snap ;
  :end_snap  :=  &end_snap;
  :instance_number:=&instance_number;
end;
/
col tcpu new_v tcpui
col dbtime new_v dbtimei
with t as (select a.tcpu,c.dbtime from (SELECT e.VALUE - b.VALUE tcpu
  FROM dba_hist_sys_time_model b, dba_hist_sys_time_model e
 WHERE     b.stat_name = 'DB CPU'
       AND e.stat_name = 'DB CPU'
       AND B.snap_id = :begin_snap
       and e.instance_number=b.instance_number and e.instance_number=:instance_number
       AND e.snap_id = :end_snap) a,(SELECT e.VALUE - b.VALUE dbtime
  FROM dba_hist_sys_time_model b, dba_hist_sys_time_model e
 WHERE     b.stat_name = 'DB time'
       AND e.stat_name = 'DB time'
       AND B.snap_id = :begin_snap
       and e.instance_number=b.instance_number and e.instance_number=:instance_number
       AND e.snap_id = :end_snap) c)
select * from t;


       
/* Formatted on 2013/2/24 17:38:35 (QP5 v5.215.12089.38647) */
variable dbtime  number;
variable tcpu  number;
begin
  :dbtime  :=  &dbtimei;
  :tcpu  :=  &tcpui;
end;
/
set lines 170
col wait_class for a20 heading 'Wait Class'
col topct for 999999 heading '%Time -outs'
col avgwt for 999999999999.99 heading 'Avg wait (ms)'
col time for 9999999999.99 heading 'Total Wait Time (s)'
col pctdbtm for 99999999.99 heading '% DB time'
/* Formatted on 2013/2/24 19:19:35 (QP5 v5.215.12089.38647) */
  SELECT wait_class,
         wtfg waits,
         DECODE (wtfg, 0, TO_NUMBER (NULL), ttofg / wtfg) * 100 topct,
         tmfg / 1000000 time,
         DECODE (wtfg, 0, TO_NUMBER (NULL), tmfg / wtfg) / 1000 avgwt,
         DECODE (:dbtime, 0, TO_NUMBER (NULL), tmfg / :dbtime) * 100 pctdbtm
    FROM ( (  SELECT e.wait_class wait_class,
                     SUM (
                        CASE
                           WHEN e.total_waits_fg IS NOT NULL
                           THEN
                              e.total_waits_fg - NVL (b.total_waits_fg, 0)
                           ELSE
                                (e.total_waits - NVL (b.total_waits, 0))
                              - GREATEST (
                                   0,
                                   (  NVL (ebg.total_waits, 0)
                                    - NVL (bbg.total_waits, 0)))
                        END)
                        wtfg,
                     SUM (
                        CASE
                           WHEN e.total_timeouts_fg IS NOT NULL
                           THEN
                              e.total_timeouts_fg - NVL (b.total_timeouts_fg, 0)
                           ELSE
                                (e.total_timeouts - NVL (b.total_timeouts, 0))
                              - GREATEST (
                                   0,
                                   (  NVL (ebg.total_timeouts, 0)
                                    - NVL (bbg.total_timeouts, 0)))
                        END)
                        ttofg,
                     SUM (
                        CASE
                           WHEN e.time_waited_micro_fg IS NOT NULL
                           THEN
                                e.time_waited_micro_fg
                              - NVL (b.time_waited_micro_fg, 0)
                           ELSE
                                (  e.time_waited_micro
                                 - NVL (b.time_waited_micro, 0))
                              - GREATEST (
                                   0,
                                   (  NVL (ebg.time_waited_micro, 0)
                                    - NVL (bbg.time_waited_micro, 0)))
                        END)
                        tmfg
                FROM dba_hist_system_event b,
                     dba_hist_system_event e,
                     dba_hist_bg_event_summary bbg,
                     dba_hist_bg_event_summary ebg
               WHERE     b.snap_id(+) = :bid
                     AND e.snap_id = :eid
                     AND bbg.snap_id(+) = :bid
                     AND ebg.snap_id(+) = :eid
                     AND e.dbid = (select dbid from v$database)
                     AND e.instance_number = :inst_num
                     AND e.dbid = b.dbid(+)
                     AND e.instance_number = b.instance_number(+)
                     AND e.event_id = b.event_id(+)
                     AND e.dbid = ebg.dbid(+)
                     AND e.instance_number = ebg.instance_number(+)
                     AND e.event_id = ebg.event_id(+)
                     AND e.dbid = bbg.dbid(+)
                     AND e.instance_number = bbg.instance_number(+)
                     AND e.event_id = bbg.event_id(+)
                     AND e.total_waits > NVL (b.total_waits, 0)
                     AND e.wait_class <> 'Idle'
            GROUP BY e.wait_class)
          UNION ALL
          SELECT 'DB CPU' wait_class,
                 TO_NUMBER (NULL) wtfg,
                 TO_NUMBER (NULL) ttofg,
                 :tcpu tmfg
            FROM DUAL
           WHERE :tcpu > 0)
ORDER BY tmfg DESC, wtfg DESC, wait_class
 /
clear    breaks  
@sqlplusset

