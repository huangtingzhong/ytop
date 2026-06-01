-- File Name: we_ra.sql
-- Purpose: Oracle We Ra
-- Created: 20260516  by  huangtingzhong

 SELECT s.ba_session_id, s.instance_id, s.sid, s.serial#, s.job_name
        , rt.task_id, rt.DB_KEY, rt.db_unique_name, rt.task_type, rt.state, rt.waiting_on
        , rt.elapsed_seconds
        , gs.module, gs.sql_id, gs.action--, gs.event
        , rt.BP_KEY, rt.bs_key, rt.df_key, rt.vb_key
 FROM sessions s
 JOIN ra_task rt
 ON rt.task_id = s.current_task
 JOIN gv$session gs
 ON gs.inst_id = s.instance_id
 AND gs.sid = s.sid
 AND gs.serial# = s.serial#
 ORDER BY rt.LAST_EXECUTE_TIME DESC
 /
