-- File Name: redo_drop.sql
-- Purpose: Drop redo by group id or file path
-- Created: 20260525  by  huangtingzhong

-- Usage: ytop prompts for substitution variable target (digits=group id, else path)
--   digits only     -> drop local redo group by ID (V$LOGFILE.ID)
--   non-numeric     -> drop redo by file path or directory prefix (GV$LOGFILE.NAME)
-- After drop, lists remaining redo (same columns as logfile.sql).

SET SERVEROUTPUT ON;

DECLARE
  p_target      VARCHAR2(512);
  p_max_switch  PLS_INTEGER   := 20;
  c_min_redo    CONSTANT PLS_INTEGER := 3;

  v_by_group    BOOLEAN;
  v_log_mode    VARCHAR2(32);
  v_noarchive   BOOLEAN;
  v_inst_id     PLS_INTEGER;
  v_status      VARCHAR2(32);
  v_switch_cnt  PLS_INTEGER;
  v_redo_count  PLS_INTEGER;
  v_sql         VARCHAR2(1024);
  v_start_ts    DATE;
  v_elapsed_ms  NUMBER;
  v_drop_cnt    PLS_INTEGER := 0;
  v_skip_cnt    PLS_INTEGER := 0;
  v_path_prefix VARCHAR2(512);

  FUNCTION is_digits(p_val VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    RETURN REGEXP_LIKE(TRIM(p_val), '^[0-9]+$');
  END is_digits;

  PROCEDURE switch_log_for_drop IS
  BEGIN
    IF v_noarchive THEN
      EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE';
    ELSE
      EXECUTE IMMEDIATE 'ALTER SYSTEM ARCHIVE LOG CURRENT';
    END IF;
  END switch_log_for_drop;

  PROCEDURE drop_one_redo(
    p_thread_id PLS_INTEGER,
    p_log_name  VARCHAR2,
    p_log_status VARCHAR2
  ) IS
  BEGIN
  DBMS_OUTPUT.PUT_LINE('Target [THREAD#=' || p_thread_id || '] ' || p_log_name || ' (status=' || p_log_status || ')');

  IF v_noarchive AND p_thread_id <> v_inst_id THEN
    v_skip_cnt := v_skip_cnt + 1;
    DBMS_OUTPUT.PUT_LINE('  SKIP (NOARCHIVELOG): peer THREAD#=' || p_thread_id ||
      ' redo cannot be switched from instance ' || v_inst_id ||
      '. Run on instance ' || p_thread_id || ' or enable ARCHIVELOG.');
    RETURN;
  END IF;

  v_status     := p_log_status;
  v_switch_cnt := 0;
  WHILE v_status IN ('CURRENT', 'ACTIVE') AND v_switch_cnt < p_max_switch LOOP
    v_switch_cnt := v_switch_cnt + 1;
    IF v_noarchive THEN
      DBMS_OUTPUT.PUT_LINE('  Switch logfile round ' || v_switch_cnt || '/' || p_max_switch);
    ELSE
      DBMS_OUTPUT.PUT_LINE('  Archive log current round ' || v_switch_cnt || '/' || p_max_switch);
    END IF;
    switch_log_for_drop;
    BEGIN
      SELECT TRIM(g.STATUS) INTO v_status
        FROM GV$LOGFILE g
       WHERE g.THREAD# = p_thread_id
         AND TRIM(g.NAME) = p_log_name;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        v_status := 'INACTIVE';
    END;
  END LOOP;

  IF v_status IN ('INACTIVE', 'NEW') THEN
    SELECT COUNT(*) INTO v_redo_count FROM GV$LOGFILE WHERE THREAD# = p_thread_id;
    IF v_redo_count <= c_min_redo THEN
      DBMS_OUTPUT.PUT_LINE('  SKIP drop: THREAD#=' || p_thread_id || ' only has ' || v_redo_count || ' redo (min ' || c_min_redo || ')');
    ELSE
      IF p_thread_id = v_inst_id THEN
        v_sql := 'ALTER DATABASE DROP LOGFILE ''' || REPLACE(p_log_name, '''', '''''') || '''';
      ELSE
        v_sql := 'ALTER DATABASE DROP LOGFILE THREAD ' || p_thread_id || ' ''' || REPLACE(p_log_name, '''', '''''') || '''';
      END IF;
      v_start_ts := SYSDATE;
      EXECUTE IMMEDIATE v_sql;
      v_elapsed_ms := ROUND((SYSDATE - v_start_ts) * 86400 * 1000);
      v_drop_cnt := v_drop_cnt + 1;
      DBMS_OUTPUT.PUT_LINE('[SQL] ' || v_sql || '  -- ' || v_elapsed_ms || ' ms');
    END IF;
  ELSE
    DBMS_OUTPUT.PUT_LINE('  WARN: skip drop (status=' || v_status || '), switch redo first (redo_switch.sql)');
  END IF;
  END drop_one_redo;

BEGIN
  IF LENGTH(TRIM('&target')) = 0 OR TRIM('&target') = CHR(38) || 'target' THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: Missing target. Pass redo group id (digits) or file/directory path.');
    RETURN;
  END IF;
  p_target := TRIM('&target');

  SELECT UPPER(TRIM(log_mode)) INTO v_log_mode FROM V$DATABASE;
  v_noarchive := (v_log_mode LIKE '%NOARCHIVE%');
  SELECT instance_number INTO v_inst_id FROM V$INSTANCE WHERE status = 'OPEN' AND ROWNUM = 1;
  v_by_group := is_digits(p_target);

  DBMS_OUTPUT.PUT_LINE('log_mode=' || v_log_mode || ', instance=' || v_inst_id);
  IF v_by_group THEN
    DBMS_OUTPUT.PUT_LINE('Mode=GROUP, target ID=' || p_target || ' (local V$LOGFILE)');
  ELSE
    v_path_prefix := RTRIM(p_target, '/');
    DBMS_OUTPUT.PUT_LINE('Mode=PATH, target=' || p_target);
  END IF;

  IF v_by_group THEN
    FOR rec IN (
      SELECT l.THREAD# AS thread_id,
             TRIM(l.NAME) AS log_name,
             l.STATUS AS log_status
        FROM V$LOGFILE l
       WHERE l.ID = TO_NUMBER(p_target)
    ) LOOP
      drop_one_redo(rec.thread_id, rec.log_name, rec.log_status);
    END LOOP;
  ELSE
    FOR rec IN (
      SELECT l.THREAD# AS thread_id,
             TRIM(l.NAME) AS log_name,
             l.STATUS AS log_status
        FROM GV$LOGFILE l
       WHERE TRIM(l.NAME) = TRIM(p_target)
          OR TRIM(l.NAME) LIKE v_path_prefix || '/%'
    ) LOOP
      drop_one_redo(rec.thread_id, rec.log_name, rec.log_status);
    END LOOP;
  END IF;

  IF v_drop_cnt = 0 AND v_skip_cnt = 0 THEN
    DBMS_OUTPUT.PUT_LINE('No matching redo found for target: ' || p_target);
  ELSE
    DBMS_OUTPUT.PUT_LINE('Dropped ' || v_drop_cnt || ' redo file(s), skipped ' || v_skip_cnt || '.');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    RAISE;
END;
/

select THREAD#,ID||'' groupid,NAME,trunc(BLOCK_SIZE*BLOCK_COUNT/1024/1024) size_m,status,type,SEQUENCE# from v$logfile;
