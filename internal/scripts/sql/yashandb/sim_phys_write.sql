-- File Name: sim_phys_write.sql
-- Purpose: Continuous physical write load via dirty HEAP blocks on HTZ_*
-- Created: 20260728 by huangtingzhong
--
-- Notes:
--   Table name: HTZ_PWRITE_<YYYYMMDDHH24MISS>_<SID> in USERS.
--   No ALTER SYSTEM (no CHECKPOINT); relies on normal DBWR write-out.
--   Stop with Ctrl+C or KILL SESSION.

SET SERVEROUTPUT ON

DECLARE
  v_ts     VARCHAR2(30);
  v_sid    VARCHAR2(30);
  v_name   VARCHAR2(128);
  v_ddl    VARCHAR2(2000);
  v_owner  VARCHAR2(128);
  v_tsname VARCHAR2(128);
  v_cols   NUMBER;
  v_rows   NUMBER := 3000;
BEGIN
  SELECT TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') INTO v_ts FROM dual;
  SELECT TO_CHAR(SYS_CONTEXT('USERENV', 'SID')) INTO v_sid FROM dual;
  v_name := 'HTZ_PWRITE_' || v_ts || '_' || v_sid;

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
  DBMS_OUTPUT.PUT_LINE('MODE=phys_write UPDATE+COMMIT (no CHECKPOINT)');
  DBMS_OUTPUT.PUT_LINE('HINT=watch v$sysstat BUFFER BLOCKS WRITES');

  EXECUTE IMMEDIATE
    'INSERT INTO ' || v_name ||
    ' SELECT LEVEL, RPAD(''W'', 4000, ''W'') FROM dual CONNECT BY LEVEL <= ' ||
    TO_CHAR(v_rows);
  COMMIT;
END;
/

PROMPT === Confirm HTZ_PWRITE table ===
SELECT owner, table_name, tablespace_name
  FROM dba_tables
 WHERE owner = USER AND table_name LIKE 'HTZ_PWRITE_%'
 ORDER BY table_name DESC
 FETCH FIRST 1 ROWS ONLY;

SELECT column_id, column_name, data_type, data_length
  FROM dba_tab_columns
 WHERE owner = USER
   AND table_name = (
     SELECT table_name FROM dba_tables
      WHERE owner = USER AND table_name LIKE 'HTZ_PWRITE_%'
      ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY
   )
 ORDER BY column_id;

DECLARE
  v_name  VARCHAR2(128);
  v_round NUMBER := 0;
BEGIN
  SELECT table_name INTO v_name FROM dba_tables
   WHERE owner = USER AND table_name LIKE 'HTZ_PWRITE_%'
   ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY;

  DBMS_OUTPUT.PUT_LINE('START LOOP TABLE_NAME=' || v_name);
  LOOP
    v_round := v_round + 1;
    -- dirty many blocks; DBWR writes them without forced CHECKPOINT
    EXECUTE IMMEDIATE
      'UPDATE ' || v_name || ' SET pad = RPAD(:1, 4000, :2)'
      USING 'W' || TO_CHAR(MOD(v_round, 89)), 'W';
    COMMIT;
  END LOOP;
END;
/
