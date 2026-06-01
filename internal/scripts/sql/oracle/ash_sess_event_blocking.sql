-- File Name: ash_sess_event_blocking.sql
-- Purpose: Oracle ASH session Event Blocking
-- Created: 20260516  by  huangtingzhong

set pages 1000
set lines 270;
set verify off
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col seq# for 999999999 heaidng 'seq#'
col begin_time for a19
col session_type for a14
col sql_id for a18
col sql_opname for a15
col session_id for 999999999999999999
col event for a25
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display session :active,INACTIVE,all                                   |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
ACCEPT btime prompt 'Enter Search before hours (i.e. 2012-01-01 23:00:00) : ' default sysdate-1
ACCEPT hour prompt 'Enter Search jiange hours (i.e. 123| default 1)) : ' default 1

select to_char(sample_time, 'yyyy-mm-dd hh24:mi:ss') begin_time,
       substr(event, 1, 24) event,
       a.BLOCKING_SESSION_STATUS || ':' || a.BLOCKING_INST_ID || ':' ||
       a.BLOCKING_SESSION block_s,
       session_type,
       b.username,
       sql_id,
       sql_opname,
       session_id
  from v$active_session_history a, dba_users b
 WHERE SAMPLE_TIME >= to_date('&btime', 'YYYY-MM-DD HH24:MI:SS')
   AND SAMPLE_TIME <=
       (to_date('&btime', 'YYYY-MM-DD HH24:MI:SS') + &hour / 24)
   and b.user_id = a.user_id
UNION ALL
select to_char(sample_time, 'yyyy-mm-dd hh24:mi:ss') begin_time,
       substr(event, 1, 24),
       b.BLOCKING_SESSION_STATUS || ':' || b.BLOCKING_INST_ID || ':' ||
       b.BLOCKING_SESSION block_s,
       c.username,
       session_type,
       sql_id,
       sql_opname,
       session_id
  from DBA_HIST_ACTIVE_SESS_HISTORY b, dba_users c
 WHERE SAMPLE_TIME >= to_date('&btime', 'YYYY-MM-DD HH24:MI:SS')
   AND SAMPLE_TIME <=
       (to_date('&btime', 'YYYY-MM-DD HH24:MI:SS') + &hour / 24)
   and c.user_id = b.user_id
 order by begin_time, event
/