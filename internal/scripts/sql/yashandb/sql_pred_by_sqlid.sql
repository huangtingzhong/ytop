-- File Name: sql_pred_by_sqlid.sql
-- Purpose: Literal SQL and EXPLAIN paste with predicates by sql_id (CLOB-safe)
-- Created: 20260802  by  huangtingzhong
-- Notes:
--   Combines sql.sql LITERAL SQL bind expansion with plan_pred_by_sqlid EXPLAIN paste.
--   1) Bind placeholders replaced with captured values (same rules as sql.sql).
--   2) Prints ALTER SESSION SET CURRENT_SCHEMA + EXPLAIN + literal SQL for predicates.
--      Top-level EXPLAIN required; EXECUTE IMMEDIATE does not show PLAN_DESCRIPTION.
--   3) CURRENT_SCHEMA from parsing_schema_name per child (unqualified object names).
--   4) sql_fulltext as CLOB (SQL length > 32K safe; UTF8 chunk=1000).
--   5) Optional child_number; empty = all children. For plan tree use plan_pred_by_sqlid.
--   6) Also lists BIND CAPTURE and compact V$SQLAREA stats (from sql.sql focus).

SET SERVEROUTPUT ON
SET HEADING ON

UNDEFINE sqlid
UNDEFINE child

PROMPT Enter sql_id (required):
ACCEPT sqlid
PROMPT Enter child_number (empty=all children):
ACCEPT child

PROMPT
PROMPT ****************************************************************************************
PROMPT CHILDREN / SCHEMA for sql_id = &&sqlid
PROMPT ****************************************************************************************

SELECT TO_CHAR(s.child_number) AS child#,
       s.parsing_schema_name AS schema_name,
       TO_CHAR(s.plan_hash_value) AS plan_hash,
       TO_CHAR(s.executions) AS execs,
       SUBSTR(REPLACE(REPLACE(s.sql_text, CHR(10), ' '), CHR(13), ' '), 1, 80) AS sql_preview
  FROM v$sql s
 WHERE s.sql_id = '&&sqlid'
   AND (TRIM('&&child') IS NULL
        OR TO_CHAR(s.child_number) = TRIM('&&child'))
 ORDER BY s.child_number
/

PROMPT
PROMPT ****************************************************************************************
PROMPT LITERAL SQL + EXPLAIN PASTE (predicates via EXPLAIN; run paste block separately)
PROMPT ****************************************************************************************

