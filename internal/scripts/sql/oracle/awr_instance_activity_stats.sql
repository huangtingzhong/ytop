-- File Name: awr_instance_activity_stats.sql
-- Purpose: Oracle AWR Instance Activity Stats
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
col ela new_v elai
col tran new_v trani
/* Formatted on 2013/2/24 19:52:51 (QP5 v5.215.12089.38647) */
/* Formatted on 2013/2/24 20:39:22 (QP5 v5.215.12089.38647) */
WITH t
     AS (SELECT c.ela, d.tran
           FROM (SELECT     EXTRACT (
                               DAY FROM   e.end_interval_time
                                        - b.end_interval_time)
                          * 86400
                        +   EXTRACT (
                               HOUR FROM   e.end_interval_time
                                         - b.end_interval_time)
                          * 3600
                        +   EXTRACT (
                               MINUTE FROM   e.end_interval_time
                                           - b.end_interval_time)
                          * 60
                        + EXTRACT (
                             SECOND FROM   e.end_interval_time
                                         - b.end_interval_time)
                           ela
                   FROM dba_hist_snapshot b, dba_hist_snapshot e
                  WHERE     b.snap_id = :bid
                        AND e.snap_id = :eid
                        /*and b.dbid            = :dbid
                        and e.dbid            = :dbid*/
                        AND b.instance_number = :inst_num
                        AND e.instance_number = :inst_num) C,
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
variable ela  number;
variable tran  number;
begin
  :ela  :=  &elai;
  :tran  :=  &trani;
end;
/
set lines 170
set pages 500
col st for a50 heading 'Statistic'
col total for 999999999999 heading 'Total'
col value1 for 999999999999.99 heading 'per Second'
col value2 for 999999999999.99 heading 'per Trans'
/* Formatted on 2013/2/25 16:08:09 (QP5 v5.215.12089.38647) */
  SELECT b.stat_name st,
         e.VALUE - b.VALUE total,
         ROUND ( (e.VALUE - b.VALUE) / :ela, 2) value1,
         ROUND ( (e.VALUE - b.VALUE) / :tran, 2) value2
    FROM dba_hist_sysstat b, dba_hist_sysstat e
   WHERE     b.snap_id = :bid
         AND e.snap_id = :eid
         /*AND b.dbid = :dbid
         AND e.dbid = :dbid*/
         AND b.instance_number = :inst_num
         AND e.instance_number = :inst_num
         AND b.stat_id = e.stat_id
         AND e.stat_name NOT IN
                ('logons current',
                 'opened cursors current',
                 'workarea memory allocated',
                 'session cursor cache count',
                 'session uga memory',
                 'session uga memory max',
                 'session pga memory',
                 'session pga memory max')
         AND e.VALUE >= b.VALUE
         AND e.VALUE > 0
ORDER BY st
 /
clear    breaks  
@sqlplusset

