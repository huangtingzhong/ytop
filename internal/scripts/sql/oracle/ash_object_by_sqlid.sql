-- File Name: ash_object_by_sqlid.sql
-- Purpose: Oracle ASH Object By Sqlid
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 200 pages 1000 heading on verify off
col time           for a17
col event          for a40
col erows          for 999999999 heading 'EVENT|ROWS'
col epercent       for 99999999  heading 'EVENT%'
col orows          for 99999999  heading 'OBJECT|ROWS'
col opercent       for 99999999  heading 'OBJECT%'
ACCEPT begin_hours prompt 'Enter Search Hours Ago (i.e. 2(default)) : '  default '2'
ACCEPT interval_hours prompt 'Enter How Interval Hours  (i.e. 2(default)) : ' default '2'
ACCEPT sqlid prompt 'Enter Search Sqlid  (i.e. 2(all)) : ' default 'ALL'
ACCEPT display_time prompt 'Enter How Display Interval Minute  (i.e. 10(default)) : ' default '10'
variable begin_hours number;
variable interval_hours number;
variable time number;
variable sqlid varchar2(200);
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   :time:=&display_time;
   :sqlid:='&sqlid';
   end;
   /
break on time on sql_id on event on erows on epercent
/* Formatted on 2018/1/10 23:10:30 (QP5 v5.300) */
  SELECT time,
         sql_id,
         event,
         etop       erows,
         epercent,
         current_obj# object_id,
         rcount     orows,
         rpercent   opercent
    FROM (SELECT DISTINCT
                 time,
                 sql_id,
                 event,
                 SUM (cnt)
                     OVER (PARTITION BY time, sql_id, event ORDER BY event)
                     etop,
                   ROUND (
                         SUM (cnt)
                         OVER (PARTITION BY time, sql_id, event ORDER BY event)
                       / DECODE (
                             SUM (cnt)
                             OVER (PARTITION BY time, sql_id ORDER BY event),
                             '0', '1',
                             NULL, 1,
                             SUM (cnt)
                             OVER (PARTITION BY time, sql_id ORDER BY event)),
                       2)
                 * 100
                     epercent,
                 CURRENT_OBJ#,
                 SUM (cnt)
                     OVER (PARTITION BY time,
                                        sql_id,
                                        event,
                                        current_obj#)
                     rcount,
                   ROUND (
                         SUM (cnt)
                             OVER (PARTITION BY time,
                                                sql_id,
                                                event,
                                                current_obj#)
                       / DECODE (
                             SUM (cnt) OVER (PARTITION BY time, sql_id, event),
                             '0', '1',
                             NULL, 1,
                             SUM (cnt) OVER (PARTITION BY time, sql_id, event)),
                       2)
                 * 100
                     rpercent
            FROM (SELECT    TO_CHAR (DATE_HH, 'yyyymmdd hh24')
                         || ' '
                         || 10 * (DATE_MI)
                         || '-'
                         || 10 * (DATE_MI + 1)
                             time,
                         sql_id,
                         event,
                         current_obj#,
                         cnt
                    FROM (SELECT TRUNC (SAMPLE_TIME, 'HH') DATE_HH,
                                 TRUNC (TO_CHAR (SAMPLE_TIME, 'MI') / 10)
                                     DATE_MI,
                                 sql_id,
                                 event,
                                 CURRENT_OBJ#,
                                 1                       cnt
                            FROM GV$ACTIVE_SESSION_HISTORY
                           WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                                 AND SAMPLE_TIME <=
                                           SYSDATE
                                         -   (:begin_hours - :interval_hours)
                                           / 24
                                 AND sql_id =
                                         DECODE (:sqlid,
                                                 'ALL', sql_id,
                                                 :sqlid)
                          UNION ALL
                          SELECT TRUNC (SAMPLE_TIME, 'HH') DATE_HH,
                                 TRUNC (TO_CHAR (SAMPLE_TIME, 'MI') / 10)
                                     DATE_MI,
                                 sql_id,
                                 event,
                                 CURRENT_OBJ#,
                                 10                      cnt
                            FROM DBA_HIST_ACTIVE_SESS_HISTORY
                           WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                                 AND sql_id =
                                         DECODE (:sqlid,
                                                 'ALL', sql_id,
                                                 :sqlid)
                                 AND SAMPLE_TIME <=
                                           SYSDATE
                                         -   (:begin_hours - :interval_hours)
                                           / 24))) b
   WHERE (b.epercent > 50 AND b.rpercent > 30) AND etop > 100 AND rcount > 50
ORDER BY time, erows
/