DECLARE
  c_sqlid      CONSTANT VARCHAR2(64) := TRIM('&&sqlid');
  c_child_in   CONSTANT VARCHAR2(32) := TRIM('&&child');
  -- UTF8: keep chunk small for DBMS_OUTPUT / WRITEAPPEND byte limits
  c_chunk      CONSTANT PLS_INTEGER := 1000;

  lvc_sql_text      CLOB;
  lvc_orig_sql_text CLOB;
  lvc_repl          VARCHAR2(4000);
  lvc_bind          VARCHAR2(200);
  lvc_name          VARCHAR2(128);
  ln_qpos           NUMBER;
  ln_sql_cnt        NUMBER := 0;
  ln_child_cnt      NUMBER := 0;
  ln_err            NUMBER := 0;
  ln_sql_len        NUMBER := 0;

  FUNCTION clob_char(p_clob IN CLOB, p_pos IN NUMBER) RETURN VARCHAR2 IS
  BEGIN
    IF p_pos < 1 OR p_pos > NVL(DBMS_LOB.GETLENGTH(p_clob), 0) THEN
      RETURN NULL;
    END IF;
    RETURN DBMS_LOB.SUBSTR(p_clob, 1, p_pos);
  END;

  FUNCTION is_ident_char(p_ch IN VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    IF p_ch IS NULL THEN
      RETURN FALSE;
    END IF;
    RETURN (p_ch >= '0' AND p_ch <= '9')
        OR (UPPER(p_ch) >= 'A' AND UPPER(p_ch) <= 'Z')
        OR p_ch = '_';
  END;

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
  END;

  FUNCTION uses_question_bind_clob(p_clob IN CLOB) RETURN BOOLEAN IS
    v_p   NUMBER := 1;
    v_len NUMBER := NVL(DBMS_LOB.GETLENGTH(p_clob), 0);
    v_inq BOOLEAN := FALSE;
    v_ch  VARCHAR2(8);
  BEGIN
    WHILE v_p <= v_len LOOP
      v_ch := clob_char(p_clob, v_p);
      IF v_ch = '''' THEN
        IF v_inq AND v_p < v_len AND clob_char(p_clob, v_p + 1) = '''' THEN
          v_p := v_p + 2;
        ELSE
          v_inq := NOT v_inq;
          v_p := v_p + 1;
        END IF;
      ELSIF NOT v_inq AND v_ch = '?' THEN
        RETURN TRUE;
      ELSE
        v_p := v_p + 1;
      END IF;
    END LOOP;
    RETURN FALSE;
  END;

  FUNCTION find_question_clob(p_clob IN CLOB) RETURN NUMBER IS
    v_p   NUMBER := 1;
    v_len NUMBER := NVL(DBMS_LOB.GETLENGTH(p_clob), 0);
    v_inq BOOLEAN := FALSE;
    v_ch  VARCHAR2(8);
  BEGIN
    WHILE v_p <= v_len LOOP
      v_ch := clob_char(p_clob, v_p);
      IF v_ch = '''' THEN
        IF v_inq AND v_p < v_len AND clob_char(p_clob, v_p + 1) = '''' THEN
          v_p := v_p + 2;
        ELSE
          v_inq := NOT v_inq;
          v_p := v_p + 1;
        END IF;
      ELSIF NOT v_inq AND v_ch = '?' THEN
        RETURN v_p;
      ELSE
        v_p := v_p + 1;
      END IF;
    END LOOP;
    RETURN 0;
  END;

  FUNCTION find_pattern_clob(p_clob IN CLOB, p_pattern IN VARCHAR2) RETURN NUMBER IS
    v_p    NUMBER := 1;
    v_len  NUMBER := NVL(DBMS_LOB.GETLENGTH(p_clob), 0);
    v_plen NUMBER := NVL(LENGTH(p_pattern), 0);
    v_inq  BOOLEAN := FALSE;
    v_ch   VARCHAR2(8);
    v_next VARCHAR2(8);
    v_frag VARCHAR2(4000);
  BEGIN
    IF v_plen = 0 OR v_plen > 4000 THEN
      RETURN 0;
    END IF;
    WHILE v_p <= v_len LOOP
      v_ch := clob_char(p_clob, v_p);
      IF v_ch = '''' THEN
        IF v_inq AND v_p < v_len AND clob_char(p_clob, v_p + 1) = '''' THEN
          v_p := v_p + 2;
        ELSE
          v_inq := NOT v_inq;
          v_p := v_p + 1;
        END IF;
      ELSIF NOT v_inq AND v_p + v_plen - 1 <= v_len THEN
        v_frag := DBMS_LOB.SUBSTR(p_clob, v_plen, v_p);
        IF UPPER(v_frag) = UPPER(p_pattern) THEN
          v_next := clob_char(p_clob, v_p + v_plen);
          IF p_pattern LIKE ':%' AND is_ident_char(v_next) THEN
            v_p := v_p + 1;
          ELSE
            RETURN v_p;
          END IF;
        ELSE
          v_p := v_p + 1;
        END IF;
      ELSE
        v_p := v_p + 1;
      END IF;
    END LOOP;
    RETURN 0;
  END;

  PROCEDURE clob_splice_replace(
    p_clob        IN OUT NOCOPY CLOB,
    p_start       IN NUMBER,
    p_match_len   IN NUMBER,
    p_replacement IN VARCHAR2
  ) IS
    v_new CLOB;
    v_len NUMBER;
    v_off NUMBER;
    v_amt NUMBER;
    v_buf VARCHAR2(4000);
  BEGIN
    v_len := NVL(DBMS_LOB.GETLENGTH(p_clob), 0);
    DBMS_LOB.CREATETEMPORARY(v_new, TRUE);

    v_off := 1;
    WHILE v_off < p_start LOOP
      v_amt := LEAST(c_chunk, p_start - v_off);
      v_buf := DBMS_LOB.SUBSTR(p_clob, v_amt, v_off);
      DBMS_LOB.WRITEAPPEND(v_new, LENGTH(v_buf), v_buf);
      v_off := v_off + v_amt;
    END LOOP;

    IF p_replacement IS NOT NULL AND LENGTH(p_replacement) > 0 THEN
      DBMS_LOB.WRITEAPPEND(v_new, LENGTH(p_replacement), p_replacement);
    END IF;

    v_off := p_start + p_match_len;
    WHILE v_off <= v_len LOOP
      v_amt := LEAST(c_chunk, v_len - v_off + 1);
      v_buf := DBMS_LOB.SUBSTR(p_clob, v_amt, v_off);
      DBMS_LOB.WRITEAPPEND(v_new, LENGTH(v_buf), v_buf);
      v_off := v_off + v_amt;
    END LOOP;

    IF DBMS_LOB.ISTEMPORARY(p_clob) = 1 THEN
      DBMS_LOB.FREETEMPORARY(p_clob);
    END IF;
    p_clob := v_new;
  END;

  PROCEDURE put_clob(p_text IN CLOB) IS
    v_len NUMBER;
    v_off NUMBER := 1;
    v_buf VARCHAR2(4000);
  BEGIN
    IF p_text IS NULL THEN
      DBMS_OUTPUT.PUT_LINE('');
      RETURN;
    END IF;
    v_len := NVL(DBMS_LOB.GETLENGTH(p_text), 0);
    IF v_len = 0 THEN
      DBMS_OUTPUT.PUT_LINE('');
      RETURN;
    END IF;
    WHILE v_off <= v_len LOOP
      v_buf := DBMS_LOB.SUBSTR(p_text, LEAST(c_chunk, v_len - v_off + 1), v_off);
      DBMS_OUTPUT.PUT_LINE(v_buf);
      v_off := v_off + c_chunk;
    END LOOP;
  END;

  PROCEDURE clob_rtrim_sql(p_clob IN OUT NOCOPY CLOB) IS
    v_len NUMBER;
    v_ch  VARCHAR2(8);
  BEGIN
    v_len := NVL(DBMS_LOB.GETLENGTH(p_clob), 0);
    WHILE v_len > 0 LOOP
      v_ch := clob_char(p_clob, v_len);
      IF v_ch IN (' ', ';', CHR(10), CHR(13), CHR(9)) THEN
        DBMS_LOB.TRIM(p_clob, v_len - 1);
        v_len := v_len - 1;
      ELSE
        EXIT;
      END IF;
    END LOOP;
  END;

  PROCEDURE emit_explain_block(
    p_schema IN VARCHAR2,
    p_child  IN NUMBER,
    p_sql    IN CLOB
  ) IS
    v_sql CLOB := p_sql;
  BEGIN
    clob_rtrim_sql(v_sql);
    DBMS_OUTPUT.PUT_LINE('-- ===== EXPLAIN paste block BEGIN =====');
    DBMS_OUTPUT.PUT_LINE('-- sql_id=' || c_sqlid
      || ' child#=' || TO_CHAR(p_child)
      || ' schema=' || NVL(p_schema, '(null)')
      || ' sql_len=' || TO_CHAR(NVL(DBMS_LOB.GETLENGTH(v_sql), 0)));
    DBMS_OUTPUT.PUT_LINE('-- Run as a top-level script (not inside PL/SQL) to see predicates.');
    IF p_schema IS NOT NULL THEN
      DBMS_OUTPUT.PUT_LINE('ALTER SESSION SET CURRENT_SCHEMA = ' || p_schema || ';');
    END IF;
    DBMS_OUTPUT.PUT_LINE('EXPLAIN');
    put_clob(v_sql);
    DBMS_OUTPUT.PUT_LINE(';');
    DBMS_OUTPUT.PUT_LINE('-- ===== EXPLAIN paste block END =====');
  END;

BEGIN
  SELECT COUNT(*)
    INTO ln_sql_cnt
    FROM v$sql
   WHERE sql_id = c_sqlid
     AND (c_child_in IS NULL OR TO_CHAR(child_number) = c_child_in);

  IF ln_sql_cnt = 0 THEN
    DBMS_OUTPUT.PUT_LINE('No SQL found in V$SQL for sql_id=' || c_sqlid
      || CASE WHEN c_child_in IS NOT NULL THEN ' child=' || c_child_in ELSE '' END);
    RETURN;
  END IF;

  FOR c IN (
    SELECT child_number,
           parsing_schema_name,
           sql_fulltext
      FROM v$sql
     WHERE sql_id = c_sqlid
       AND (c_child_in IS NULL OR TO_CHAR(child_number) = c_child_in)
     ORDER BY child_number
  ) LOOP
    ln_child_cnt := ln_child_cnt + 1;
    lvc_name := c.parsing_schema_name;
    ln_err := 0;

    IF DBMS_LOB.ISTEMPORARY(lvc_orig_sql_text) = 1 THEN
      DBMS_LOB.FREETEMPORARY(lvc_orig_sql_text);
    END IF;
    IF DBMS_LOB.ISTEMPORARY(lvc_sql_text) = 1 THEN
      DBMS_LOB.FREETEMPORARY(lvc_sql_text);
    END IF;

    DBMS_LOB.CREATETEMPORARY(lvc_orig_sql_text, TRUE);
    DBMS_LOB.CREATETEMPORARY(lvc_sql_text, TRUE);
    IF c.sql_fulltext IS NOT NULL THEN
      DBMS_LOB.APPEND(lvc_orig_sql_text, c.sql_fulltext);
      DBMS_LOB.APPEND(lvc_sql_text, c.sql_fulltext);
    END IF;
    ln_sql_len := NVL(DBMS_LOB.GETLENGTH(lvc_sql_text), 0);

    FOR r1 IN (
      SELECT name,
             position,
             datatype_string,
             value_string
        FROM v$sql_bind_capture
       WHERE sql_id = c_sqlid
         AND child_number = c.child_number
       ORDER BY position
    ) LOOP
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

      IF lvc_bind IS NOT NULL AND NOT uses_question_bind_clob(lvc_orig_sql_text) THEN
        ln_qpos := find_pattern_clob(lvc_sql_text, lvc_bind);
        IF ln_qpos = 0 THEN
          DBMS_OUTPUT.PUT_LINE(
            'ERROR: bind pattern not found. '
            || 'child#=' || TO_CHAR(c.child_number)
            || ' position=' || TO_CHAR(r1.position)
            || ' name=' || NVL(r1.name, '(null)')
            || ' pattern=' || lvc_bind
          );
          ln_err := 1;
          EXIT;
        END IF;
        clob_splice_replace(lvc_sql_text, ln_qpos, LENGTH(lvc_bind), lvc_repl);
      ELSE
        ln_qpos := find_question_clob(lvc_sql_text);
        IF ln_qpos = 0 THEN
          DBMS_OUTPUT.PUT_LINE(
            'ERROR: no remaining ''?'' placeholders while replacing binds. '
            || 'child#=' || TO_CHAR(c.child_number)
            || ' position=' || TO_CHAR(r1.position)
            || ' name=' || NVL(r1.name, '(null)')
          );
          ln_err := 1;
          EXIT;
        END IF;
        clob_splice_replace(lvc_sql_text, ln_qpos, 1, lvc_repl);
      END IF;
    END LOOP;

    IF ln_err = 0 THEN
      DBMS_OUTPUT.PUT_LINE('Schema: ' || NVL(lvc_name, '(null)')
        || '  child#=' || TO_CHAR(c.child_number)
        || '  sql_len=' || TO_CHAR(ln_sql_len)
        || '  literal_len=' || TO_CHAR(NVL(DBMS_LOB.GETLENGTH(lvc_sql_text), 0)));
      put_clob(lvc_sql_text);
      DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------');
      emit_explain_block(lvc_name, c.child_number, lvc_sql_text);
      DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------');
    END IF;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('-- children processed: ' || TO_CHAR(ln_child_cnt));
END;
/

PROMPT

PROMPT
PROMPT ****************************************************************************************
PROMPT BIND CAPTURE from v$sql_bind_capture  (sql_id = &&sqlid)
PROMPT ****************************************************************************************

SELECT TO_CHAR(child_number) AS child#,
       TO_CHAR(position) AS pos,
       name,
       datatype_string AS dtype,
       SUBSTR(value_string, 1, 80) AS value
  FROM v$sql_bind_capture
 WHERE sql_id = '&&sqlid'
   AND (TRIM('&&child') IS NULL
        OR TO_CHAR(child_number) = TRIM('&&child'))
 ORDER BY child_number, position
/

PROMPT
PROMPT ****************************************************************************************
PROMPT V$SQLAREA stats  (sql_id = &&sqlid)  -- compact subset from sql.sql
PROMPT ****************************************************************************************

SELECT TO_CHAR(plan_hash_value) AS phv,
       TO_CHAR(executions) AS execs,
       CASE
         WHEN elapsed_time / DECODE(executions, 0, 1, executions) / 1000 < 1000
           THEN TO_CHAR(ROUND(elapsed_time / DECODE(executions, 0, 1, executions) / 1000, 2)) || 'ms'
         WHEN elapsed_time / DECODE(executions, 0, 1, executions) / 1000 / 1000 < 60
           THEN TO_CHAR(ROUND(elapsed_time / DECODE(executions, 0, 1, executions) / 1000 / 1000, 2)) || 's'
         WHEN elapsed_time / DECODE(executions, 0, 1, executions) / 1000 / 1000 / 60 < 60
           THEN TO_CHAR(ROUND(elapsed_time / DECODE(executions, 0, 1, executions) / 1000 / 1000 / 60, 2)) || 'm'
         ELSE TO_CHAR(ROUND(elapsed_time / DECODE(executions, 0, 1, executions) / 1000 / 1000 / 60 / 60, 2)) || 'h'
       END AS ela_p_e,
       CASE
         WHEN cpu_time / DECODE(executions, 0, 1, executions) / 1000 < 1000
           THEN TO_CHAR(ROUND(cpu_time / DECODE(executions, 0, 1, executions) / 1000, 2)) || 'ms'
         WHEN cpu_time / DECODE(executions, 0, 1, executions) / 1000 / 1000 < 60
           THEN TO_CHAR(ROUND(cpu_time / DECODE(executions, 0, 1, executions) / 1000 / 1000, 2)) || 's'
         ELSE TO_CHAR(ROUND(cpu_time / DECODE(executions, 0, 1, executions) / 1000 / 1000 / 60, 2)) || 'm'
       END AS cpu_p_e,
       TO_CHAR(ROUND(buffer_gets / DECODE(executions, 0, 1, executions), 2)) AS get_p_e,
       TO_CHAR(ROUND(disk_reads / DECODE(executions, 0, 1, executions), 2)) AS disk_p_e,
       TO_CHAR(ROUND(rows_processed / DECODE(executions, 0, 1, executions), 2)) AS rows_p_e,
       parsing_schema_name AS schema_name
  FROM v$sqlarea
 WHERE sql_id = '&&sqlid'
/

PROMPT
PROMPT Tip: for execution plan tree (same layout as sql.sql), run plan_pred_by_sqlid.sql
PROMPT
