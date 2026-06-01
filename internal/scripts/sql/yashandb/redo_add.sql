-- File Name: redo_add.sql
-- Purpose: YashanDB Recreate redo logs by count size and path
-- Created: 20260309  by  huangtingzhong

-- Params: p_redo_count (default 6 per instance), p_redo_size (default 4G), p_redo_path (default empty, from V$LOGFILE)
-- NOARCHIVELOG: only ALTER SYSTEM SWITCH LOGFILE on local instance; peer instance redo must be dropped on that node.

SET SERVEROUTPUT ON;

DECLARE
  -- ========== edit these three lines for count/size/path==========
  p_redo_count  PLS_INTEGER   := nvl(&redocount,6);                    -- redo groups per instance (default 6)
  p_redo_size   VARCHAR2(32)  := nvl('&size','4G');                 -- redo size (default 4G)
  p_redo_path   VARCHAR2(512) := nvl('&path','');           -- target path; empty = from V$LOGFILE
  p_max_switch  PLS_INTEGER   := 20;                  -- max log switches before drop
  -- ========================================================

  v_default_path   VARCHAR2(512);
  v_target_path    VARCHAR2(512);
  v_target_bytes   NUMBER;
  v_redo_name      VARCHAR2(512);
  v_status        VARCHAR2(32);
  v_switch_cnt    PLS_INTEGER;
  v_sql           VARCHAR2(1024);
  v_size_str      VARCHAR2(32);
  v_i             PLS_INTEGER;
  v_redo_count    PLS_INTEGER;   -- current redo count; keep >= 3 after drop
  c_min_redo      CONSTANT PLS_INTEGER := 3;  -- YashanDB minimum online redo files
  v_start_ts      DATE;          -- SQL start time for elapsed ms
  v_elapsed_ms    NUMBER;        -- elapsed milliseconds
  v_exists        PLS_INTEGER;   -- 1 if member name exists in V$LOGFILE
  v_retry         PLS_INTEGER;   -- suffix retry on name conflict
  c_max_retry     CONSTANT PLS_INTEGER := 99;  -- max retries per file name
  v_match_count   PLS_INTEGER;   -- redo files matching path and size
  v_inst_id       PLS_INTEGER;   -- current OPEN instance id
  v_log_mode      VARCHAR2(32);  -- ARCHIVELOG / NOARCHIVELOG from V$DATABASE
  v_noarchive     BOOLEAN;       -- true when log_mode is NOARCHIVELOG
  v_open_inst_cnt PLS_INTEGER;   -- OPEN instances in cluster
  v_skip_peer_cnt PLS_INTEGER := 0;  -- peer-instance redo skipped in NOARCHIVE mode

  -- Convert p_redo_size (e.g. 200M/1G) to bytes
  FUNCTION size_to_bytes(p_size VARCHAR2) RETURN NUMBER IS
    v_s VARCHAR2(32);
    v_n NUMBER;
  BEGIN
    v_s := TRIM(UPPER(p_size));
    IF REGEXP_LIKE(v_s, '^[0-9]+M$') THEN
      v_n := TO_NUMBER(REGEXP_SUBSTR(v_s, '^[0-9]+'));
      RETURN v_n * 1024 * 1024;
    ELSIF REGEXP_LIKE(v_s, '^[0-9]+G$') THEN
      v_n := TO_NUMBER(REGEXP_SUBSTR(v_s, '^[0-9]+'));
      RETURN v_n * 1024 * 1024 * 1024;
    ELSIF REGEXP_LIKE(v_s, '^[0-9]+$') THEN
      RETURN TO_NUMBER(v_s);
    ELSE
      RAISE_APPLICATION_ERROR(-20001, 'Invalid redo size format: ' || p_size || ', use 200M, 1G or bytes');
    END IF;
  END size_to_bytes;

  -- Switch log so CURRENT/ACTIVE redo can become INACTIVE before DROP.
  PROCEDURE switch_log_for_drop IS
  BEGIN
    IF v_noarchive THEN
      EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE';
    ELSE
      EXECUTE IMMEDIATE 'ALTER SYSTEM ARCHIVE LOG CURRENT';
    END IF;
  END switch_log_for_drop;

