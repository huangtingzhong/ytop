-- File Name: sim_phys_read.sql
-- Purpose: Continuous physical/buffer read load via FULL scan on HTZ_* HEAP
-- Created: 20260728 by huangtingzhong
--
-- Notes:
--   Table name: HTZ_PREAD_<YYYYMMDDHH24MISS>_<SID> in USERS.
--   No ALTER SYSTEM (no FLUSH BUFFER_CACHE); session SQL only.
--   Physical reads depend on buffer aging; script maximizes multi-segment scans.
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
  v_name := 'HTZ_PREAD_' || v_ts || '_' || v_sid;

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
  DBMS_OUTPUT.PUT_LINE('MODE=phys_read FULL scan + catalog scan (no FLUSH)');
  DBMS_OUTPUT.PUT_LINE('HINT=watch v$sysstat BUFFER BLOCKS READS');

  EXECUTE IMMEDIATE
    'INSERT INTO ' || v_name ||
    ' SELECT LEVEL, RPAD(''P'', 4000, ''P'') FROM dual CONNECT BY LEVEL <= ' ||
    TO_CHAR(v_rows);
  COMMIT;
END;
/

PROMPT === Confirm HTZ_PREAD table ===
SELECT owner, table_name, tablespace_name
  FROM dba_tables
 WHERE owner = USER AND table_name LIKE 'HTZ_PREAD_%'
 ORDER BY table_name DESC
 FETCH FIRST 1 ROWS ONLY;

SELECT column_id, column_name, data_type, data_length
  FROM dba_tab_columns
 WHERE owner = USER
   AND table_name = (
     SELECT table_name FROM dba_tables
      WHERE owner = USER AND table_name LIKE 'HTZ_PREAD_%'
      ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY
   )
 ORDER BY column_id;

DECLARE
  v_name  VARCHAR2(128);
  v_round NUMBER := 0;
  v_cnt   NUMBER;
  v_len   NUMBER;
  v_x     NUMBER;
BEGIN
  SELECT table_name INTO v_name FROM dba_tables
   WHERE owner = USER AND table_name LIKE 'HTZ_PREAD_%'
   ORDER BY table_name DESC FETCH FIRST 1 ROWS ONLY;

  DBMS_OUTPUT.PUT_LINE('START LOOP TABLE_NAME=' || v_name);
  LOOP
    v_round := v_round + 1;
    -- HEAP full scan (no ALTER SYSTEM)
    EXECUTE IMMEDIATE
      'SELECT /*+ FULL(t) */ COUNT(*), MAX(LENGTH(pad)) FROM ' ||
      v_name || ' t' INTO v_cnt, v_len;
    -- self join expands working set
    EXECUTE IMMEDIATE
      'SELECT /*+ FULL(a) FULL(b) */ COUNT(*) FROM ' || v_name ||
      ' a, ' || v_name || ' b WHERE a.id = b.id AND MOD(a.id, 3) = :1'
      INTO v_x USING MOD(v_round, 3);
    -- mix catalog scans to touch more segments
    SELECT COUNT(*) INTO v_x FROM dba_objects;
    SELECT COUNT(*) INTO v_x FROM dba_tab_columns;
    SELECT COUNT(*) INTO v_x FROM dba_segments;
  END LOOP;
END;
/
