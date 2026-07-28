-- File Name: standby.sql
-- Purpose: YashanDB standby HA env check and sync status (single / YAC)
-- Created: 20260516  by  huangtingzhong
--
-- Order: identity -> config -> storage/logs -> sync status -> apply -> threads
-- Layout: each result set width kept <= ~250 cols for terminal.
-- YAC: GV$ for instance-scoped views; single instance returns 1 row.
-- Empty sections are normal when role/config does not apply.
-- Note: section titles use SELECT FROM dual (standby-safe); DBMS_OUTPUT
--       package calls are not available on YashanDB read-only instances.

SET SERVEROUTPUT OFF
SET FEEDBACK OFF
SET VERIFY OFF

col section for a72

-- =====================================================================
-- A. Identity
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Instances (YAC: all nodes; single: one row)
-- ---------------------------------------------------------------------
SELECT '=== 1. instances (gv$instance) ===' AS section FROM dual;

col i           for a2
col inst_name   for a14
col host        for a14
col ver         for a12
col status      for a8
col db_status   for a12
col startup     for a19
col role_i      for a12

SELECT TO_CHAR(instance_number) AS i,
       instance_name            AS inst_name,
       host_name                AS host,
       REGEXP_SUBSTR(version, '[0-9]+(\.[0-9]+)+') AS ver,
       status,
       database_status          AS db_status,
       TO_CHAR(startup_time, 'yyyy-mm-dd hh24:mi:ss') AS startup,
       instance_role            AS role_i
  FROM gv$instance
 ORDER BY instance_number;

-- ---------------------------------------------------------------------
-- 2. Database role / protection / redo points
-- ---------------------------------------------------------------------
SELECT '=== 2. database (v$database) ===' AS section FROM dual;

col role        for a14
col open_mode   for a12
col log_mode    for a12
col db_stat     for a12
col fb          for a3
col scn         for a20
col pmode       for a20
col plevel      for a20
col sw_status   for a16
col rcy_point   for a24
col flush_point for a24
col reset_point for a16

SELECT database_role     AS role,
       open_mode,
       log_mode,
       status            AS db_stat,
       flashback_on      AS fb,
       TO_CHAR(current_scn) AS scn,
       protection_mode   AS pmode,
       protection_level  AS plevel,
       switchover_status AS sw_status,
       rcy_point,
       flush_point,
       reset_point
  FROM v$database;

-- =====================================================================
-- B. Configuration
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3. HA / DG related parameters (incl. LISTEN_ADDR / REPLICATION_ADDR)
-- ---------------------------------------------------------------------
SELECT '=== 3. HA/DG parameters (gv$parameter) ===' AS section FROM dual;

col name        for a40
col value       for a80
col def_val     for a24

SELECT TO_CHAR(inst_id) AS i,
       name,
       value,
       default_value    AS def_val
  FROM (
        SELECT inst_id, name, value, default_value
          FROM gv$parameter
        UNION ALL
        SELECT inst_id, name, value, default_value
          FROM gx$parameter
       ) p
 WHERE (
         name LIKE 'HA_%'
      OR name LIKE 'OM_ELECTION%'
      OR name LIKE 'FAILOVER_%'
      OR name LIKE 'ARCHIVELOG_%'
      OR name LIKE 'ARCHIVE_LOCAL%'
      OR name LIKE 'REPLICATION%'
      OR name LIKE 'STANDBY%'
      OR name LIKE 'QUORUM_SYNC%'
      OR name LIKE 'REQUIRED_SYNC%'
      OR name LIKE 'BLOCK_REPAIR%'
      OR name = 'LISTEN_ADDR'
      OR name = 'RECOVERY_PARALLELISM'
      OR name = 'REDO_FILE_NAME_CONVERT'
      OR name = 'DB_FILE_NAME_CONVERT'
      OR name = 'DB_BUCKET_NAME_CONVERT'
      OR (name LIKE 'ARCHIVE_DEST_%'
          AND value IS NOT NULL
          AND LENGTH(TRIM(value)) > 0)
       )
 ORDER BY inst_id, name;

-- ---------------------------------------------------------------------
-- 4. Archive dest config
-- ---------------------------------------------------------------------
SELECT '=== 4. archive dest (v$archive_dest) ===' AS section FROM dual;

col dest_id     for a3
col dest_name   for a14
col service     for a28
col db_name     for a14
col valid_now   for a3
col valid_role  for a10
col affirm      for a3
col timeout     for a8
col no_elect    for a3
col node_id     for a18

