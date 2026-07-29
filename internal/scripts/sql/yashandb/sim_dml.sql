-- File Name: sim_dml.sql
-- Purpose: Continuous high-volume small DML (insert/update/delete) on HTZ_* HEAP
-- Created: 20260728 by huangtingzhong
--
-- Notes:
--   Table name: HTZ_DML_<YYYYMMDDHH24MISS>_<SID> in USERS.
--   Row count bounded to avoid filling USERS.
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
  v_max    NUMBER := 3000;
BEGIN
  SELECT TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') INTO v_ts FROM dual;
  SELECT TO_CHAR(SYS_CONTEXT('USERENV', 'SID')) INTO v_sid FROM dual;
  v_name := 'HTZ_DML_' || v_ts || '_' || v_sid;

  v_ddl := 'CREATE TABLE ' || v_name ||
           ' (id NUMBER, val NUMBER, pad VARCHAR2(200)) TABLESPACE USERS';
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
  DBMS_OUTPUT.PUT_LINE('COLUMNS=ID NUMBER, VAL NUMBER, PAD VARCHAR2(200)');
  DBMS_OUTPUT.PUT_LINE('DDL=' || v_ddl);
  DBMS_OUTPUT.PUT_LINE('MODE=dml high-frequency INSERT/UPDATE/DELETE');
  DBMS_OUTPUT.PUT_LINE('HINT=watch EXECUTE COUNT / REDO ENTRIES BY SELF');

  EXECUTE IMMEDIATE
    'INSERT INTO ' || v_name ||
    ' SELECT LEVEL, LEVEL, RPAD(''D'', 200, ''D'') FROM dual CONNECT BY LEVEL <= ' ||
    TO_CHAR(v_max);
  COMMIT;
END;
/

PROMPT === Confirm HTZ_DML table ===
SELECT owner, table_name, tablespace_name
  FROM dba_tables
 WHERE owner = USER AND table_name LIKE 'HTZ_DML_%'
 ORDER BY table_name DESC
 FETCH FIRST 1 ROWS ONLY;

SELECT column_id, column_name, data_type, data_length
  FROM dba_tab_columns
 WHERE owner = USER
   AND table_name = (
     SELECT table_name FROM dba_tables
      WHERE owner = USER AND table_name LIKE 'HTZ_DML_%'
      ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY
   )
 ORDER BY column_id;

DECLARE
  v_name  VARCHAR2(128);
  v_max   NUMBER := 3000;
  v_round NUMBER := 0;
  v_cnt   NUMBER;
BEGIN
  SELECT table_name INTO v_name FROM dba_tables
   WHERE owner = USER AND table_name LIKE 'HTZ_DML_%'
   ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY;

  DBMS_OUTPUT.PUT_LINE('START LOOP TABLE_NAME=' || v_name);
  LOOP
    v_round := v_round + 1;
    EXECUTE IMMEDIATE
      'INSERT INTO ' || v_name ||
      ' SELECT :1 + LEVEL, LEVEL, RPAD(''I'', 200, ''I'')' ||
      ' FROM dual CONNECT BY LEVEL <= 100'
      USING (v_max + v_round * 100);
    EXECUTE IMMEDIATE
      'UPDATE ' || v_name || ' SET val = val + 1 WHERE MOD(id, 17) = 0';
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_name INTO v_cnt;
    IF v_cnt > v_max THEN
      EXECUTE IMMEDIATE
        'DELETE FROM ' || v_name ||
        ' WHERE id IN (SELECT id FROM ' || v_name ||
        ' ORDER BY id FETCH FIRST :1 ROWS ONLY)'
        USING (v_cnt - v_max);
    END IF;
    COMMIT;
  END LOOP;
END;
/
