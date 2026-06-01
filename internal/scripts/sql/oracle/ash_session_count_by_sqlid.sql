-- File Name: ash_session_count_by_sqlid.sql
-- Purpose: Oracle ASH Session Count By Sqlid
-- Created: 20260516  by  huangtingzhong

ACCEPT begin_hours prompt 'Enter Search Hours Ago (i.e. 2(default)) : '  default '2'
ACCEPT interval_hours prompt 'Enter How Interval Hours  (i.e. 2(default)) : ' default '2'
ACCEPT sqlid prompt 'Enter How sqlid: ' 
variable begin_hours number;
variable interval_hours number;
variable sqlid varchar2(100);
begin
   :begin_hours:=&begin_hours;
   :interval_hours:=&interval_hours;
   :waitclass:='&waitclass';
   :sqlid:='&sqlid';
   end;
/
set pages 170
col stime for a20 heading 'SAMPLE_TIME'
col sample_id for 99999999999999
col tnum for 999999999999999
  SELECT stime, sample_id, COUNT (*) tnum
    FROM (SELECT TO_CHAR (SAMPLE_TIME, 'yyyy-mm-dd hh24:mi:ss') stime,
                 SAMPLE_ID,
                 SESSION_ID
            FROM GV$ACTIVE_SESSION_HISTORY
           WHERE     SAMPLE_TIME >= SYSDATE - 5 / 24
                 AND SAMPLE_TIME <= SYSDATE - (5 - 5) / 24
                 AND SQL_ID = 'g7y3nq90z8w5f'
          UNION ALL
          SELECT TO_CHAR (SAMPLE_TIME, 'yyyy-mm-dd hh24:mi:ss') stime,
                 SAMPLE_ID,
                 SESSION_ID
            FROM DBA_HIST_ACTIVE_SESS_HISTORY
           WHERE     SAMPLE_TIME >= SYSDATE - 5 / 24
                 AND SAMPLE_TIME <= SYSDATE - (5 - 5) / 24
                 AND SQL_ID = 'g7y3nq90z8w5f')
GROUP BY stime, sample_id
ORDER BY 1 
/