-- File Name: ash_sess_total_num1.sql
-- Purpose: Oracle ASH session Total Num1
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 300 pages 5000 verify off heading on
col begin_time for a19

ACCEPT format prompt 'Enter Display Format (i.e. YYYY-MM-DD HH24:MI:SS|default(YYYY-MM-DD HH24:MI))) : ' default 'YYYY-MM-DD HH24:MI'
select begin_time,count(*) tatal_sess
  from (select to_char(sample_time, nvl('&&time_display_format','yyyy-mm-dd hh24:mi:ss') begin_time,
               session_id 
          from v$active_session_history a
         WHERE SAMPLE_TIME >= to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
           AND SAMPLE_TIME <=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')+nvl(&&interval_hours,2)/24    
        UNION ALL
        select to_char(sample_time, nvl('&&time_display_format','yyyy-mm-dd hh24:mi:ss') begin_time,
               session_id
          from DBA_HIST_ACTIVE_SESS_HISTORY b
         WHERE SAMPLE_TIME >= to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')
           AND SAMPLE_TIME <=
               to_date('&&begin_date', 'yyyy-mm-dd hh24:mi:ss')+nvl(&&interval_hours,2)/24
 group by begin_time
 order by begin_time
/
