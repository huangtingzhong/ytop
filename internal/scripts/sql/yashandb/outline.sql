-- File Name: outline.sql
-- Purpose: View YashanDB OUTLINE (list all + look up by name / sql_id / sql_text fragment)
-- Created: 20260801  by  huangtingzhong
--
-- Usage: ytop/yasql -f outline.sql   (prompts outline name)
--   blank : list all OUTLINEs
--   input : match by outline NAME (exact, case-insensitive), SQL_ID, or SQL_TEXT
--           fragment (substring, case-insensitive). Multiple matches are all shown.

SET SERVEROUTPUT ON

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | View YashanDB OUTLINE                                                  |
PROMPT | Input accepts one of (case-insensitive):                              |
PROMPT |   - outline NAME      (exact match)                                    |
PROMPT |   - SQL_ID            (match DBA_OUTLINES.SQL_ID)                      |
PROMPT |   - SQL_TEXT fragment (substring match)                                |
PROMPT |   - blank             (match ALL outlines)                            |
PROMPT +------------------------------------------------------------------------+
PROMPT

ACCEPT outlinename PROMPT 'Enter outline name / sql_id / sql_text fragment (blank = all): '

DECLARE
  v_input   VARCHAR2(4000) := TRIM('&&outlinename');
  v_total   NUMBER;
  v_matched NUMBER;
  v_sid     VARCHAR2(32);

  FUNCTION has_value(p IN VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    RETURN p IS NOT NULL AND LENGTH(TRIM(p)) > 0;
  END;

  PROCEDURE bar(p_title IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 78, '-'));
    IF p_title IS NOT NULL THEN DBMS_OUTPUT.PUT_LINE(p_title); END IF;
  END;

  PROCEDURE show_detail(p_name IN VARCHAR2) IS
    v_owner VARCHAR2(128); v_cat VARCHAR2(128); v_en VARCHAR2(32);
    v_used VARCHAR2(64); v_ts VARCHAR2(32);
    v_sqlid VARCHAR2(32); v_sql CLOB;
  BEGIN
    SELECT owner, category, enabled, used,
           TO_CHAR(timestamp,'YYYY-MM-DD HH24:MI:SS'), sql_id, sql_text
      INTO v_owner, v_cat, v_en, v_used, v_ts, v_sqlid, v_sql
      FROM dba_outlines WHERE name = p_name;
    IF v_sqlid IS NULL THEN
      BEGIN
        SELECT sql_id INTO v_sqlid FROM v$sql
         WHERE sql_fulltext LIKE SUBSTR(DBMS_LOB.SUBSTR(v_sql, 80, 1), 1, 80) || '%' AND rownum=1;
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
    DBMS_OUTPUT.PUT_LINE('  ' || RPAD(p_name, 32) || RPAD(v_owner, 9) || RPAD(v_cat, 13)
                         || RPAD(v_en, 11) || RPAD(NVL(v_used,'?'),9) || RPAD(NVL(v_sqlid,'(n/a)'),14)
                         || v_ts);
    DBMS_OUTPUT.PUT_LINE('    SQL_TEXT : ' || SUBSTR(DBMS_LOB.SUBSTR(v_sql, 180, 1), 1, 180));
    FOR h IN (SELECT node, stage, join_pos, hint FROM dba_outline_hints WHERE name = p_name
              ORDER BY node, stage, join_pos) LOOP
      DBMS_OUTPUT.PUT_LINE('    HINT[node=' || h.node || ',stage=' || h.stage
                           || ',join=' || h.join_pos || ']: '
                           || SUBSTR(DBMS_LOB.SUBSTR(h.hint, 150, 1), 1, 150));
    END LOOP;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('  outline not found: ' || p_name);
  END;

  -- match by NAME (exact, case-insensitive) / SQL_ID / SQL_TEXT fragment (substring)
  FUNCTION match_count(p_input IN VARCHAR2) RETURN NUMBER IS
    v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM dba_outlines
     WHERE UPPER(name) = UPPER(p_input)
        OR sql_id = p_input
        OR INSTR(UPPER(DBMS_LOB.SUBSTR(sql_text, 32767, 1)), UPPER(p_input)) > 0;
    RETURN v_n;
  END;

  PROCEDURE show_matches(p_input IN VARCHAR2) IS
  BEGIN
    FOR r IN (SELECT name FROM dba_outlines
               WHERE UPPER(name) = UPPER(p_input)
                  OR sql_id = p_input
                  OR INSTR(UPPER(DBMS_LOB.SUBSTR(sql_text, 32767, 1)), UPPER(p_input)) > 0
               ORDER BY name) LOOP
      show_detail(r.name);
    END LOOP;
  END;

BEGIN
  IF has_value(v_input) THEN
    bar('[lookup] input = ' || v_input || '  (match by name / sql_id / sql_text fragment)');
    v_matched := match_count(v_input);
    IF v_matched = 0 THEN
      DBMS_OUTPUT.PUT_LINE('  no outline matched.');
    ELSE
      DBMS_OUTPUT.PUT_LINE('  matched ' || v_matched || ' outline(s):');
      show_matches(v_input);
    END IF;
  ELSE
    -- blank input matches ALL outlines (full detail)
    bar('[lookup] blank input - matching ALL outlines');
    SELECT COUNT(*) INTO v_matched FROM dba_outlines;
    IF v_matched = 0 THEN
      DBMS_OUTPUT.PUT_LINE('  (empty) no outline.');
    ELSE
      DBMS_OUTPUT.PUT_LINE('  showing all ' || v_matched || ' outline(s):');
      FOR r IN (SELECT name FROM dba_outlines ORDER BY name) LOOP
        show_detail(r.name);
      END LOOP;
    END IF;
  END IF;

  bar();
END;
/
