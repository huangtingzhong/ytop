-- File Name: sql_bind_by_sqlid.sql
-- Purpose: YashanDB Expand SQL text with bind values
-- Created: 20260516  by  huangtingzhong

--          from V$SQL_BIND_CAPTURE, ordered by POSITION.
-- Notes:
--   - YashanDB may use '?' or ':name' placeholders in SQL_FULLTEXT.
--   - ':name' binds use replace_first_outside_quotes (skip colons in literals).
--   - '?' binds use position-based replacement (see sql.sql).
--   - If V$SQL has no rows for the sql_id, print message and RETURN (no error).
--   - DATE/TIMESTAMP values are wrapped with to_date/to_timestamp (simple form).
-- Usage:
--   1) Edit c_sqlid below, then run with ysql -f this_file
-- =============================================================================

SET SERVEROUTPUT ON

DECLARE
  c_sqlid           CONSTANT VARCHAR2(64) := '&&sqlid';

  lvc_sql_text      VARCHAR2(32000);
  lvc_orig_sql_text VARCHAR2(32000);
  ln_child          NUMBER := 10000;
  lvc_repl          VARCHAR2(2000);
  lvc_bind          VARCHAR2(200);
  lvc_name          VARCHAR2(30);

  ln_bind_count     NUMBER := 0;
  ln_sql_cnt        NUMBER := 0;
  ln_qpos           NUMBER;

  CURSOR c1 IS
    SELECT child_number,
           name,
           position,
           datatype_string,
           value_string,
           sql_id
      FROM v$sql_bind_capture
     WHERE sql_id = c_sqlid
     ORDER BY child_number, position;

  -- Replace first bind token outside single-quoted literals (handles ':name' in SQL).
  FUNCTION replace_first_outside_quotes(
    p_text        IN VARCHAR2,
    p_pattern     IN VARCHAR2,
    p_replacement IN VARCHAR2
  ) RETURN VARCHAR2 IS
    v_pos      PLS_INTEGER := 1;
    v_len      PLS_INTEGER := NVL(LENGTH(p_text), 0);
    v_plen     PLS_INTEGER := NVL(LENGTH(p_pattern), 0);
    v_in_quote BOOLEAN := FALSE;
    v_result   VARCHAR2(32767) := '';
    v_ch       CHAR(1);
    v_next     CHAR(1);
  BEGIN
    IF v_len = 0 OR v_plen = 0 THEN
      RETURN p_text;
    END IF;

    WHILE v_pos <= v_len LOOP
      v_ch := SUBSTR(p_text, v_pos, 1);

      IF v_ch = '''' THEN
        IF v_in_quote
           AND v_pos < v_len
           AND SUBSTR(p_text, v_pos + 1, 1) = '''' THEN
          v_result := v_result || '''''';
          v_pos := v_pos + 2;
        ELSE
          v_in_quote := NOT v_in_quote;
          v_result := v_result || v_ch;
          v_pos := v_pos + 1;
        END IF;
      ELSIF NOT v_in_quote
            AND v_pos + v_plen - 1 <= v_len
            AND UPPER(SUBSTR(p_text, v_pos, v_plen)) = UPPER(p_pattern) THEN
        v_next := CASE
                    WHEN v_pos + v_plen <= v_len THEN SUBSTR(p_text, v_pos + v_plen, 1)
                    ELSE NULL
                  END;
        IF p_pattern LIKE ':%'
           AND v_next IS NOT NULL
           AND v_next BETWEEN '0' AND '9' THEN
          v_result := v_result || v_ch;
          v_pos := v_pos + 1;
        ELSE
          RETURN v_result || p_replacement || SUBSTR(p_text, v_pos + v_plen);
        END IF;
      ELSE
        v_result := v_result || v_ch;
        v_pos := v_pos + 1;
      END IF;
    END LOOP;

    RETURN v_result;
  END replace_first_outside_quotes;

  FUNCTION bind_pattern(p_name IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p_name LIKE ':SYS_B_%' THEN
      RETURN ':"' || SUBSTR(p_name, 2) || '"';
    ELSIF p_name LIKE ':%' THEN
      RETURN p_name;
    ELSIF p_name IS NOT NULL AND LENGTH(TRIM(p_name)) > 0 THEN
      RETURN ':' || LTRIM(p_name, ':');
    ELSE
      RETURN NULL;
    END IF;
  END bind_pattern;

  FUNCTION uses_question_bind(p_text IN VARCHAR2) RETURN BOOLEAN IS
    v_pos      PLS_INTEGER := 1;
    v_len      PLS_INTEGER := NVL(LENGTH(p_text), 0);
    v_in_quote BOOLEAN := FALSE;
    v_ch       CHAR(1);
  BEGIN
    WHILE v_pos <= v_len LOOP
      v_ch := SUBSTR(p_text, v_pos, 1);
      IF v_ch = '''' THEN
        IF v_in_quote
           AND v_pos < v_len
           AND SUBSTR(p_text, v_pos + 1, 1) = '''' THEN
          v_pos := v_pos + 2;
        ELSE
          v_in_quote := NOT v_in_quote;
          v_pos := v_pos + 1;
        END IF;
      ELSIF NOT v_in_quote AND v_ch = '?' THEN
        RETURN TRUE;
      ELSE
        v_pos := v_pos + 1;
      END IF;
    END LOOP;
    RETURN FALSE;
  END uses_question_bind;

BEGIN
  SELECT COUNT(*)
    INTO ln_sql_cnt
    FROM v$sql
   WHERE sql_id = c_sqlid;

  IF ln_sql_cnt = 0 THEN
    DBMS_OUTPUT.PUT_LINE('No SQL found in V$SQL for sql_id=' || c_sqlid);
    RETURN;
  END IF;

  SELECT sql_fulltext
    INTO lvc_orig_sql_text
    FROM v$sql
   WHERE sql_id = c_sqlid
     AND ROWNUM = 1;

  SELECT parsing_schema_name
    INTO lvc_name
    FROM v$sql
   WHERE sql_id = c_sqlid
     AND ROWNUM = 1;

  SELECT COUNT(*)
    INTO ln_bind_count
    FROM v$sql_bind_capture
   WHERE sql_id = c_sqlid;

  IF ln_bind_count = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Schema: ' || lvc_name);
    DBMS_OUTPUT.PUT_LINE(lvc_orig_sql_text);
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------');
    RETURN;
  END IF;

  FOR r1 IN c1 LOOP
    IF (r1.child_number <> ln_child) THEN
      IF ln_child <> 10000 THEN
        DBMS_OUTPUT.PUT_LINE('Schema: ' || lvc_name);
        DBMS_OUTPUT.PUT_LINE(lvc_sql_text);
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------');
      END IF;

      ln_child     := r1.child_number;
      lvc_sql_text := lvc_orig_sql_text;
    END IF;

    BEGIN
      SELECT parsing_schema_name
        INTO lvc_name
        FROM v$sql
       WHERE sql_id = r1.sql_id
         AND child_number = r1.child_number;
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;

    IF r1.value_string IS NULL THEN
      lvc_repl := 'NULL';
    ELSIF r1.datatype_string = 'NUMBER' THEN
      lvc_repl := r1.value_string;
    ELSIF r1.datatype_string = 'DATE' THEN
      lvc_repl := 'to_date(''' || r1.value_string || ''')';
    ELSIF r1.datatype_string LIKE 'TIMESTAMP%' THEN
      lvc_repl := 'to_timestamp(''' || r1.value_string || ''')';
    ELSE
      lvc_repl := '''' || REPLACE(r1.value_string, '''', '''''') || '''';
    END IF;

    lvc_bind := bind_pattern(r1.name);

    IF lvc_bind IS NOT NULL AND NOT uses_question_bind(lvc_orig_sql_text) THEN
      lvc_sql_text := replace_first_outside_quotes(lvc_sql_text, lvc_bind, lvc_repl);
    ELSE
      ln_qpos := INSTR(lvc_sql_text, '?');
      IF ln_qpos = 0 THEN
        DBMS_OUTPUT.PUT_LINE(
          'ERROR: no remaining ''?'' placeholders while replacing binds. ' ||
          'bind position=' || r1.position || ', name=' || NVL(r1.name, '(null)')
        );
        RETURN;
      END IF;

      lvc_sql_text :=
        SUBSTR(lvc_sql_text, 1, ln_qpos - 1) ||
        lvc_repl ||
        SUBSTR(lvc_sql_text, ln_qpos + 1);
    END IF;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Schema: ' || lvc_name);
  DBMS_OUTPUT.PUT_LINE(lvc_sql_text);
  DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------');
END;
/

