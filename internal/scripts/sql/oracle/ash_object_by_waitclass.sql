-- File Name: ash_object_by_waitclass.sql
-- Purpose: Oracle ASH Object By Waitclass
-- Created: 20180111  by  huangtingzhong

-- TEL、weixin : 18081072613
-- http://www.htz.pw
-- 2018.01.11 drill-down after ash_total.sql
-- 2025.07.18 fix empty result when filtering ON CPU session_state
set echo off
set lines 300 pages 1000 heading on verify off
col time           for a17
col event          for a40
col erow           for 999999999   heading 'EVENT|ROWS'
col erowpercent    for 9999        heading 'EVENT%'
col sql_id         for a18
col sqlrow         for 99999999    heading 'EVENT|SQLID|ROWS'
col sqlrowpercent  for 99999       heading 'SQLID%'
col sqlobjrow      for 99999999    heading 'EVENT|SQLID|OBJECT|ROWS'
col sqlobjrowpercent     for 9999  heading 'OBJECT%'
ACCEPT begin_hours prompt 'Enter Search Hours Ago (i.e. 2(default)) : '  default '0.083'
ACCEPT interval_hours prompt 'Enter How Interval Hours  (i.e. 2(default)) : ' default '0.083'
ACCEPT waitclass prompt 'Enter Search Wait Class  (i.e. User I/O(default) Or ON CPU) : ' default 'User I/O'
ACCEPT display_time prompt 'Enter How Display Interval Minute  (i.e. 10(default)) : ' default '10'
ACCEPT sid_filter prompt 'Enter SID to filter (leave empty for all SIDs) : ' default ''
variable begin_hours number;
variable interval_hours number;
variable time number;
variable waitclass varchar2(200);
variable sid_filter varchar2(20);
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   :time:=&display_time;
   :waitclass:='&waitclass';
   :sid_filter:='&sid_filter';
   end;
   /
break on time on event on erow on erowpercent on sql_id on sqlrow on sqlrowpercent on object_id on sqlobjrow

/* Formatted on 2018/1/11 0:01:47 (QP5 v5.300) */
  SELECT time,
         event,
         erow,
--         erowpercent,
         sql_id,
         sqlrow,
--         sqlrowpercent,
         object_id,
         sqlobjrow
--       ,sqlobjrowpercent --,  erowtop,sqlrowtop, sqlobjrowtop
    FROM (SELECT time,
                 event,
                 erow,
                 erowpercent,
                 sql_id,
                 sqlrow,
                 sqlrowpercent,
                 current_obj# object_id,
                 sqlobjrow,
                 sqlobjrowpercent,
                 dense_rank ()
                     OVER (PARTITION BY time ORDER BY erow desc)
                     erowtop,
                 dense_rank ()
                 OVER (PARTITION BY time, event ORDER BY sqlrow  desc)
                     sqlrowtop,
                 dense_rank ()
                     OVER (PARTITION BY time,
                                        event,
                                        sql_id
                           ORDER BY sqlobjrow desc)
                     sqlobjrowtop
            FROM (SELECT DISTINCT
                         time,
                         sql_id,
                         event,
                         SUM (cnt) OVER (PARTITION BY time, event) erow,
                           ROUND (
                                 SUM (cnt) OVER (PARTITION BY time, event)
                               / DECODE (SUM (cnt) OVER (PARTITION BY time),
                                         '0', '1',
                                         NULL, 1,
                                         SUM (cnt) OVER (PARTITION BY time)),
                               2)
                         * 100
                             erowpercent,
                         CURRENT_OBJ#,
                         SUM (cnt) OVER (PARTITION BY time, event, sql_id)
                             sqlrow,
                           ROUND (
                                 SUM (cnt)
                                     OVER (PARTITION BY time, event, sql_id)
                               / DECODE (
                                     SUM (cnt) OVER (PARTITION BY time, event),
                                     '0', '1',
                                     NULL, 1,
                                     SUM (cnt) OVER (PARTITION BY time, event)),
                               2)
                         * 100
                             sqlrowpercent,
                         SUM (cnt)
                             OVER (PARTITION BY time,
                                                event,
                                                sql_id,
                                                current_obj#)
                             sqlobjrow,
                           ROUND (
                                 SUM (cnt)
                                     OVER (PARTITION BY time,
                                                        event,
                                                        sql_id,
                                                        current_obj#)
                               / DECODE (
                                     SUM (cnt)
                                     OVER (PARTITION BY time, event, sql_id),
                                     '0', '1',
                                     NULL, 1,
                                     SUM (cnt)
                                     OVER (PARTITION BY time, event, sql_id)),
                               2)
                         * 100
                             sqlobjrowpercent
                    FROM (SELECT    TO_CHAR (DATE_HH, 'yyyymmdd hh24')
                                 || ' '
                                 || 10 * (DATE_MI)
                                 || '-'
                                 || 10 * (DATE_MI + 1)
                                     time,
                                 sql_id,
                                 event,
                                 current_obj#,
                                 wait_class,
                                 cnt
                            FROM (SELECT TRUNC (SAMPLE_TIME, 'HH') DATE_HH,
                                         TRUNC (
                                             TO_CHAR (SAMPLE_TIME, 'MI') / 10)
                                             DATE_MI,
                                         sql_id,
                                         nvl(event,session_state) event,
                                         CURRENT_OBJ#,
                                         WAIT_CLASS,
                                         1                       cnt
                                    FROM GV$ACTIVE_SESSION_HISTORY
                                   WHERE     SAMPLE_TIME >=
                                                 SYSDATE - :begin_hours / 24
                                         AND SAMPLE_TIME <=
                                                   SYSDATE
                                                 -   (  :begin_hours
                                                      - :interval_hours)
                                                   / 24
                                         AND (WAIT_CLASS = :waitclass or SESSION_STATE=:waitclass)
                                         AND (:sid_filter IS NULL OR :sid_filter = '' OR SESSION_ID = :sid_filter)
                                  UNION ALL
                                  SELECT TRUNC (SAMPLE_TIME, 'HH') DATE_HH,
                                         TRUNC (
                                             TO_CHAR (SAMPLE_TIME, 'MI') / 10)
                                             DATE_MI,
                                         sql_id,
                                         nvl(event,session_state) event,
                                         CURRENT_OBJ#,
                                         WAIT_CLASS,
                                         10                      cnt
                                    FROM DBA_HIST_ACTIVE_SESS_HISTORY
                                   WHERE     SAMPLE_TIME >=
                                                 SYSDATE - :begin_hours / 24
                                         AND (WAIT_CLASS = :waitclass or SESSION_STATE=:waitclass)
                                         AND (:sid_filter IS NULL OR :sid_filter = '' OR SESSION_ID = :sid_filter)
                                         AND SAMPLE_TIME <=
                                                   SYSDATE
                                                 -   (  :begin_hours
                                                      - :interval_hours)
                                                   / 24))) b)
   WHERE erowtop < 3 AND sqlrowtop < 3 AND sqlobjrowtop < 3
ORDER BY time,
         erow,
         sqlrow,
         sqlobjrow
/
