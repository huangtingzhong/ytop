-- File Name: outline_enable.sql
-- Purpose: Enable a YashanDB OUTLINE (query info BEFORE and AFTER)
-- Created: 20260801  by  huangtingzhong
--
-- Usage: ytop/yasql -f outline_enable.sql   (prompts outline name)
-- Note: to actually apply outlines to SQL execution, also run:
--       ALTER SESSION SET use_stored_outlines = TRUE;   (or TRUE at system level)

SET SERVEROUTPUT ON

ACCEPT outlinename PROMPT 'Enter outline name to enable: '

DECLARE
  v_name VARCHAR2(128) := TRIM('&&outlinename');

  PROCEDURE bar(p_title IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 78, '-'));
    IF p_title IS NOT NULL THEN DBMS_OUTPUT.PUT_LINE(p_title); END IF;
  END;

  PROCEDURE show_info(p_name IN VARCHAR2) IS
    v_owner VARCHAR2(64); v_cat VARCHAR2(64); v_en VARCHAR2(16); v_sql CLOB; v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM dba_outlines WHERE UPPER(name) = UPPER(p_name);
    IF v_n = 0 THEN
      DBMS_OUTPUT.PUT_LINE('  (outline not found: ' || p_name || ')');
      RETURN;
    END IF;
    SELECT owner, category, enabled, sql_text INTO v_owner, v_cat, v_en, v_sql
      FROM dba_outlines WHERE UPPER(name) = UPPER(p_name);
    DBMS_OUTPUT.PUT_LINE('  name=' || p_name || ' owner=' || v_owner
                         || ' category=' || v_cat || ' enabled=' || v_en);
    DBMS_OUTPUT.PUT_LINE('  SQL : ' || SUBSTR(DBMS_LOB.SUBSTR(v_sql, 110, 1), 1, 110));
    FOR h IN (SELECT hint FROM dba_outline_hints WHERE UPPER(name) = UPPER(p_name)
              ORDER BY node, stage, join_pos) LOOP
      DBMS_OUTPUT.PUT_LINE('  HINT: ' || SUBSTR(DBMS_LOB.SUBSTR(h.hint, 110, 1), 1, 110));
    END LOOP;
  END;

BEGIN
  IF v_name IS NULL OR LENGTH(TRIM(v_name)) = 0 THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: outline name is required (cannot be blank).');
    RETURN;
  END IF;
  DECLARE v_chk NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_chk FROM dba_outlines WHERE UPPER(name) = UPPER(v_name);
    IF v_chk = 0 THEN
      DBMS_OUTPUT.PUT_LINE('ERROR: outline not found: ' || v_name || '. Nothing to do.');
      RETURN;
    END IF;
  END;

  bar('[BEFORE enable] outline = ' || v_name);
  show_info(v_name);

  EXECUTE IMMEDIATE 'ALTER OUTLINE ' || v_name || ' ENABLE';
  DBMS_OUTPUT.PUT_LINE('>> ALTER OUTLINE ' || v_name || ' ENABLE executed.');

  bar('[AFTER enable]');
  show_info(v_name);
  DBMS_OUTPUT.PUT_LINE('Reminder: also set use_stored_outlines=TRUE to apply outlines to SQL execution.');
  bar();
END;
/
