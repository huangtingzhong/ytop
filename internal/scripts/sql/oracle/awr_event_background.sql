-- File Name: awr_event_background.sql
-- Purpose: Oracle AWR Event Background
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
col bgela new_v bgelai
col tran new_v trani
/* Formatted on 2013/2/24 19:52:51 (QP5 v5.215.12089.38647) */
/* Formatted on 2013/2/24 20:39:22 (QP5 v5.215.12089.38647) */
set term off
WITH t
     AS (SELECT c.bgela, d.tran
           FROM (SELECT e.VALUE - b.VALUE bgela
                   FROM dba_hist_sys_time_model b, dba_hist_sys_time_model e
                  WHERE     b.stat_name = 'background elapsed time'
                        AND e.stat_name = 'background elapsed time'
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
set term on
       
/* Formatted on 2013/2/24 17:38:35 (QP5 v5.215.12089.38647) */
variable bgela  number;
variable tran  number;
begin
  :bgela  :=  &bgelai;
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
/* Formatted on 2013/2/24 20:35:23 (QP5 v5.215.12089.38647) */
  SELECT e.event_name event,
         e.total_waits - NVL (b.total_waits, 0) waits,
         DECODE (
            (e.total_waits - NVL (b.total_waits, 0)),
            0, TO_NUMBER (NULL),
              100
            * (e.total_timeouts - NVL (b.total_timeouts, 0))
            / (e.total_waits - NVL (b.total_waits, 0)))
            pctto,
         (e.time_waited_micro - NVL (b.time_waited_micro, 0)) / 1000000 time,
         DECODE (
            (e.total_waits - NVL (b.total_waits, 0)),
            0, TO_NUMBER (NULL),
              ( (e.time_waited_micro - NVL (b.time_waited_micro, 0)) / 1000)
            / (e.total_waits - NVL (b.total_waits, 0)))
            avwt_fmt,
         (e.total_waits - NVL (b.total_waits, 0)) / :tran txwaits,
         CASE
            WHEN DECODE (e.wait_class, 'Idle', 0, 99) <> 0
            THEN
               DECODE (
                  :bgela,
                  0, 0,
                    100
                  * (e.time_waited_micro - NVL (b.time_waited_micro, 0))
                  / :bgela)
            ELSE
               TO_NUMBER (NULL)
         END
            pctwtt,
         DECODE (e.wait_class, 'Idle', 0, 99) idle
    FROM dba_hist_bg_event_summary b, dba_hist_bg_event_summary e
   WHERE     b.snap_id(+) = :bid
         AND e.snap_id = :eid
         /*AND b.dbid(+) = (SELECT dbid FROM v$database)
         AND e.dbid = (SELECT dbid FROM v$database)*/
         AND b.instance_number(+) = :inst_num
         AND e.instance_number = :inst_num
         AND b.event_id(+) = e.event_id
         AND b.event_name(+) = e.event_name
         AND e.total_waits > NVL (b.total_waits, 0)
         AND ( (e.time_waited_micro - NVL (b.time_waited_micro, 0)) / 1000000) >=
                .001
-- and e.event(+)           = e.event
ORDER BY idle DESC, time DESC, waits DESC
 /
clear    breaks  
@sqlplusset

