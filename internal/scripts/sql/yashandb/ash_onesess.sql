-- File Name: ash_onesess.sql
-- Purpose: YashanDB ASH detail for one session (GV$ASH, cluster)
-- Created: 20260613  by  huangtingzhong
-- Oracle ref: ash_onesess.sql
-- Variables: &btime (yyyy-mm-dd hh24:mi:ss), &hour (interval hours), &inst_id (ALL=all nodes), &sid

col time      for a19
col inst      for a3
col username  for a15
col sid       for a16
col sqlid     for a13
col event     for a20
col wait_class for a15
col program   for a15
col db_pct    for a8
col cpu_pct   for a8



SELECT TO_CHAR(ash.sample_time, 'yyyy-mm-dd hh24:mi:ss') AS time,
       TO_CHAR(ash.inst_id) AS inst,
       NVL(u.username, 'USER_' || ash.user_id) AS username,
       ash.inst_id || '.' || ash.session_id || '.' || ash.session_serial# AS sid,
       ash.sql_id AS sqlid,
       CASE
           WHEN ash.session_state = 'WAITING' THEN SUBSTR(ash.event, 1, 20)
           WHEN ash.session_state = 'ON CPU' THEN 'ON CPU'
           ELSE ash.session_state
       END AS event,
       ash.wait_class,
       SUBSTR(ash.program, 1, 15) AS program,
       TO_CHAR(ROUND(100 * ash.tm_delta_db_time / NULLIF(ash.tm_delta_time, 0), 2)) AS db_pct,
       TO_CHAR(ROUND(100 * ash.tm_delta_cpu_time / NULLIF(ash.tm_delta_time, 0), 2)) AS cpu_pct
  FROM gv$active_session_history ash
  LEFT JOIN dba_users u ON ash.user_id = u.user_id
 WHERE ash.is_awr_sample = 'N'
   AND ash.sample_time >= TO_DATE('&btime', 'yyyy-mm-dd hh24:mi:ss')
   AND ash.sample_time <= TO_DATE('&btime', 'yyyy-mm-dd hh24:mi:ss') + &hour / 24
   AND ash.session_id = &sid
   AND TO_CHAR(ash.inst_id) LIKE DECODE('&inst_id', 'ALL', '%', '&inst_id')
 ORDER BY ash.inst_id, ash.sample_time;