SELECT TO_CHAR(dest_id) AS dest_id,
       dest_name,
       service,
       db_unique_name   AS db_name,
       valid_now,
       valid_role,
       affirm,
       TO_CHAR(net_timeout) AS timeout,
       disable_election     AS no_elect,
       node_id
  FROM v$archive_dest
 ORDER BY dest_id;

-- =====================================================================
-- C. Storage / log layout
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5. Datafile path prefixes
-- ---------------------------------------------------------------------
SELECT '=== 5. datafile path prefix (v$datafile) ===' AS section FROM dual;

col data_dir    for a64
col file_cnt    for a8

SELECT CASE
         WHEN INSTR(name, '/') > 0 THEN
           SUBSTR(name, 1, INSTR(name, '/', -1) - 1)
         ELSE
           name
       END AS data_dir,
       TO_CHAR(COUNT(*)) AS file_cnt
  FROM v$datafile
 GROUP BY CASE
            WHEN INSTR(name, '/') > 0 THEN
              SUBSTR(name, 1, INSTR(name, '/', -1) - 1)
            ELSE
              name
          END
 ORDER BY data_dir;

-- ---------------------------------------------------------------------
-- 6. Online redo log files (TYPE=ONLINE)
-- ---------------------------------------------------------------------
SELECT '=== 6. online redo (v$logfile TYPE=ONLINE) ===' AS section FROM dual;

col thr         for a2
col id          for a3
col type        for a8
col size_m      for a6
col seq         for a8
col arch        for a3
col health      for a14
col name        for a72

