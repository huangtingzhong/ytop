-- File Name: sqlmap_gen_ddl.sql
-- Purpose: Generate CREATE SQLMAP DDL from an existing sqlmap name (read SYS.SQL_MAP$)
-- Created: 20260731  by  huangtingzhong
--
-- Usage: ytop/yasql -f sqlmap_gen_ddl.sql   (prompts for sqlmap name)
-- Reads USER_NAME / SQL_TEXT / SQLMAP_TEXT from SYS.SQL_MAP$, escapes single quotes,
-- and prints the CREATE SQLMAP DDL. DDL <= 32767 bytes is printed on a single line
-- (directly re-executable); longer DDL is folded per 32767 bytes (view only -- join
-- lines back into one before re-execution, since yasql string literals cannot span lines).

SET SERVEROUTPUT ON
SET VERIFY OFF
SET FEEDBACK OFF

-- YashanDB: do not use SET LINESIZE/PAGESIZE (YASQL-00008).
-- Long DDL is printed via DBMS_OUTPUT in chunks (see body below).

UNDEFINE mapname

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | Generate CREATE SQLMAP DDL from existing sqlmap name                   |
PROMPT +------------------------------------------------------------------------+
PROMPT

ACCEPT mapname PROMPT 'Enter mapname (sqlmap name): '

DECLARE
  v_name   VARCHAR2(64) := TRIM('&&mapname');
  v_user   VARCHAR2(64);
  v_src    CLOB;
  v_tgt    CLOB;
  v_ddl    CLOB;
  v_cnt    NUMBER;
  v_q      VARCHAR2(1) := CHR(39);
  v_seg    VARCHAR2(4000);
  v_len    NUMBER;
  v_off    NUMBER;
  v_amt    NUMBER;

  -- Read CLOB in chunks, escape single quotes, append to target CLOB
  PROCEDURE append_escaped(p_ddl IN OUT NOCOPY CLOB, p_clob IN CLOB) IS
    c_chunk CONSTANT PLS_INTEGER := 4000;
    v_l PLS_INTEGER;
    v_o PLS_INTEGER := 1;
    v_a PLS_INTEGER;
    v_c VARCHAR2(4000);
  BEGIN
    IF p_clob IS NULL THEN RETURN; END IF;
    v_l := DBMS_LOB.GETLENGTH(p_clob);
    WHILE v_o <= v_l LOOP
      v_a := LEAST(c_chunk, v_l - v_o + 1);
      v_c := DBMS_LOB.SUBSTR(p_clob, v_a, v_o);
      v_c := REPLACE(v_c, v_q, v_q || v_q);
      DBMS_LOB.WRITEAPPEND(p_ddl, LENGTH(v_c), v_c);
      v_o := v_o + v_a;
    END LOOP;
  END append_escaped;

BEGIN
  DBMS_OUTPUT.ENABLE(10000000);

  SELECT COUNT(*) INTO v_cnt FROM SYS.SQL_MAP$ WHERE name = v_name;
  IF v_cnt = 0 THEN
    DBMS_OUTPUT.PUT_LINE('-- sqlmap not found: ' || v_name);
    DBMS_OUTPUT.PUT_LINE('-- use sqlmap.sql to list existing sqlmaps');
    RETURN;
  END IF;

  SELECT user_name, sql_text, sqlmap_text
    INTO v_user, v_src, v_tgt
    FROM SYS.SQL_MAP$
   WHERE name = v_name;

  -- Build DDL into CLOB
  DBMS_LOB.CREATETEMPORARY(v_ddl, TRUE);
  v_seg := 'CREATE SQLMAP ' || v_name || ' (' || v_user || ', ' || v_q;
  DBMS_LOB.WRITEAPPEND(v_ddl, LENGTH(v_seg), v_seg);
  append_escaped(v_ddl, v_src);
  v_seg := v_q || ', ' || v_q;
  DBMS_LOB.WRITEAPPEND(v_ddl, LENGTH(v_seg), v_seg);
  append_escaped(v_ddl, v_tgt);
  v_seg := v_q || ');';
  DBMS_LOB.WRITEAPPEND(v_ddl, LENGTH(v_seg), v_seg);

  v_len := DBMS_LOB.GETLENGTH(v_ddl);
  DBMS_OUTPUT.PUT_LINE('-- DDL for sqlmap: ' || v_name ||
                       '  (user=' || v_user || ', total=' || v_len || ' bytes)');

  IF v_len <= 32767 THEN
    DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_ddl, v_len, 1));
  ELSE
    v_off := 1;
    WHILE v_off <= v_len LOOP
      v_amt := LEAST(32767, v_len - v_off + 1);
      DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(v_ddl, v_amt, v_off));
      v_off := v_off + v_amt;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('-- Note: DDL exceeds 32767 bytes and is folded; join lines before re-execution');
  END IF;
END;
/
