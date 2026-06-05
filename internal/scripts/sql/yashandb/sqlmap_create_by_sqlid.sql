-- File Name: sqlmap_create_by_sqlid.sql
-- Purpose: YashanDB Create SQLMAP from two v$sql sql_ids
-- Created: 20260604  by  huangtingzhong
--
-- Usage: yasql/ytop -f this_file (prompts &&source_sqlid, &&target_sqlid)
--   Empty &&target_sqlid: preview only (print CREATE SQLMAP DDL, no execute);
--   map_sql uses same text as source sql_fulltext.
-- Requires: DBA; mapped SQL must be DML; SQL_MAP=true for mapping to take effect.
-- Limits: sql/map_sql each <= 32000 bytes (Release Notes 23.2.1+).
-- Errors (RAISE_APPLICATION_ERROR, YashanDB positive errcode 30000..99999):
--   30201 source sql_id not in v$sql
--   30202 target sql_id not in v$sql
--   30203 v$sql not accessible
--   30204 CREATE SQLMAP failed
--   30205 SQL text exceeds 32000 bytes
--   30206 SQL is not a DML statement (SELECT/INSERT/UPDATE/DELETE/MERGE)

SET SERVEROUTPUT ON

DECLARE
  c_max_sql_bytes  CONSTANT PLS_INTEGER := 32000;

  v_source_sqlid   VARCHAR2(32)  := TRIM('&&source_sqlid');
  v_target_sqlid   VARCHAR2(32)  := TRIM('&&target_sqlid');
  v_preview_only   BOOLEAN;
  v_source_exists  NUMBER;
  v_target_exists  NUMBER;
  v_source_sql     VARCHAR2(32767);
  v_target_sql     VARCHAR2(32767);
  v_map_name       VARCHAR2(128);
  v_ddl            VARCHAR2(32767);
  v_dummy          NUMBER;
  v_sql_map        VARCHAR2(16);

  FUNCTION is_dml_sql(p_sql IN VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    RETURN REGEXP_LIKE(TRIM(p_sql), '^\s*(SELECT|INSERT|UPDATE|DELETE|MERGE)\b', 'i');
  END;

  FUNCTION err_msg(p_prefix IN VARCHAR2, p_detail IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN SUBSTR(p_prefix || NVL(p_detail, ''), 1, 900);
  END;

  -- Empty target: preview DDL only; map_sql = source sql_fulltext
  FUNCTION is_empty_target(p_sqlid IN VARCHAR2) RETURN BOOLEAN IS
    v_norm VARCHAR2(64);
  BEGIN
    IF p_sqlid IS NULL THEN
      RETURN TRUE;
    END IF;
    v_norm := LOWER(TRIM(p_sqlid));
    IF LENGTH(v_norm) = 0 THEN
      RETURN TRUE;
    END IF;
    IF v_norm IN ('&&target_sqlid', '&target_sqlid') THEN
      RETURN TRUE;
    END IF;
    RETURN FALSE;
  END;

  PROCEDURE put_long_line(p_text IN VARCHAR2) IS
    c_chunk CONSTANT PLS_INTEGER := 4000;
    v_len   PLS_INTEGER;
    v_pos   PLS_INTEGER := 1;
  BEGIN
    IF p_text IS NULL THEN
      RETURN;
    END IF;
    v_len := LENGTH(p_text);
    WHILE v_pos <= v_len LOOP
      DBMS_OUTPUT.PUT_LINE(SUBSTR(p_text, v_pos, c_chunk));
      v_pos := v_pos + c_chunk;
    END LOOP;
  END;

BEGIN
  -- 1. Check v$sql exists
  BEGIN
    EXECUTE IMMEDIATE 'SELECT 1 FROM v$sql WHERE ROWNUM = 1' INTO v_dummy;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(30203,
        err_msg('v$sql does not exist or is not accessible: ', SQLERRM));
  END;

  -- 2. source sql_id
  SELECT COUNT(*) INTO v_source_exists
    FROM v$sql
   WHERE sql_id = v_source_sqlid;

  IF v_source_exists = 0 THEN
    RAISE_APPLICATION_ERROR(30201,
      'Source sql_id not found in v$sql: ' || v_source_sqlid);
  END IF;

  v_preview_only := is_empty_target(v_target_sqlid);

  -- 3. target sql_id (skip when preview: empty target_sqlid)
  IF NOT v_preview_only THEN
    SELECT COUNT(*) INTO v_target_exists
      FROM v$sql
     WHERE sql_id = v_target_sqlid;

    IF v_target_exists = 0 THEN
      RAISE_APPLICATION_ERROR(30202,
        'Target sql_id not found in v$sql: ' || v_target_sqlid);
    END IF;
  END IF;

  -- 4. Full SQL text (sql_text is truncated; use sql_fulltext)
  SELECT TRIM(sql_fulltext) INTO v_source_sql
    FROM v$sql
   WHERE sql_id = v_source_sqlid
     AND ROWNUM = 1;

  IF v_preview_only THEN
    v_target_sql := v_source_sql;
  ELSE
    SELECT TRIM(sql_fulltext) INTO v_target_sql
      FROM v$sql
     WHERE sql_id = v_target_sqlid
       AND ROWNUM = 1;
  END IF;

  IF LENGTHB(v_source_sql) > c_max_sql_bytes OR LENGTHB(v_target_sql) > c_max_sql_bytes THEN
    RAISE_APPLICATION_ERROR(30205,
      'SQL text exceeds ' || c_max_sql_bytes || ' bytes (source/target sql_fulltext)');
  END IF;

  IF NOT is_dml_sql(v_source_sql) OR NOT is_dml_sql(v_target_sql) THEN
    RAISE_APPLICATION_ERROR(30206,
      'SQLMAP requires DML SQL (SELECT/INSERT/UPDATE/DELETE/MERGE) in v$sql');
  END IF;

  v_source_sql := REPLACE(v_source_sql, '''', '''''');
  IF v_preview_only THEN
    v_target_sql := v_source_sql;
  ELSE
    v_target_sql := REPLACE(v_target_sql, '''', '''''');
  END IF;

  IF v_preview_only THEN
    v_map_name := 'map_' || v_source_sqlid || '_'
               || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISS');
  ELSE
    v_map_name := 'map_' || v_source_sqlid || '_' || v_target_sqlid || '_'
               || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISS');
  END IF;

  -- 5. CREATE SQLMAP DDL ( ALL , 'sql' , 'map_sql' )
  v_ddl := 'CREATE SQLMAP ' || v_map_name
        || ' (ALL, ''' || v_source_sql || ''', ''' || v_target_sql || ''')';

  IF v_preview_only THEN
    DBMS_OUTPUT.PUT_LINE('-- preview only (target_sqlid empty), not executed');
    DBMS_OUTPUT.PUT_LINE('  source sql_id: ' || v_source_sqlid);
    DBMS_OUTPUT.PUT_LINE('  map_sql: same as source sql_fulltext');
    DBMS_OUTPUT.PUT_LINE('-- CREATE SQLMAP DDL:');
    put_long_line(v_ddl);
    RETURN;
  END IF;

  BEGIN
    SELECT UPPER(TRIM(value)) INTO v_sql_map
      FROM v$parameter
     WHERE LOWER(name) = 'sql_map'
       AND ROWNUM = 1;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      v_sql_map := NULL;
  END;

  IF NVL(v_sql_map, 'FALSE') NOT IN ('TRUE', 'ON', '1', 'YES') THEN
    DBMS_OUTPUT.PUT_LINE('WARN: SQL_MAP is not enabled; CREATE SQLMAP succeeds but mapping is inactive.');
  END IF;

  -- 6. Drop existing SQLMAP with same name (ignore if not exists)
  BEGIN
    EXECUTE IMMEDIATE 'DROP SQLMAP ' || v_map_name;
    DBMS_OUTPUT.PUT_LINE('Dropped existing SQLMAP: ' || v_map_name);
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  BEGIN
    EXECUTE IMMEDIATE v_ddl;
    DBMS_OUTPUT.PUT_LINE('SQLMAP created: ' || v_map_name);
    DBMS_OUTPUT.PUT_LINE('  source sql_id: ' || v_source_sqlid);
    DBMS_OUTPUT.PUT_LINE('  target sql_id: ' || v_target_sqlid);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('CREATE SQLMAP failed: ' || SQLERRM);
      RAISE_APPLICATION_ERROR(30204,
        err_msg('CREATE SQLMAP failed: ', SQLERRM));
  END;
END;
/