BEGIN
  -- 0) Database log mode and cluster layout
  SELECT UPPER(TRIM(log_mode)) INTO v_log_mode FROM V$DATABASE;
  v_noarchive := (v_log_mode LIKE '%NOARCHIVE%');
  SELECT COUNT(*) INTO v_open_inst_cnt FROM GV$INSTANCE WHERE STATUS = 'OPEN';
  SELECT instance_number INTO v_inst_id FROM V$INSTANCE WHERE status = 'OPEN' AND ROWNUM = 1;

  DBMS_OUTPUT.PUT_LINE('Database log_mode=' || v_log_mode || ', OPEN instances=' || v_open_inst_cnt || ', connected instance=' || v_inst_id);
  IF v_noarchive THEN
    DBMS_OUTPUT.PUT_LINE('NOARCHIVELOG: use SWITCH LOGFILE on local instance only; cannot switch peer instance redo from here.');
    IF v_open_inst_cnt > 1 THEN
      DBMS_OUTPUT.PUT_LINE('YAC hint: run this script on each instance to drop that instance THREAD# redo, or enable ARCHIVELOG.');
    END IF;
  ELSE
    DBMS_OUTPUT.PUT_LINE('ARCHIVELOG: use ARCHIVE LOG CURRENT (cluster-wide redo switch on YAC).');
  END IF;

  -- 1) Parse target size in bytes
  v_target_bytes := size_to_bytes(p_redo_size);
  v_size_str     := p_redo_size;

  -- 2) Resolve target path from V$LOGFILE if not specified
  IF p_redo_path IS NULL OR TRIM(p_redo_path) = '' THEN
    SELECT SUBSTR(TRIM(NAME), 1,
                  LENGTH(TRIM(NAME)) - LENGTH(SUBSTRING_INDEX(TRIM(NAME), '/', -1)) - 1)
      INTO v_default_path
      FROM (SELECT NAME FROM V$LOGFILE WHERE ROWNUM = 1);
    v_target_path := RTRIM(v_default_path);
    DBMS_OUTPUT.PUT_LINE('Using default redo path: ' || v_target_path);
  ELSE
    v_target_path := RTRIM(TRIM(p_redo_path));
    IF SUBSTR(v_target_path, -1) = '/' THEN
      v_target_path := RTRIM(SUBSTR(v_target_path, 1, LENGTH(v_target_path) - 1));
    END IF;
    -- YAC disk group: append /dbfiles when path starts with +
    IF SUBSTR(v_target_path, 1, 1) = '+' THEN
      v_target_path := v_target_path || '/dbfiles';
      DBMS_OUTPUT.PUT_LINE('YAC disk group detected, redo path: ' || v_target_path);
    END IF;
  END IF;

  DBMS_OUTPUT.PUT_LINE('Target path=' || v_target_path || ', size=' || v_size_str || ' (' || v_target_bytes || ' bytes), required ' || p_redo_count || ' file(s) per instance (YAC cluster: count is per instance, not whole DB).');

  -- Skip add if enough redo files already match path and size (local V$LOGFILE view)
  SELECT COUNT(*) INTO v_match_count
    FROM V$LOGFILE l
   WHERE SUBSTR(TRIM(l.NAME), 1, LENGTH(TRIM(l.NAME)) - LENGTH(SUBSTRING_INDEX(TRIM(l.NAME), '/', -1)) - 1) = v_target_path
     AND (l.BLOCK_SIZE * l.BLOCK_COUNT) = v_target_bytes;
  IF v_match_count >= p_redo_count THEN
    DBMS_OUTPUT.PUT_LINE('Already satisfied: ' || v_match_count || ' redo file(s) match path and size (required >= ' || p_redo_count || '), skip adding.');
  ELSE
  -- 3) Add new redo files with unique names
  FOR v_i IN 1 .. (p_redo_count - v_match_count) LOOP
    v_retry := 0;
    LOOP
      IF v_retry = 0 THEN
        v_redo_name := v_target_path || '/redo_' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || '_' || v_i || '.log';
      ELSE
        v_redo_name := v_target_path || '/redo_' || TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') || '_' || v_i || '_' || v_retry || '.log';
      END IF;
      SELECT COUNT(*) INTO v_exists FROM V$LOGFILE WHERE TRIM(NAME) = v_redo_name;
      EXIT WHEN v_exists = 0;
      v_retry := v_retry + 1;
      IF v_retry > c_max_retry THEN
        RAISE_APPLICATION_ERROR(-20002, 'Cannot get unique redo name for ' || v_i || ' after ' || c_max_retry || ' retries');
      END IF;
    END LOOP;
    v_sql       := 'ALTER DATABASE ADD LOGFILE ''' || REPLACE(v_redo_name, '''', '''''') || ''' SIZE ' || v_size_str;
    v_start_ts  := SYSDATE;
    EXECUTE IMMEDIATE v_sql;
    v_elapsed_ms := ROUND((SYSDATE - v_start_ts) * 86400 * 1000);
    DBMS_OUTPUT.PUT_LINE('[SQL] ' || v_sql || '  -- ' || v_elapsed_ms || ' ms');
  END LOOP;
  END IF;

  -- 4) Drop redo on all instances that mismatch path or size
  DBMS_OUTPUT.PUT_LINE('Drop phase: connected instance ' || v_inst_id || ' (other instances must be OPEN for GV$ view).');

  FOR rec IN (
    SELECT l.THREAD# AS thread_id,
           TRIM(l.NAME) AS log_name,
           l.BLOCK_SIZE * l.BLOCK_COUNT AS file_bytes,
           l.STATUS AS log_status
      FROM GV$LOGFILE l
     WHERE ( SUBSTR(TRIM(l.NAME), 1, LENGTH(TRIM(l.NAME)) - LENGTH(SUBSTRING_INDEX(TRIM(l.NAME), '/', -1)) - 1) <> v_target_path
             OR (l.BLOCK_SIZE * l.BLOCK_COUNT) <> v_target_bytes
           )
  ) LOOP
    DBMS_OUTPUT.PUT_LINE('Process redo [THREAD#=' || rec.thread_id || ']: ' || rec.log_name || ' (status=' || rec.log_status || ')');

  IF v_noarchive AND rec.thread_id <> v_inst_id THEN
    v_skip_peer_cnt := v_skip_peer_cnt + 1;
    DBMS_OUTPUT.PUT_LINE('  SKIP drop (NOARCHIVELOG): peer instance THREAD#=' || rec.thread_id ||
      ' redo cannot be switched from instance ' || v_inst_id ||
      '. Run redo_add.sql on instance ' || rec.thread_id || ' to switch/drop, or use ARCHIVELOG.');
  ELSE

    v_status     := rec.log_status;
    v_switch_cnt := 0;
    WHILE v_status IN ('CURRENT', 'ACTIVE') AND v_switch_cnt < p_max_switch LOOP
      v_switch_cnt := v_switch_cnt + 1;
      IF v_noarchive THEN
        DBMS_OUTPUT.PUT_LINE('  Switch logfile (local THREAD#=' || rec.thread_id || ') round ' || v_switch_cnt || '/' || p_max_switch);
      ELSE
        DBMS_OUTPUT.PUT_LINE('  Archive log current round ' || v_switch_cnt || '/' || p_max_switch);
      END IF;
      switch_log_for_drop;
      BEGIN
        SELECT TRIM(g.STATUS) INTO v_status FROM GV$LOGFILE g WHERE g.THREAD# = rec.thread_id AND TRIM(g.NAME) = rec.log_name;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          v_status := 'INACTIVE';
      END;
    END LOOP;

    IF v_status IN ('INACTIVE', 'NEW') THEN
      SELECT COUNT(*) INTO v_redo_count FROM GV$LOGFILE WHERE THREAD# = rec.thread_id;
      IF v_redo_count <= c_min_redo THEN
        DBMS_OUTPUT.PUT_LINE('  SKIP drop ' || rec.log_name || ': instance ' || rec.thread_id || ' only has ' || v_redo_count || ' redo (min ' || c_min_redo || ')');
      ELSE
        IF rec.thread_id = v_inst_id THEN
          v_sql := 'ALTER DATABASE DROP LOGFILE ''' || REPLACE(rec.log_name, '''', '''''') || '''';
        ELSE
          v_sql := 'ALTER DATABASE DROP LOGFILE THREAD ' || rec.thread_id || ' ''' || REPLACE(rec.log_name, '''', '''''') || '''';
        END IF;
        v_start_ts := SYSDATE;
        EXECUTE IMMEDIATE v_sql;
        v_elapsed_ms := ROUND((SYSDATE - v_start_ts) * 86400 * 1000);
        DBMS_OUTPUT.PUT_LINE('[SQL] ' || v_sql || '  -- ' || v_elapsed_ms || ' ms');
      END IF;
    ELSE
      IF v_noarchive THEN
        DBMS_OUTPUT.PUT_LINE('  WARN: skip drop ' || rec.log_name || ' (status=' || v_status ||
          '). NOARCHIVELOG: SWITCH LOGFILE only cycles local redo; add more local redo groups or retry after workload idle.');
      ELSE
        DBMS_OUTPUT.PUT_LINE('  WARN: skip drop ' || rec.log_name || ' (status=' || v_status || '), need manual switch later');
      END IF;
    END IF;

  END IF;
  END LOOP;

  IF v_skip_peer_cnt > 0 THEN
    DBMS_OUTPUT.PUT_LINE('--- NOARCHIVELOG summary: ' || v_skip_peer_cnt ||
      ' peer-instance redo file(s) skipped on instance ' || v_inst_id ||
      '. Connect to each peer and re-run, or enable ARCHIVELOG for cluster-wide switch.');
  END IF;

  -- 5) List current redo from V$LOGFILE
  DBMS_OUTPUT.PUT_LINE('--- Current redo (V$LOGFILE) ---');
  DBMS_OUTPUT.PUT_LINE(RPAD('ID', 6) || ' ' || RPAD('THREAD#', 8) || ' ' || RPAD('NAME', 68) || ' ' || RPAD('SIZE_MB', 10) || ' ' || 'STATUS');
  DBMS_OUTPUT.PUT_LINE(LPAD('-', 6, '-') || ' ' || LPAD('-', 8, '-') || ' ' || LPAD('-', 68, '-') || ' ' || LPAD('-', 10, '-') || ' ' || '------');
  FOR r IN (SELECT l.ID, l.THREAD#, TRIM(l.NAME) AS log_name, ROUND((l.BLOCK_SIZE * l.BLOCK_COUNT) / 1024 / 1024) AS size_mb, l.STATUS FROM V$LOGFILE l ORDER BY l.THREAD#, l.ID) LOOP
    DBMS_OUTPUT.PUT_LINE(LPAD(r.ID, 6) || ' ' || LPAD(NVL(TO_CHAR(r.THREAD#), '-'), 8) || ' ' || RPAD(SUBSTR(r.log_name, 1, 68), 68) || ' ' || LPAD(r.size_mb, 10) || ' ' || r.STATUS);
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('--- End of V$LOGFILE ---');

  DBMS_OUTPUT.PUT_LINE('Done.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    RAISE;
END;
/
