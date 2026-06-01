-- File Name: logfile_add_redo.sql
-- Purpose: YashanDB Add or resize redo log groups online
-- Created: 20260516  by  huangtingzhong

set serveroutput on;
DECLARE

  c_default_cnt CONSTANT PLS_INTEGER := 10;
  c_default_mb  CONSTANT NUMBER       := 500;

  g_target_redo_count PLS_INTEGER;
  g_target_redo_mb    NUMBER;
  g_new_file_prefix   VARCHAR2(64) := 'ra';


  c_max_loop            CONSTANT PLS_INTEGER := 256;
  c_max_drop_retry      CONSTANT PLS_INTEGER := 256;  -- max DROP retries per file
  c_sleep_after_archive CONSTANT NUMBER       := 5;   -- sleep seconds after archive

  v_tgt_bytes NUMBER;
  v_dir         VARCHAR2(4000);
  v_cnt         PLS_INTEGER;
  v_min_bytes   NUMBER;
  v_ok          BOOLEAN;
  r_add         PLS_INTEGER;
  j             PLS_INTEGER;
  v_path        VARCHAR2(4000);
  v_sql         VARCHAR2(4000);
  v_batch       VARCHAR2(16);  -- 8-hex batch suffix per thread ADD batch
  v_thr         PLS_INTEGER;
  rc            SYS_REFCURSOR;

  TYPE t_tab IS TABLE OF VARCHAR2(4000);
  old_names t_tab;

  -- listing output row vars
  v_l_thr PLS_INTEGER;
  v_l_id  PLS_INTEGER;
  v_l_nm  VARCHAR2(4000);
  v_l_bs  PLS_INTEGER;
  v_l_bc  PLS_INTEGER;
  v_l_st  VARCHAR2(64);
  v_l_ty  VARCHAR2(64);
  v_l_sz  NUMBER;

  FUNCTION log_status_dyn(p_member VARCHAR2) RETURN VARCHAR2 IS
    v_st VARCHAR2(64);
  BEGIN
    EXECUTE IMMEDIATE 'SELECT MAX(status) FROM v$logfile WHERE name = :1'
      INTO v_st USING p_member;
    RETURN v_st;
  END;

  PROCEDURE exec_sql(p_sql VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
  END;

  PROCEDURE sleep_after_archive IS
  BEGIN
    BEGIN
      DBMS_LOCK.SLEEP(c_sleep_after_archive);
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END;

  PROCEDURE switch_until_inactive(p_member VARCHAR2) IS
    v_st VARCHAR2(64);
    n    PLS_INTEGER := 0;
  BEGIN
    LOOP
      v_st := log_status_dyn(p_member);
      EXIT WHEN v_st = 'INACTIVE';
      EXIT WHEN v_st IS NULL;
      IF v_st IN ('CURRENT', 'ACTIVE') THEN
        EXECUTE IMMEDIATE 'ALTER SYSTEM ARCHIVE LOG CURRENT';
        sleep_after_archive;
        BEGIN
          EXECUTE IMMEDIATE 'ALTER SYSTEM CHECKPOINT';
        EXCEPTION
          WHEN OTHERS THEN NULL;
        END;
      ELSE
        EXIT;
      END IF;
      n := n + 1;
      EXIT WHEN n >= c_max_loop;
    END LOOP;
  END;

  PROCEDURE safe_drop_member(p_member VARCHAR2) IS
    v_try  PLS_INTEGER := 0;
    v_ok   BOOLEAN := FALSE;
    v_sql  VARCHAR2(4000);
    v_last VARCHAR2(4000);
  BEGIN
    v_sql := 'ALTER DATABASE DROP LOGFILE ''' || REPLACE(p_member, '''', '''''') || '''';

    WHILE NOT v_ok LOOP
      v_try := v_try + 1;
      IF v_try > c_max_drop_retry THEN
        DBMS_OUTPUT.PUT_LINE('DROP abort after ' || c_max_drop_retry || ' tries: ' || p_member || ' — ' || v_last);
        RAISE VALUE_ERROR;
      END IF;

      switch_until_inactive(p_member);

      BEGIN
        exec_sql(v_sql);
        v_ok := TRUE;
      EXCEPTION
        WHEN OTHERS THEN
          v_last := SQLERRM;
          DBMS_OUTPUT.PUT_LINE('[DROP retry ' || v_try || '/' || c_max_drop_retry || '] ' || p_member || ' : ' || v_last);
          BEGIN
            EXECUTE IMMEDIATE 'ALTER SYSTEM ARCHIVE LOG CURRENT';
          EXCEPTION
            WHEN OTHERS THEN NULL;
          END;
          sleep_after_archive;
      END;
    END LOOP;
  END;

BEGIN
  DBMS_OUTPUT.PUT_LINE('=== REDO maint start ===');


  BEGIN
    IF LENGTH(TRIM('&count')) > 0 THEN
      g_target_redo_count := TO_NUMBER(TRIM('&count'));
    ELSE
      g_target_redo_count := c_default_cnt;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN g_target_redo_count := c_default_cnt;
  END;
  BEGIN
    IF LENGTH(TRIM('&size_mb')) > 0 THEN
      g_target_redo_mb := TO_NUMBER(TRIM('&size_mb'));
    ELSE
      g_target_redo_mb := c_default_mb;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN g_target_redo_mb := c_default_mb;
  END;
  v_tgt_bytes := ROUND(g_target_redo_mb * 1048576);

  DBMS_OUTPUT.PUT_LINE(
    '[CONFIG] target_groups=' || g_target_redo_count ||
    ' size_mb=' || g_target_redo_mb ||
    ' (defaults ' || c_default_cnt || '/' || c_default_mb || 'MB when args empty/invalid)'
  );

  IF g_target_redo_count <= 0 OR g_target_redo_mb <= 0 THEN
    DBMS_OUTPUT.PUT_LINE('Invalid config: target count and MB must be positive');
    RETURN;
  END IF;

  -- ----- 1) Inspect -----
  OPEN rc FOR 'SELECT DISTINCT THREAD# FROM v$logfile ORDER BY 1';
  LOOP
    FETCH rc INTO v_thr;
    EXIT WHEN rc%NOTFOUND;

    EXECUTE IMMEDIATE
      'SELECT COUNT(*), MIN(block_size * block_count) FROM v$logfile WHERE THREAD# = :b AND type = ''ONLINE'''
      INTO v_cnt, v_min_bytes USING v_thr;

    v_ok := (v_cnt >= g_target_redo_count) AND (v_min_bytes >= v_tgt_bytes);
    DBMS_OUTPUT.PUT_LINE(
      '[REPORT] THREAD=' || v_thr ||
      ' groups=' || v_cnt || '/' || g_target_redo_count ||
      ' min_bytes=' || NVL(v_min_bytes, 0) || '/' || v_tgt_bytes ||
      ' => ' || CASE WHEN v_ok THEN 'OK' ELSE 'NEED_WORK' END
    );
  END LOOP;
  CLOSE rc;

  -- ----- 2) ADD/DROP (always run) -----
  OPEN rc FOR 'SELECT DISTINCT THREAD# FROM v$logfile ORDER BY 1';
  LOOP
    FETCH rc INTO v_thr;
    EXIT WHEN rc%NOTFOUND;

    EXECUTE IMMEDIATE
      'SELECT COUNT(*), MIN(block_size * block_count) FROM v$logfile WHERE THREAD# = :b AND type = ''ONLINE'''
      INTO v_cnt, v_min_bytes USING v_thr;

    EXECUTE IMMEDIATE
      'SELECT SUBSTR(MIN(name), 1, INSTR(MIN(name), ''/'', -1) - 1) FROM v$logfile WHERE THREAD# = :b AND type = ''ONLINE'''
      INTO v_dir USING v_thr;

    IF v_dir IS NOT NULL THEN

      IF v_min_bytes < v_tgt_bytes THEN
        EXECUTE IMMEDIATE
          'SELECT name FROM v$logfile WHERE THREAD# = :b AND type = ''ONLINE'' ORDER BY id'
          BULK COLLECT INTO old_names USING v_thr;

        v_batch := SUBSTR(RAWTOHEX(SYS_GUID()), 1, 8);
        FOR j IN 1 .. g_target_redo_count LOOP
          v_path := v_dir || '/' || NVL(g_new_file_prefix, 'ra') || '_t' || v_thr || '_' || j || '_' || v_batch || '.log';
          v_sql := 'ALTER DATABASE ADD LOGFILE ''' || REPLACE(v_path, '''', '''''') || ''' SIZE ' || TRUNC(v_tgt_bytes);
          exec_sql(v_sql);
        END LOOP;

        IF old_names.COUNT > 0 THEN
          FOR j IN 1 .. old_names.COUNT LOOP
            safe_drop_member(old_names(j));
          END LOOP;
        END IF;

      ELSE
        IF v_cnt < g_target_redo_count THEN
          r_add := g_target_redo_count - v_cnt;
          v_batch := SUBSTR(RAWTOHEX(SYS_GUID()), 1, 8);
          FOR j IN 1 .. r_add LOOP
            v_path := v_dir || '/' || NVL(g_new_file_prefix, 'ra') || '_t' || v_thr || '_a' || j || '_' || v_batch || '.log';
            v_sql := 'ALTER DATABASE ADD LOGFILE ''' || REPLACE(v_path, '''', '''''') || ''' SIZE ' || TRUNC(v_tgt_bytes);
            exec_sql(v_sql);
          END LOOP;
        ELSIF v_cnt > g_target_redo_count THEN
          EXECUTE IMMEDIATE
            'SELECT name FROM (
               SELECT name FROM (
                 SELECT name,
                        CASE status WHEN ''INACTIVE'' THEN 1 ELSE 2 END AS ord,
                        id
                 FROM v$logfile
                 WHERE THREAD# = :b AND type = ''ONLINE''
                 ORDER BY ord, id DESC
               )
               WHERE ROWNUM <= :n
             )'
            BULK COLLECT INTO old_names USING v_thr, (v_cnt - g_target_redo_count);

          IF old_names.COUNT > 0 THEN
            FOR j IN 1 .. old_names.COUNT LOOP
              safe_drop_member(old_names(j));
            END LOOP;
          END IF;
        END IF;
      END IF;

    END IF;

  END LOOP;
  CLOSE rc;

  -- ----- 3) Current online redo listing -----
  DBMS_OUTPUT.PUT_LINE('=== CURRENT ONLINE REDO (after apply) ===');
  OPEN rc FOR
    'SELECT thread#, id, name, block_size, block_count, status, type FROM v$logfile ORDER BY thread#, id';
  LOOP
    FETCH rc INTO v_l_thr, v_l_id, v_l_nm, v_l_bs, v_l_bc, v_l_st, v_l_ty;
    EXIT WHEN rc%NOTFOUND;
    v_l_sz := v_l_bs * v_l_bc;
    DBMS_OUTPUT.PUT_LINE(
      'TH=' || v_l_thr ||
      ' ID=' || v_l_id ||
      ' PATH=' || v_l_nm ||
      ' SIZE_BYTES=' || v_l_sz ||
      ' SIZE_MB=' || ROUND(v_l_sz / 1048576, 2) ||
      ' STATUS=' || v_l_st ||
      ' TYPE=' || v_l_ty
    );
  END LOOP;
  CLOSE rc;

  DBMS_OUTPUT.PUT_LINE('=== REDO maint end ===');
END;
/
