-- File Name: sim_redo.sql
-- Purpose: Continuous HEAP DML load to generate large redo (HTZ_* on USERS)
-- Created: 20260728 by huangtingzhong
--
-- Notes:
--   Table name: HTZ_REDO_<YYYYMMDDHH24MISS>_<SID> in USERS.
--   Two PL/SQL blocks so CREATE info is printed before the infinite loop.
--   Stop with Ctrl+C or ALTER SYSTEM KILL SESSION.
--   Keep USERS free space; avoid running all sim_* scripts in parallel.

SET SERVEROUTPUT ON

DECLARE
  v_ts     VARCHAR2(30);
  v_sid    VARCHAR2(30);
  v_name   VARCHAR2(128);
  v_ddl    VARCHAR2(2000);
  v_owner  VARCHAR2(128);
  v_tsname VARCHAR2(128);
  v_cols   NUMBER;
  v_batch  NUMBER := 1500;
BEGIN
  SELECT TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') INTO v_ts FROM dual;
  SELECT TO_CHAR(SYS_CONTEXT('USERENV', 'SID')) INTO v_sid FROM dual;
  v_name := 'HTZ_REDO_' || v_ts || '_' || v_sid;

  v_ddl := 'CREATE TABLE ' || v_name ||
           ' (id NUMBER, pad VARCHAR2(4000)) TABLESPACE USERS';
  EXECUTE IMMEDIATE v_ddl;

  SELECT owner, tablespace_name INTO v_owner, v_tsname
    FROM dba_tables WHERE owner = USER AND table_name = v_name;
  SELECT COUNT(*) INTO v_cols
    FROM dba_tab_columns WHERE owner = USER AND table_name = v_name;

  DBMS_OUTPUT.PUT_LINE('=== LOAD TABLE CREATED ===');
  DBMS_OUTPUT.PUT_LINE('OWNER=' || v_owner);
  DBMS_OUTPUT.PUT_LINE('TABLE_NAME=' || v_name);
  DBMS_OUTPUT.PUT_LINE('TABLESPACE_NAME=' || v_tsname);
  DBMS_OUTPUT.PUT_LINE('COLUMN_COUNT=' || v_cols);
  DBMS_OUTPUT.PUT_LINE('COLUMNS=ID NUMBER, PAD VARCHAR2(4000)');
  DBMS_OUTPUT.PUT_LINE('DDL=' || v_ddl);
  DBMS_OUTPUT.PUT_LINE('MODE=redo continuous UPDATE+COMMIT');
  DBMS_OUTPUT.PUT_LINE('HINT=watch v$sysstat REDO SIZE / REDO ENTRIES BY SELF');

  EXECUTE IMMEDIATE
    'INSERT INTO ' || v_name ||
    ' SELECT LEVEL, RPAD(''R'', 4000, ''R'') FROM dual CONNECT BY LEVEL <= ' ||
    TO_CHAR(v_batch);
  COMMIT;
END;
/

PROMPT === Confirm HTZ_REDO table ===
SELECT owner, table_name, tablespace_name, num_rows
  FROM dba_tables
 WHERE owner = USER AND table_name LIKE 'HTZ_REDO_%'
 ORDER BY table_name DESC
 FETCH FIRST 1 ROWS ONLY;

SELECT column_id, column_name, data_type, data_length
  FROM dba_tab_columns
 WHERE owner = USER
   AND table_name = (
     SELECT table_name FROM dba_tables
      WHERE owner = USER AND table_name LIKE 'HTZ_REDO_%'
      ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY
   )
 ORDER BY column_id;

DECLARE
  v_name  VARCHAR2(128);
  v_round NUMBER := 0;
BEGIN
  SELECT table_name INTO v_name FROM dba_tables
   WHERE owner = USER AND table_name LIKE 'HTZ_REDO_%'
   ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY;

  DBMS_OUTPUT.PUT_LINE('START LOOP TABLE_NAME=' || v_name);
  LOOP
    v_round := v_round + 1;
    EXECUTE IMMEDIATE
      'UPDATE ' || v_name || ' SET pad = RPAD(:1, 4000, :2)'
      USING 'R' || TO_CHAR(MOD(v_round, 97)), 'R';
    COMMIT;
  END LOOP;
END;
/
