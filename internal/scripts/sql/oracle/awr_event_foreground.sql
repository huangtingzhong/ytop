-- File Name: awr_event_foreground.sql
-- Purpose: Oracle AWR Event Foreground
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
col tran new_v trani
/* Formatted on 2013/2/24 19:52:51 (QP5 v5.215.12089.38647) */
WITH t
     AS (SELECT a.tcpu, c.dbtime, d.tran
           FROM (SELECT e.VALUE - b.VALUE tcpu
                   FROM dba_hist_sys_time_model b, dba_hist_sys_time_model e
                  WHERE     b.stat_name = 'DB CPU'
                        AND e.stat_name = 'DB CPU'
                        AND B.snap_id = :bid
                        AND e.instance_number = b.instance_number
                        AND e.instance_number = :instance_number
                        AND e.snap_id = :eid
                        AND e.instance_number = b.instance_number
                        AND e.instance_number = :instance_number) a,
                (SELECT e.VALUE - b.VALUE dbtime
                   FROM dba_hist_sys_time_model b, dba_hist_sys_time_model e
                  WHERE     b.stat_name = 'DB time'
                        AND e.stat_name = 'DB time'
                        AND B.snap_id = :bid
                        AND e.instance_number = b.instance_number
                        AND e.instance_number = :instance_number
                        AND e.snap_id = :eid
                        AND e.instance_number = b.instance_number
                        AND e.instance_number = :instance_number) c,
                (SELECT SUM (e.VALUE) - SUM (b.VALUE) tran
                   FROM dba_hist_sysstat b, dba_hist_sysstat e
                  WHERE     b.STAT_NAME IN ('user rollbacks', 'user commits')
                        AND b.snap_id = :bid
                        AND e.snap_id = :eid
                        AND b.stat_name = e.stat_name
                        AND b.dbid = e.dbid
                        AND b.dbid = (SELECT dbid FROM v$database)
                        AND b.instance_number = e.instance_number
                        AND b.instance_number = :inst_num) d)
SELECT *
  FROM t;


       
/* Formatted on 2013/2/24 17:38:35 (QP5 v5.215.12089.38647) */
variable dbtime  number;
variable tcpu  number;
variable tran  number;
begin
  :dbtime  :=  &dbtimei;
  :tcpu  :=  &tcpui;
  :tran  :=  &trani;
end;
/
set lines 170
col wait_class for a20 heading 'Wait Class'
col topct for 999999 heading '%Time -outs'
col avwt_fmt for 999999999999.999 heading 'Avg wait (ms)'
col time for 9999999999.999 heading 'Total Wait Time (s)'
col pctwtt for 99999999.999 heading '% DB time'
col txwaits for 9999999.999 heading 'Waits /txn'
col pctto for 99999999.999 heading '%Time -outs'
/* Formatted on 2013/2/24 19:53:59 (QP5 v5.215.12089.38647) */
  SELECT event,
         wtfg waits,
         DECODE (wtfg, 0, TO_NUMBER (NULL), ttofg / wtfg) * 100 pctto,
         tmfg / 1000000 time,
         DECODE (wtfg, 0, TO_NUMBER (NULL), tmfg / wtfg) / 1000 avwt_fmt,
         DECODE (:tran, 0, TO_NUMBER (NULL), wtfg / :tran) txwaits,
         CASE
            WHEN idle = 0
            THEN
               DECODE (:dbtime, 0, TO_NUMBER (NULL), tmfg / :dbtime) * 100
            ELSE
               TO_NUMBER (NULL)
         END
            pctwtt
    FROM (SELECT e.event_name event,
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
                 END
                    wtfg,
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
                 END
                    ttofg,
                 CASE
                    WHEN e.time_waited_micro_fg IS NOT NULL
                    THEN
                       e.time_waited_micro_fg - NVL (b.time_waited_micro_fg, 0)
                    ELSE
                         (e.time_waited_micro - NVL (b.time_waited_micro, 0))
                       - GREATEST (
                            0,
                            (  NVL (ebg.time_waited_micro, 0)
                             - NVL (bbg.time_waited_micro, 0)))
                 END
                    tmfg,
                 DECODE (e.wait_class, 'Idle', 99, 0) idle
            FROM dba_hist_system_event b,
                 dba_hist_system_event e,
                 dba_hist_bg_event_summary bbg,
                 dba_hist_bg_event_summary ebg
           WHERE     b.snap_id(+) = :bid
                 AND e.snap_id = :eid
                 AND bbg.snap_id(+) = :bid
                 AND ebg.snap_id(+) = :eid
                 AND e.dbid = (SELECT dbid FROM v$database)
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
                 AND e.total_waits > NVL (b.total_waits, 0))
   WHERE tmfg / 1000000 >= .001
ORDER BY idle, tmfg DESC, wtfg DESC
 /
clear    breaks  
@sqlplusset

