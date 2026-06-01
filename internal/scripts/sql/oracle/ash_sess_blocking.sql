-- File Name: ash_sess_blocking.sql
-- Purpose: Oracle ASH session Blocking
-- Created: 20260516  by  huangtingzhong

select *
  from (select to_char(sample_time, 'yyyy-mm-dd hh24:mi:ss') begin_time,
               substr(event, 1, 24) event,
               a.BLOCKING_SESSION_STATUS || ':' || a.BLOCKING_INST_ID || ':' ||
               a.BLOCKING_SESSION block_s,
               session_id,
               session_type,
               b.username,
               sql_id,
               sql_opname
          from gv$active_session_history a, dba_users b
         WHERE SAMPLE_TIME >= to_date('&btime', 'YYYY-MM-DD HH24:MI:SS')
           AND SAMPLE_TIME <=
               (to_date('&btime', 'YYYY-MM-DD HH24:MI:SS') + &hour / 24)
           and b.user_id = a.user_id
           and ((A.BLOCKING_SESSION_STATUS = 'VALID') or
               (sample_time, session_id, a.inst_id) in
               (select distinct sample_time,
                                 a.BLOCKING_SESSION,
                                 a.BLOCKING_INST_ID
                   from v$active_session_history a
                  WHERE SAMPLE_TIME >=
                        to_date('&btime', 'YYYY-MM-DD HH24:MI:SS')
                    AND SAMPLE_TIME <=
                        (to_date('&btime', 'YYYY-MM-DD HH24:MI:SS') +
                        &hour / 24)
                    and a.BLOCKING_SESSION_STATUS = 'VALID'))
        UNION ALL
        select to_char(sample_time, 'yyyy-mm-dd hh24:mi:ss') begin_time,
               substr(event, 1, 24),
               d.BLOCKING_SESSION_STATUS || ':' || d.BLOCKING_INST_ID || ':' ||
               d.BLOCKING_SESSION block_s,
               session_id,
               c.username,
               session_type,
               sql_id,
               sql_opname
          from DBA_HIST_ACTIVE_SESS_HISTORY d, dba_users c
         WHERE SAMPLE_TIME >= to_date('&btime', 'YYYY-MM-DD HH24:MI:SS')
           AND SAMPLE_TIME <=
               (to_date('&btime', 'YYYY-MM-DD HH24:MI:SS') + &hour / 24)
           and c.user_id = d.user_id
           AND ((d.blocking_session_status = 'VALID') or
               ((sample_time, session_id, d.instance_number) in
               (select distinct sample_time,
                                  e.BLOCKING_INST_ID,
                                  e.BLOCKING_SESSION
                    from DBA_HIST_ACTIVE_SESS_HISTORY e
                   WHERE SAMPLE_TIME >=
                         to_date('&btime', 'YYYY-MM-DD HH24:MI:SS')
                     AND SAMPLE_TIME <=
                         (to_date('&btime', 'YYYY-MM-DD HH24:MI:SS') +
                         &hour / 24)
                     and e.blocking_session_status = 'VALID'))))
 order by begin_time
