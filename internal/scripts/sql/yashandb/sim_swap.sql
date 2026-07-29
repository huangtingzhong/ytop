-- File Name: sim_swap.sql
-- Purpose: Continuous VM/SWAP load via high-fanout HASH JOIN on HTZ_* HEAP
-- Created: 20260728 by huangtingzhong
--
-- Notes:
--   Table name: HTZ_SWAP_<YYYYMMDDHH24MISS>_<SID> in USERS.
--   Seed size capped for small USERS; join fanout drives VM SWAP OUT/IN.
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
  v_rows   NUMBER := 25000;
BEGIN
  SELECT TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS') INTO v_ts FROM dual;
  SELECT TO_CHAR(SYS_CONTEXT('USERENV', 'SID')) INTO v_sid FROM dual;
  v_name := 'HTZ_SWAP_' || v_ts || '_' || v_sid;

  v_ddl := 'CREATE TABLE ' || v_name ||
           ' (id NUMBER, c1 VARCHAR2(200), c2 VARCHAR2(200)) TABLESPACE USERS';
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
  DBMS_OUTPUT.PUT_LINE('COLUMNS=ID NUMBER, C1 VARCHAR2(200), C2 VARCHAR2(200)');
  DBMS_OUTPUT.PUT_LINE('DDL=' || v_ddl);
  DBMS_OUTPUT.PUT_LINE('MODE=swap HASH JOIN fanout on C2');
  DBMS_OUTPUT.PUT_LINE('HINT=watch v$sysstat VM SWAP OUT/IN and v$vmstat');

  EXECUTE IMMEDIATE
    'INSERT INTO ' || v_name ||
    ' SELECT LEVEL,' ||
    ' RPAD(TO_CHAR(MOD(LEVEL, 12347)), 200, ''A''),' ||
    ' RPAD(TO_CHAR(MOD(LEVEL, 2347)), 200, ''B'')' ||
    ' FROM dual CONNECT BY LEVEL <= ' || TO_CHAR(v_rows);
  COMMIT;
END;
/

PROMPT === Confirm HTZ_SWAP table ===
SELECT owner, table_name, tablespace_name
  FROM dba_tables
 WHERE owner = USER AND table_name LIKE 'HTZ_SWAP_%'
 ORDER BY table_name DESC
 FETCH FIRST 1 ROWS ONLY;

SELECT column_id, column_name, data_type, data_length
  FROM dba_tab_columns
 WHERE owner = USER
   AND table_name = (
     SELECT table_name FROM dba_tables
      WHERE owner = USER AND table_name LIKE 'HTZ_SWAP_%'
      ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY
   )
 ORDER BY column_id;

DECLARE
  v_name  VARCHAR2(128);
  v_round NUMBER := 0;
  v_cnt   NUMBER;
  v_sql   VARCHAR2(4000);
BEGIN
  SELECT table_name INTO v_name FROM dba_tables
   WHERE owner = USER AND table_name LIKE 'HTZ_SWAP_%'
   ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY;

  v_sql :=
    'SELECT /*+ USE_HASH(a b) */ COUNT(*) FROM ' || v_name || ' a, ' ||
    v_name || ' b WHERE a.c2 = b.c2 AND a.id <= 20000 AND b.id <= 20000' ||
    ' AND a.id <> b.id';

  DBMS_OUTPUT.PUT_LINE('START LOOP TABLE_NAME=' || v_name);
  LOOP
    v_round := v_round + 1;
    BEGIN
      EXECUTE IMMEDIATE v_sql INTO v_cnt;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('round=' || v_round || ' err=' || SQLERRM);
    END;
  END LOOP;
END;
/
