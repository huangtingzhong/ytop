-- File Name: redo_switch.sql
-- Purpose: Switch redo log per archive or noarchive mode
-- Created: 20260525  by  huangtingzhong

-- ARCHIVELOG:     ALTER SYSTEM ARCHIVE LOG CURRENT (YAC cluster-wide)
-- NOARCHIVELOG:   ALTER SYSTEM SWITCH LOGFILE (local instance only)

SET SERVEROUTPUT ON;

DECLARE
  v_log_mode  VARCHAR2(32);
  v_noarchive BOOLEAN;
  v_inst_id   PLS_INTEGER;
  v_sql       VARCHAR2(64);
  v_start_ts  DATE;
  v_elapsed_ms NUMBER;
BEGIN
  SELECT UPPER(TRIM(log_mode)) INTO v_log_mode FROM V$DATABASE;
  v_noarchive := (v_log_mode LIKE '%NOARCHIVE%');
  SELECT instance_number INTO v_inst_id FROM V$INSTANCE WHERE status = 'OPEN' AND ROWNUM = 1;

  IF v_noarchive THEN
    v_sql := 'ALTER SYSTEM SWITCH LOGFILE';
  ELSE
    v_sql := 'ALTER SYSTEM ARCHIVE LOG CURRENT';
  END IF;

  DBMS_OUTPUT.PUT_LINE('log_mode=' || v_log_mode || ', instance=' || v_inst_id);
  DBMS_OUTPUT.PUT_LINE('Executing: ' || v_sql);

  v_start_ts := SYSDATE;
  EXECUTE IMMEDIATE v_sql;
  v_elapsed_ms := ROUND((SYSDATE - v_start_ts) * 86400 * 1000);
  DBMS_OUTPUT.PUT_LINE('Done in ' || v_elapsed_ms || ' ms');

  DBMS_OUTPUT.PUT_LINE('--- Current redo (V$LOGFILE) ---');
  FOR r IN (
    SELECT l.THREAD#, l.ID, TRIM(l.NAME) AS log_name, l.STATUS
      FROM V$LOGFILE l
     ORDER BY l.THREAD#, l.ID
  ) LOOP
    DBMS_OUTPUT.PUT_LINE('THREAD#=' || r.THREAD# || ' ID=' || r.ID || ' STATUS=' || r.STATUS || ' ' || r.log_name);
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    RAISE;
END;
/
