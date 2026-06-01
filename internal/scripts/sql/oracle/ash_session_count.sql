-- File Name: ash_session_count.sql
-- Purpose: Oracle ASH Session Count
-- Created: 20260516  by  huangtingzhong

ACCEPT begin_hours prompt 'Enter Search Hours Ago (i.e. 2(default)) : '  default '2'
ACCEPT interval_hours prompt 'Enter How Interval Hours  (i.e. 2(default)) : ' default '2'
ACCEPT date_format prompt 'Enter Date Format (default YYYY-MM-DD HH24:MI:SS) ' default 'YYYY-MM-DD HH24:MI:SS'
variable begin_hours number;
variable interval_hours number;
variable date_format varchar2(100);
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   :date_format:='&date_format';
   end;
/
set pages 170
col stime for a20 heading 'SAMPLE_TIME'
col sample_id for 99999999999999
col tnum for 999999999999999 heading 'TOTAL_SESSION'
/* Formatted on 2016/6/17 13:43:24 (QP5 v5.256.13226.35510) */
  SELECT begin_time stime, COUNT (*) tnum
    FROM (SELECT TO_CHAR (sample_time, :date_format) begin_time
            FROM v$active_session_history a
           WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                 AND SAMPLE_TIME <=
                        SYSDATE - ( :begin_hours - :interval_hours) / 24
          UNION ALL
          SELECT TO_CHAR (sample_time, :date_format) begin_time
            FROM DBA_HIST_ACTIVE_SESS_HISTORY b
           WHERE     SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                 AND SAMPLE_TIME <=
                        SYSDATE - ( :begin_hours - :interval_hours) / 24)
GROUP BY begin_time
ORDER BY begin_time
/