SELECT TO_CHAR(thread#) AS thr,
       TO_CHAR(id)      AS id,
       type,
       status,
       TO_CHAR(TRUNC(block_size * block_count / 1024 / 1024)) AS size_m,
       TO_CHAR(sequence#) AS seq,
       archived           AS arch,
       health,
       name
  FROM v$logfile
 WHERE type = 'ONLINE'
 ORDER BY thread#, id;

-- ---------------------------------------------------------------------
-- 7. Standby redo log files (TYPE=STANDBY)
-- ---------------------------------------------------------------------
SELECT '=== 7. standby redo (v$logfile TYPE=STANDBY) ===' AS section FROM dual;

SELECT TO_CHAR(thread#) AS thr,
       TO_CHAR(id)      AS id,
       type,
       status,
       TO_CHAR(TRUNC(block_size * block_count / 1024 / 1024)) AS size_m,
       TO_CHAR(sequence#) AS seq,
       archived           AS arch,
       health,
       name
  FROM v$logfile
 WHERE type = 'STANDBY'
 ORDER BY thread#, id;

-- =====================================================================
-- D. Sync status (runtime)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 8. Dest status: sync + points (PRIMARY)
-- ---------------------------------------------------------------------
SELECT '=== 8. dest status (v$archive_dest_status) ===' AS section FROM dual;

col peer_addr   for a22
col conn        for a12
col sync_st     for a12
col db_mode     for a8
col syncd       for a3
col gap         for a8
col disc_at     for a14
col recv_seq    for a8
col recv_lfn    for a12
col app_seq     for a8
col app_lfn     for a12
col flush_lfn   for a12
col recv_scn    for a18

SELECT TO_CHAR(dest_id) AS dest_id,
       db_unique_name   AS db_name,
       peer_addr,
       connection       AS conn,
       status           AS sync_st,
       database_mode    AS db_mode,
       synchronized     AS syncd,
       gap_status       AS gap,
       TO_CHAR(disconnect_time, 'mm-dd hh24:mi') AS disc_at,
       TO_CHAR(received_seq#) AS recv_seq,
       TO_CHAR(received_lfn)  AS recv_lfn,
       TO_CHAR(applied_seq#)  AS app_seq,
       TO_CHAR(applied_lfn)   AS app_lfn,
       TO_CHAR(flush_lfn)     AS flush_lfn,
       TO_CHAR(received_scn)  AS recv_scn
  FROM v$archive_dest_status
 ORDER BY dest_id;

-- ---------------------------------------------------------------------
-- 9. Replication status (STANDBY)
-- ---------------------------------------------------------------------
SELECT '=== 9. replication (v$replication_status) ===' AS section FROM dual;

col peer_role   for a8
col peer_mode   for a8
col t_lag       for a8
col a_lag       for a8
col finish      for a8
col gap_seq     for a8
col last_msg    for a8
col peer_pt     for a18
col recv_pt     for a18
col apply_pt    for a18
col peer_node   for a12
col fo_trig     for a8
col error       for a40

SELECT TO_CHAR(thread#) AS thr,
       connection       AS conn,
       status           AS sync_st,
       peer_role,
       peer_mode,
       peer_addr,
       TO_CHAR(transport_lag)       AS t_lag,
       TO_CHAR(apply_lag)           AS a_lag,
       TO_CHAR(apply_finish_time)   AS finish,
       TO_CHAR(gap_seq#)            AS gap_seq,
       TO_CHAR(time_since_last_msg) AS last_msg,
       peer_point       AS peer_pt,
       received_point   AS recv_pt,
       applied_point    AS apply_pt,
       peer_node_id     AS peer_node,
       trigger_cond_failover AS fo_trig,
       error
  FROM v$replication_status
 ORDER BY thread#;

-- ---------------------------------------------------------------------
-- 10. Archive gap
-- ---------------------------------------------------------------------
SELECT '=== 10. archive gap (gv$archive_gap) ===' AS section FROM dual;

col gap_id      for a4
col low_seq     for a8
col high_seq    for a8
col gap_cnt     for a8

SELECT TO_CHAR(inst_id) AS i,
       TO_CHAR(id)      AS gap_id,
       TO_CHAR(low_sequence#)  AS low_seq,
       TO_CHAR(high_sequence#) AS high_seq,
       TO_CHAR(high_sequence# - low_sequence# + 1) AS gap_cnt
  FROM gv$archive_gap
 ORDER BY inst_id, id;

-- =====================================================================
-- E. Apply / recovery
-- =====================================================================

-- ---------------------------------------------------------------------
-- 11. Recovery status
-- ---------------------------------------------------------------------
SELECT '=== 11. recovery status (gv$recovery_status) ===' AS section FROM dual;

col parallel    for a4
col start_t     for a19
col stop_t      for a19
col replay_pt   for a28

SELECT TO_CHAR(inst_id) AS i,
       TO_CHAR(thread#) AS thr,
       status,
       TO_CHAR(parallelism) AS parallel,
       TO_CHAR(start_recovery_time, 'yyyy-mm-dd hh24:mi:ss') AS start_t,
       TO_CHAR(stop_recovery_time, 'yyyy-mm-dd hh24:mi:ss')  AS stop_t,
       replay_point AS replay_pt
  FROM gv$recovery_status
 ORDER BY inst_id, thread#;

-- ---------------------------------------------------------------------
-- 12. Recovery progress (raw rows)
-- ---------------------------------------------------------------------
SELECT '=== 12. recovery progress (gv$recovery_progress) ===' AS section FROM dual;

col item        for a28
col units       for a14
col value       for a18

SELECT TO_CHAR(inst_id) AS i,
       item,
       units,
       TO_CHAR(value) AS value
  FROM gv$recovery_progress
 ORDER BY inst_id, item;

-- =====================================================================
-- F. HA background threads
-- =====================================================================

-- ---------------------------------------------------------------------
-- 13. HA redo / replication threads (we.sql style: session + process)
-- ---------------------------------------------------------------------
SELECT '=== 13. HA threads (gv$session/gv$process) ===' AS section FROM dual;

col sid_tid     for a28
col thr_name    for a16
col thr_st      for a14
col event       for a30

SELECT TO_CHAR(b.inst_id) AS i,
       CASE
         WHEN a.sid IS NOT NULL THEN
           a.inst_id||'.'||a.sid||'.'||a.serial#||'.'||b.thread_id
         ELSE
           b.inst_id||'.-.-.'||b.thread_id
       END AS sid_tid,
       b.name AS thr_name,
       b.status AS thr_st,
       NVL(SUBSTR(a.wait_event, 1, 30), '-') AS event
  FROM gv$process b
  LEFT JOIN gv$session a
    ON a.inst_id = b.inst_id
   AND a.paddr = b.thread_addr
 WHERE b.name IN (
         'RD_SEND',
         'RD_RECV',
         'STBY_RCY',
         'RCY_REPL',
         'FAL_CLI',
         'LOGW',
         'RD_ARCH',
         'REPL_TCP_LSNR',
         'REPL_WORKER'
       )
 ORDER BY b.inst_id, b.name, b.thread_id;
