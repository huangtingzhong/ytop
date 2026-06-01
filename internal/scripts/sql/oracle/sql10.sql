-- File Name: sql10.sql
-- Purpose: Oracle SQL tuning report with plan and objects
-- Created: 20150905  by  huangtingzhong

alter session set nls_date_format='yyyymmdd';
set serveroutput on size 1000000

SET VERIFY OFF
set linesize 200
set echo off
set pages 0


var sql_id_bind varchar2(30)


begin
  :sql_id_bind := '&&sqlid';
end;
/

define _VERSION_11  = "--"
define _VERSION_12  = "--"
define _VERSION_10  = "--"
define _CDB_MODE    = "--"
define _TABLE_COL_VALUE    = "--"
col pdbname    noprint new_value _PDBNAME
col version12  noprint new_value _VERSION_12
col version11  noprint new_value _VERSION_11
col version10  noprint new_value _VERSION_10


select /*+ no_parallel */case
         when substr(banner,
                     instr(banner, 'Release ') + 8,
                     instr(substr(banner, instr(banner, 'Release ') + 8), ' ')) >=
              '10.2' and
              substr(banner,
                     instr(banner, 'Release ') + 8,
                     instr(substr(banner, instr(banner, 'Release ') + 8), ' ')) <
              '11.2' then
          '  '
         else
          '--'
       end  version10,
       case
         when substr(banner,
                     instr(banner, 'Release ') + 8,
                     instr(substr(banner, instr(banner, 'Release ') + 8), ' ')) >=
              '11.2' then
          '  '
         else
          '--'
       end  version11,
              case
         when substr(banner,
                     instr(banner, 'Release ') + 8,
                     instr(substr(banner, instr(banner, 'Release ') + 8), ' ')) >=
              '12.1' then
          '  '
         else
          '--'
       end  version12
  from v$version
 where banner like 'Oracle Database%';


-------------------------------------------------------------------------------------------------
col CPU_TIME                heading "CPU|TIME"           for 999999,999,999
col ELAPSED_TIME            heading "ELAPSED|TIME"       for 999999,999,999
col PARSE_CALLS             heading "PARSE|CALLS"        for 99999,999,999
col DISK_READS              heading "DISK|READS"         for 999999,999,999
col BUFFER_GETS             heading "BUFFER|GETS"        for 999999,999,999
col SORTS                   heading "SORTS"              for 999999,999,999
col ROWS_PROCESSED          heading "ROWS|PROCESSED"     for a8
COL INSTANCE_NUMBER         heading "I"                  for a1
COL PARSING_SCHEMA_NAME     heading "NAME"               for a15
col FETCHES                 heading "FETCHES"            for a8
col ROW_PROCESSES           heading "ROW_PROC"           for a5
col EXECUTIONS              heading "EXEC"               for a10
col CPU_PRE_EXEC            heading "CPU|PRE EXEC"       for a8
col ELA_PRE_EXEC            heading "ELA|PRE EXEC"       for a8
col DISK_PRE_EXEC           heading "DISK|PRE EXEC"      for a8
col GET_PRE_EXEC            heading "GET|PRE EXEC"       for a8
col ROWS_PRE_EXEC           heading "ROWS|PRE EXEC"      for a8
col ROWS_PRE_FETCHES        heading "ROWS|PRE FETCH"     for a8
col c                       heading "CHI|NUM"            for 999
col USERNAME                heading "USER|NAME"          for a10
col PLAN_HASH_VALUE         heading "PLAN|HASH VALUE"    for 999999999999
col APP_WAIT_PRE            heading "APPLI|PER EXEC" for a8
col CON_WAIT_PER            heading "CONCUR|PER EXEC" for a8
col WRITE_PRE_EXEC          heading "WRITE|PER EXEC"     for  a8
col CON_PRE_EXEC            heading "CON|PRE EXEC"       for  a8
col APP_PRE_EXEC            heading "APP|PRE EXEC"       for  a8
col CLU_WAIT_PER            heading "CLUSTER|PER EXEC" FOR a8
col USER_IO_WAIT_PER        heading "USER_IO|PER EXEC" FOR a8
COL PLSQL_WAIT_PER          heading "PLSQL|PER EXEC"     FOR a8
COL JAVA_WAIT_PER           heading "JAVA|PER EXEC"      FOR a8
COL F_L_TIME                heading 'FIRST_LOAD_TIME|LAST_LOAD_TIME'   FOR a22
COL SQL_PROFILE             heading 'SQL_PROFILE'        FOR a25
COL END_TIME                heading 'END_TIME'           FOR a6
col IOWAIT_PRE_EXEC         heading "IOWAIT|PER EXEC"    for a8
col PARSE_PRE_EXEC          heading "PARSE|PER EXEC"     for a8
col SORTS_PRE_EXEC          heading "SORTS|PER EXEC"     for a8
col MEM_PRE_EXEC            heading "MEM|PER EXEC"       for a8
col APP_WAIT_PRE_EXEC       heading "APP_WAIT|PER EXEC"  for a8
col CONC_WAIT_PRE_EXEC      heading "CONC_WAIT|PER EXEC" for a8
col CLUSTER_WAIT_PRE_EXEC   heading "CLUSTER_WAIT|PER EXEC" for a8
col PLSQL_WAIT_PRE_EXEC     heading "PLSQL_WAIT|PER EXEC" for a8
col JAVA_WAIT_PRE_EXEC      heading "JAVA_WAIT|PER EXEC"  for a8
-------------------------------------------------------------------------------------------------
col TABLE_NAME              heading "TABLE|NAME"         for a35
col SEGMENT_NAME            heading "SEGMENT|NAME"       for a35
col OWNER                   heading "OWNER"              for a15
col TABLESPACE_NAME         heading "TABLESPACE|NAME"    for a10
col LOGGING                 heading "LOG"                for a3
col BUFFER_POOL             heading "BUFFER|POOL"        for a7
col DEGREE                  heading "DEGREE"             for a6
col PARTITIONED             heading "PART"               for a4
col NUM_ROWS                heading "NUM|ROWS"           for 999,999,999
col BLOCKS                  heading "BLOCKS"             for 999,999,999
col EMPTY_BLOCKS            heading "EMPTY|BLOCKS"       for 999,999,999
col AVG_SPACE               heading "AVG|SPACE"          for 999,999,999
col AVG_ROW_LEN             heading "AVG|ROW_LEN"        for 999,999,999
col AVG_ROW_LEN             heading "AVG|ROW_LEN"        for 999,999,999
col LAST_ANALYZED           heading "LAST|ANALYZED"
col STALE_STATS             heading "OLD|STATS"          FOR A5
col sample_size             heading 'SAMPLE_SIZE'        FOR 999,999,999
col block_size              heading 'BLOCK_SIZE(M)'      FOR 999,999
col avg_size                heading 'AVG_SIZE(M)'        FOR 999,999
-------------------------------------------------------------------------------------------------
col TABLE_OWNER             heading "TABLE|OWNER"        for a15
col INDEX_NAME              heading "Index|Name"         for a30
col UNIQUENESS              heading "UNIQUE"             for a9
col UCPTDVS                 heading "UCPTDVS"            for a7
col COLUMN_NAME             heading "COLUMN|NAME"        for a25
col COLUMN_POSITION         heading "COL|POS"            for 999
col DESCEND                 heading "DESC"               for a4
-------------------------------------------------------------------------------------------------
col CHILD_NUMBER            heading "CHILD|NUMBER"       for 999
col name                    heading "BIND|NAME"          for a10
col value_string            heading "VALUE|STRING"       for a60
col DATATYPE_STRING         heading "DATATYPE|STRING"    for a20
-------------------------------------------------------------------------------------------------
col program                 heading "PROGRAM"            for a30
col event                   heading "EVENT"              for a40
col total                   heading "TOTAL"              for 999,999
col wait_class              heading "WAIT|CLASS"         for a15
-------------------------------------------------------------------------------------------------
col DATA_TYPE               heading "DATA|TYPE"          for a15
col NULLABLE                heading "NL"                 for a2
col HISTOGRAM               heading "HIST"               for a5
col DENSITY                 heading "DENSITY"            for 999,999,999
col NUM_NULLS               heading "NUM|NULLS"          for 999,999,999
col NUM_BUCKETS             heading "NUM|BUCKETS"        for 999,999,999
col AVG_COL_LEN             heading "AVG|COL LEN"        for 999,999,999
-------------------------------------------------------------------------------------------------
col L_T                     heading "LOG|TEMP"           for a7
col STATUS                  heading "STATUS"             for a10
col INDEX_TYPE              heading "INDEX|TYPE"         for a8
col UNIQUENESS              heading "Unique"             for a9
col BLEV                    heading "B"                  for a1
col LEAF_BLOCKS             heading "Leaf|Blks"          for 999,999
col DISTINCT_KEYS           heading "Distinct|Keys"      for 999,999,999
col AVG_LEAF_BLOCKS_PER_KEY heading "Average|Leaf Blocks|Per Key" for 99,999
col AVG_DATA_BLOCKS_PER_KEY heading "Average|Data Blocks|Per Key" for 99,999
col CLUSTERING_FACTOR       heading "Cluster|Factor"     for 999,999,999
col COLUMN_POSITION         heading "Col|Pos"            for 999
col degree                  heading "D"                  for a1
col index_local             heading "LOCAL|PRE"          for a6
-------------------------------------------------------------------------------------------------
col file_name new_value file_name noprint;
select '18081072613_'|| HOST_NAME||'_'||INSTANCE_NAME||'_'||
         :sql_id_bind||'~'||'_'||to_char(sysdate,'yyyymmddhh24')||'_htz.txt' file_name
         from v$instance
;
spool &file_name;

-------------------------------------------------------------------------------------------------
set pages 10000 heading on
prompt
prompt ****************************************************************************************
prompt LITERAL SQL
prompt ****************************************************************************************

-- DECLARE
--   LVC_SQL_TEXT      VARCHAR2(32000);
--   LVC_ORIG_SQL_TEXT VARCHAR2(32000);
--   LN_CHILD          NUMBER := 10000;
--   LVC_BIND          VARCHAR2(200);
--   LVC_NAME          VARCHAR2(30);
--   CURSOR C1 IS
--     SELECT CHILD_NUMBER, NAME, POSITION, DATATYPE_STRING, VALUE_STRING
--       -- add
--       ,sql_id
--       -- add end
--       FROM V$SQL_BIND_CAPTURE
--      WHERE SQL_ID = :sql_id_bind
--      ORDER BY CHILD_NUMBER, POSITION;
-- BEGIN
--   SELECT SQL_FULLTEXT
--     INTO LVC_ORIG_SQL_TEXT
--     FROM V$SQL
--    WHERE SQL_ID = :sql_id_bind
--      AND ROWNUM = 1;
--   FOR R1 IN C1 LOOP
--     IF (R1.CHILD_NUMBER <> LN_CHILD) THEN
--       IF LN_CHILD <> 10000 THEN
--         DBMS_OUTPUT.PUT_LINE(LVC_NAME);
--         DBMS_OUTPUT.PUT_LINE(LVC_SQL_TEXT);
--         DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------');
--       END IF;
--       LN_CHILD     := R1.CHILD_NUMBER;
--       LVC_SQL_TEXT := LVC_ORIG_SQL_TEXT;
--     END IF;

--     -- add
--     select parsing_schema_name into LVC_NAME from v$sql where sql_id=r1.sql_id and child_number=r1.CHILD_NUMBER;
--     -- add end

--     IF R1.NAME LIKE ':SYS_B_%' THEN
--       LVC_BIND := ':"'||substr(R1.NAME,2)||'"';
--     ELSE
--       LVC_BIND := R1.NAME;
--     END IF;


--     IF r1.VALUE_STRING IS NOT NULL THEN
--       IF R1.DATATYPE_STRING = 'NUMBER' THEN
--         LVC_SQL_TEXT := REGEXP_REPLACE(LVC_SQL_TEXT, LVC_BIND, R1.VALUE_STRING,1,1,'i');
--       ELSIF R1.DATATYPE_STRING LIKE 'VARCHAR%' THEN
--         LVC_SQL_TEXT := REGEXP_REPLACE(LVC_SQL_TEXT, LVC_BIND, ''''||R1.VALUE_STRING||'''',1,1,'i');
--       ELSE
--         LVC_SQL_TEXT := REGEXP_REPLACE(LVC_SQL_TEXT, LVC_BIND, ''''||R1.VALUE_STRING||'''',1,1,'i');
--       END IF;
--     ELSE
--        LVC_SQL_TEXT := REGEXP_REPLACE(LVC_SQL_TEXT, LVC_BIND, 'NULL',1,1,'i');
--     END IF;
--   END LOOP;
--   DBMS_OUTPUT.PUT_LINE(LVC_NAME);
--   DBMS_OUTPUT.PUT_LINE(LVC_SQL_TEXT);
-- END;
-- /



DECLARE
  LVC_SQL_TEXT      VARCHAR2(32000);
  LVC_ORIG_SQL_TEXT VARCHAR2(32000);
  LN_CHILD          NUMBER := 10000;
  LVC_BIND          VARCHAR2(200);
  LVC_NAME          VARCHAR2(30);
  LN_BIND_COUNT     NUMBER := 0;

  FUNCTION replace_first_outside_quotes(
    p_text        IN VARCHAR2,
    p_pattern     IN VARCHAR2,
    p_replacement IN VARCHAR2
  ) RETURN VARCHAR2 IS
    v_pos        PLS_INTEGER := 1;
    v_len        PLS_INTEGER := NVL(LENGTH(p_text), 0);
    v_plen       PLS_INTEGER := NVL(LENGTH(p_pattern), 0);
    v_in_quote   BOOLEAN := FALSE;
    v_result     VARCHAR2(32767) := '';
    v_ch         CHAR(1);
    v_replaced   BOOLEAN := FALSE;
    v_next       CHAR(1);
  BEGIN
    IF v_len = 0 OR v_plen = 0 THEN
      RETURN p_text;
    END IF;

    WHILE v_pos <= v_len LOOP
      v_ch := SUBSTR(p_text, v_pos, 1);

      IF v_ch = '''' THEN
        IF v_in_quote THEN
          -- handle doubled quote inside a literal
          IF v_pos < v_len AND SUBSTR(p_text, v_pos + 1, 1) = '''' THEN
            v_result := v_result || '''''';
            v_pos := v_pos + 2;
            CONTINUE;
          ELSE
            v_in_quote := FALSE;
            v_result := v_result || v_ch;
            v_pos := v_pos + 1;
            CONTINUE;
          END IF;
        ELSE
          v_in_quote := TRUE;
          v_result := v_result || v_ch;
          v_pos := v_pos + 1;
          CONTINUE;
        END IF;
      END IF;

      IF NOT v_in_quote AND NOT v_replaced AND v_pos + v_plen - 1 <= v_len THEN
        IF UPPER(SUBSTR(p_text, v_pos, v_plen)) = UPPER(p_pattern) THEN
          -- avoid partial match like ':1' within ':10'
          v_next := CASE WHEN v_pos + v_plen <= v_len THEN SUBSTR(p_text, v_pos + v_plen, 1) ELSE NULL END;
          IF p_pattern LIKE ':%' THEN
            IF v_next IS NULL OR v_next NOT BETWEEN '0' AND '9' THEN
              v_result := v_result || p_replacement || SUBSTR(p_text, v_pos + v_plen);
              RETURN v_result;
            END IF;
          ELSE
            v_result := v_result || p_replacement || SUBSTR(p_text, v_pos + v_plen);
            RETURN v_result;
          END IF;
        END IF;
      END IF;

      v_result := v_result || v_ch;
      v_pos := v_pos + 1;
    END LOOP;

    RETURN v_result;
  END replace_first_outside_quotes;
BEGIN

  SELECT SQL_FULLTEXT
    INTO LVC_ORIG_SQL_TEXT
    FROM V$SQL
   WHERE SQL_ID = :sql_id_bind
     AND ROWNUM = 1;

  SELECT parsing_schema_name
    INTO LVC_NAME
    FROM v$sql
   WHERE sql_id = :sql_id_bind
     AND ROWNUM = 1;


  SELECT COUNT(*)
    INTO LN_BIND_COUNT
    FROM V$SQL_BIND_CAPTURE
   WHERE SQL_ID = :sql_id_bind;


  IF LN_BIND_COUNT = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Schema: ' || LVC_NAME);
    DBMS_OUTPUT.PUT_LINE(LVC_ORIG_SQL_TEXT);
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------');
    RETURN;
  END IF;


  FOR R1 IN (
    SELECT CHILD_NUMBER, NAME, POSITION, DATATYPE_STRING,
           CASE
             WHEN DATATYPE_STRING LIKE 'TIMESTAMP%' AND VALUE_STRING IS NULL THEN
               TO_CHAR(anydata.accesstimestamp(value_anydata), 'YYYY-MM-DD HH24:MI:SS')
             ELSE VALUE_STRING
           END AS VALUE_STRING,
           sql_id
      FROM V$SQL_BIND_CAPTURE
     WHERE SQL_ID = :sql_id_bind
     ORDER BY CHILD_NUMBER, POSITION
  ) LOOP
    IF (R1.CHILD_NUMBER <> LN_CHILD) THEN
      IF LN_CHILD <> 10000 THEN
        DBMS_OUTPUT.PUT_LINE(LVC_NAME);
        DBMS_OUTPUT.PUT_LINE(LVC_SQL_TEXT);
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------');
      END IF;
      LN_CHILD     := R1.CHILD_NUMBER;
      LVC_SQL_TEXT := LVC_ORIG_SQL_TEXT;
    END IF;

    -- add
    select parsing_schema_name into LVC_NAME from v$sql where sql_id=r1.sql_id and child_number=r1.CHILD_NUMBER;
    -- add end

    IF R1.NAME LIKE ':SYS_B_%' THEN
      LVC_BIND := ':"'||substr(R1.NAME,2)||'"';
    ELSE
      LVC_BIND := R1.NAME;
    END IF;

    IF r1.VALUE_STRING IS NOT NULL THEN
      IF R1.DATATYPE_STRING = 'NUMBER' THEN
        LVC_SQL_TEXT := replace_first_outside_quotes(LVC_SQL_TEXT, LVC_BIND, R1.VALUE_STRING);
      ELSIF R1.DATATYPE_STRING LIKE 'VARCHAR%' THEN
        LVC_SQL_TEXT := replace_first_outside_quotes(LVC_SQL_TEXT, LVC_BIND, ''''||R1.VALUE_STRING||'''');
      ELSE
        LVC_SQL_TEXT := replace_first_outside_quotes(LVC_SQL_TEXT, LVC_BIND, ''''||R1.VALUE_STRING||'''');
      END IF;
    ELSE
       LVC_SQL_TEXT := replace_first_outside_quotes(LVC_SQL_TEXT, LVC_BIND, 'NULL');
    END IF;
  END LOOP;


  DBMS_OUTPUT.PUT_LINE(LVC_NAME);
  DBMS_OUTPUT.PUT_LINE(LVC_SQL_TEXT);
END;
/


prompt ****************************************************************************************
prompt CURSOR
prompt ****************************************************************************************
--select * from table(dbms_xplan.display_cursor('&&sqlid',0,'advanced allstats last'));
select t.*
  from v$sql s,
       table(dbms_xplan.display_cursor(s.sql_id, s.child_number)) t
 where s.sql_id = :sql_id_bind;

prompt ****************************************************************************************
prompt PLAN STAT FROM ASH
prompt ****************************************************************************************
/* Formatted on 2016/11/7 11:36:33 (QP5 v5.256.13226.35510) */


 DECLARE
    i_plan_putout        VARCHAR2 (3000);
    i_plan_output_last   VARCHAR2 (3000) := ' ';
    i_ash_output         VARCHAR2 (3000);
    i_length             NUMBER;
    i_version            VARCHAR2 (20);
 BEGIN
    SELECT /*+ no_parallel */
          SUBSTR (
              banner,
              INSTR (banner, 'Release ') + 8,
              INSTR (SUBSTR (banner, INSTR (banner, 'Release ') + 8), ' '))
      INTO i_version
      FROM v$version
     WHERE banner LIKE 'Oracle Database%';
&_VERSION_11    IF i_version > '11.2'
&_VERSION_11    THEN
&_VERSION_11       FOR c_plan_output
&_VERSION_11          IN (WITH htz
&_VERSION_11                   AS (SELECT SQL_ID,
&_VERSION_11                              CHILD_NUMBER,
&_VERSION_11                              PLAN_HASH_VALUE,
&_VERSION_11                              '' FORMAT
&_VERSION_11                         FROM v$sql
&_VERSION_11                        WHERE sql_id = :sql_id_bind),
&_VERSION_11                   htz_pw
&_VERSION_11                   AS (SELECT t.*,
&_VERSION_11                              ROW_NUMBER ()
&_VERSION_11                              OVER (
&_VERSION_11                                 PARTITION BY sql_id,
&_VERSION_11                                              sql_child_number,
&_VERSION_11                                              sql_plan_line_id
&_VERSION_11                                 ORDER BY tcount DESC)
&_VERSION_11                                 event_order
&_VERSION_11                         FROM (  SELECT sql_id,
&_VERSION_11                                        sql_child_number,
&_VERSION_11                                        sql_plan_line_id,
&_VERSION_11                                        event,
&_VERSION_11                                        COUNT (*) tcount,
&_VERSION_11                                           ROUND (
&_VERSION_11                                                (ratio_to_report (COUNT (*))
&_VERSION_11                                                    OVER ())
&_VERSION_11                                              * 100,
&_VERSION_11                                              2)
&_VERSION_11                                        || '%'
&_VERSION_11                                           pct
&_VERSION_11                                   FROM (SELECT a.sql_id,
&_VERSION_11                                                a.sql_child_number,
&_VERSION_11                                                a.sql_plan_line_id,
&_VERSION_11                                                a.sql_plan_hash_value,
&_VERSION_11                                                DECODE (
&_VERSION_11                                                   a.SESSION_STATE,
&_VERSION_11                                                   'ON CPU', DECODE (
&_VERSION_11                                                                a.SESSION_TYPE,
&_VERSION_11                                                                'BACKGROUND', 'BCPU',
&_VERSION_11                                                                'CPU'),
&_VERSION_11                                                   EVENT)
&_VERSION_11                                                   EVENT
&_VERSION_11                                           FROM v$active_session_history a
&_VERSION_11                                          WHERE a.sql_id = :sql_id_bind)
&_VERSION_11                               GROUP BY sql_id,
&_VERSION_11                                        sql_child_number,
&_VERSION_11                                        sql_plan_line_id,
&_VERSION_11                                        sql_plan_hash_value,
&_VERSION_11                                        event) t),
&_VERSION_11                   cdhtz
&_VERSION_11                   AS (SELECT sql_id,
&_VERSION_11                              child_number,
&_VERSION_11                              n,
&_VERSION_11                              plan_table_output -- get plan line id from plan_table output
&_VERSION_11                                               ,
&_VERSION_11                              CASE
&_VERSION_11                                 WHEN REGEXP_LIKE (
&_VERSION_11                                         plan_table_output,
&_VERSION_11                                         '^[|][*]? *([0-9]+) *[|].*[|]$')
&_VERSION_11                                 THEN
&_VERSION_11                                    REGEXP_REPLACE (
&_VERSION_11                                       plan_table_output,
&_VERSION_11                                       '^[|][*]? *([0-9]+) *[|].*[|]$',
&_VERSION_11                                       '\1')
&_VERSION_11                              END
&_VERSION_11                                 SQL_PLAN_LINE_ID
&_VERSION_11                         FROM (SELECT ROWNUM n,
&_VERSION_11                                      plan_table_output,
&_VERSION_11                                      SQL_ID,
&_VERSION_11                                      CHILD_NUMBER
&_VERSION_11                                 FROM htz,
&_VERSION_11                                      TABLE (
&_VERSION_11                                         DBMS_XPLAN.display_cursor (
&_VERSION_11                                            htz.SQL_ID,
&_VERSION_11                                            htz.CHILD_NUMBER,
&_VERSION_11                                            htz.FORMAT))))
&_VERSION_11                SELECT plan_table_output,
&_VERSION_11                       CASE
&_VERSION_11                          WHEN f.tcount > 0
&_VERSION_11                          THEN
&_VERSION_11                                SUBSTR (event, 1, 25)
&_VERSION_11                             || '('
&_VERSION_11                             || tcount
&_VERSION_11                             || ')('
&_VERSION_11                             || pct
&_VERSION_11                             || ')'
&_VERSION_11                       END
&_VERSION_11                          cast_info,
&_VERSION_11                       f.SQL_PLAN_LINE_ID
&_VERSION_11                  FROM cdhtz e, htz_pw f
&_VERSION_11                 WHERE     e.sql_id = f.sql_id(+)
&_VERSION_11                       AND e.child_number = f.sql_child_number(+)
&_VERSION_11                       AND e.sql_plan_line_id = f.sql_plan_line_id(+)
&_VERSION_11              ORDER BY e.sql_id, e.child_number, e.n)
&_VERSION_11       LOOP
&_VERSION_11          IF (c_plan_output.plan_table_output <> i_plan_output_last)
&_VERSION_11          THEN
&_VERSION_11             IF (c_plan_output.cast_info IS NOT NULL)
&_VERSION_11             THEN
&_VERSION_11                DBMS_OUTPUT.put_line (
&_VERSION_11                      c_plan_output.plan_table_output
&_VERSION_11                   || RPAD (c_plan_output.cast_info, 37)
&_VERSION_11                   || '|');
&_VERSION_11             ELSE
&_VERSION_11                DBMS_OUTPUT.put_line (c_plan_output.plan_table_output);
&_VERSION_11                i_plan_output_last := c_plan_output.plan_table_output;
&_VERSION_11             END IF;
&_VERSION_11
&_VERSION_11             i_plan_output_last := c_plan_output.plan_table_output;
&_VERSION_11          ELSE
&_VERSION_11             IF (c_plan_output.cast_info IS NOT NULL)
&_VERSION_11             THEN
&_VERSION_11                SELECT LENGTH (i_plan_output_last) INTO i_length FROM DUAL;
&_VERSION_11
&_VERSION_11                DBMS_OUTPUT.put_line (
&_VERSION_11                      '|'
&_VERSION_11                   || LPAD (' ', i_length - 2)
&_VERSION_11                   || '|'
&_VERSION_11                   || RPAD (c_plan_output.cast_info, 37)
&_VERSION_11                   || '|');
&_VERSION_11             ELSE
&_VERSION_11                DBMS_OUTPUT.put_line (c_plan_output.plan_table_output);
&_VERSION_11             END IF;
&_VERSION_11          END IF;
&_VERSION_11       END LOOP;
&_VERSION_11    END IF;
 END;
 /


prompt
prompt ****************************************************************************************
prompt AWR
prompt ****************************************************************************************

SELECT t.*
FROM dba_hist_sqlstat h,
     table(dbms_xplan.display_awr(h.sql_id, h.plan_hash_value)) t
WHERE h.sql_id = :sql_id_bind
  AND NOT EXISTS (
    SELECT 1 FROM v$sql s2 WHERE s2.sql_id = h.sql_id
  );

prompt
prompt ****************************************************************************************
prompt SQL MONITOR
prompt ****************************************************************************************

SELECT
&_VERSION_11  DBMS_SQLTUNE.report_sql_monitor(sql_id       => :sql_id_bind,
&_VERSION_11                                  type         => 'TEXT',
&_VERSION_11                                  report_level => 'NONE+PLAN+ACTIVITY-SQL_FULLTEXT-SQL_TEXT-SESSIONS-OTHER') AS report
FROM dual;




PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | infromation  from v$sqlstats               |
PROMPT +------------------------------------------------------------------------+
PROMPT

SELECT CASE
        WHEN EXECUTIONS < 1000 THEN TO_CHAR(EXECUTIONS)
        WHEN EXECUTIONS < 10000 THEN TO_CHAR(ROUND(EXECUTIONS / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(EXECUTIONS / 10000, 2)) || 'W'
        END AS EXECUTIONS,
       CASE
        WHEN CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
        END AS CPU_PRE_EXEC,
       CASE
        WHEN ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
        END AS ELA_PRE_EXEC,
       CASE
        WHEN DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 1000
            THEN TO_CHAR(ROUND(DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS),2))
        WHEN DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 10000
            THEN TO_CHAR(ROUND(DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 10000, 2)) || 'W'
        END AS DISK_PRE_EXEC,
       CASE
        WHEN BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 1000
            THEN TO_CHAR(ROUND(BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS),2))
        WHEN BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 10000
            THEN TO_CHAR(ROUND(BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 10000, 2)) || 'W'
    END AS GET_PRE_EXEC,
       CASE
        WHEN ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 1000
            THEN TO_CHAR(ROUND(ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS),2))
        WHEN ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 10000
            THEN TO_CHAR(ROUND(ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 10000, 2)) || 'W'
    END AS ROWS_PRE_EXEC,
       CASE
        WHEN fetches/ DECODE(executions, 0, 1, executions) < 1000 THEN TO_CHAR(ROUND(fetches / DECODE(executions, 0, 1, executions),2))
        WHEN fetches / DECODE(executions, 0, 1, executions) < 10000 THEN TO_CHAR(ROUND(fetches / DECODE(executions, 0, 1, executions) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(fetches / DECODE(executions, 0, 1, executions) / 10000, 2)) || 'W'
        END AS ROWS_PRE_FETCHES,
      CASE
        WHEN APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS APP_WAIT_PRE,
        CASE
        WHEN CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS CON_WAIT_PER,
         case
               WHEN CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS CLU_WAIT_PER,
               CASE
        WHEN USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS USER_IO_WAIT_PER,
               CASE
        WHEN PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS PLSQL_WAIT_PER,
               CASE
        WHEN JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS JAVA_WAIT_PER,
    SQL_PROFILE
  FROM v$sqlarea
where sql_id = :sql_id_bind;

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | information from v$sql                 |
PROMPT +------------------------------------------------------------------------+
PROMPT

SELECT
    CASE
        WHEN EXECUTIONS < 1000 THEN TO_CHAR(EXECUTIONS)
        WHEN EXECUTIONS < 10000 THEN TO_CHAR(ROUND(EXECUTIONS / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(EXECUTIONS / 10000, 2)) || 'W'
    END AS EXECUTIONS,
    plan_hash_value,
    child_number AS c,
    PARSING_SCHEMA_NAME AS username,
      CASE
        WHEN CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(CPU_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS CPU_PRE_EXEC,
    CASE
        WHEN ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS ELA_PRE_EXEC,
    CASE
        WHEN DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 1000
            THEN TO_CHAR(ROUND(DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS),2))
        WHEN DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 10000
            THEN TO_CHAR(ROUND(DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(DISK_READS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 10000, 2)) || 'W'
    END AS DISK_PRE_EXEC,
    CASE
        WHEN BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 1000
            THEN TO_CHAR(ROUND(BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS),2))
        WHEN BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 10000
            THEN TO_CHAR(ROUND(BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(BUFFER_GETS / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 10000, 2)) || 'W'
    END AS GET_PRE_EXEC,
    CASE
        WHEN ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 1000
            THEN TO_CHAR(ROUND(ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS),2))
        WHEN ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) < 10000
            THEN TO_CHAR(ROUND(ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(ROWS_PROCESSED / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 10000, 2)) || 'W'
    END AS ROWS_PRE_EXEC,
    CASE
        WHEN ROWS_PROCESSED / DECODE(FETCHES, 0, 1, FETCHES) < 1000
            THEN TO_CHAR(ROUND(ROWS_PROCESSED / DECODE(FETCHES, 0, 1, FETCHES),2))
        WHEN ROWS_PROCESSED / DECODE(FETCHES, 0, 1, FETCHES) < 10000
            THEN TO_CHAR(ROUND(ROWS_PROCESSED / DECODE(FETCHES, 0, 1, FETCHES) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(ROWS_PROCESSED / DECODE(FETCHES, 0, 1, FETCHES) / 10000, 2)) || 'W'
    END AS ROWS_PRE_FETCHES,
  CASE
        WHEN APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(APPLICATION_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS APP_PRE_EXEC,
        CASE
        WHEN CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(CONCURRENCY_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS CON_PRE_EXEC,
        CASE
        WHEN CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(CLUSTER_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS CLU_WAIT_PER,
        CASE
        WHEN USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(USER_IO_WAIT_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS USER_IO_WAIT_PER,
        CASE
        WHEN PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(PLSQL_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS PLSQL_WAIT_PER,
        CASE
        WHEN JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 < 1000
            THEN ROUND(JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000, 2) || 'ms'
        WHEN JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 < 60
            THEN ROUND(JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60, 2) || 's'
        WHEN ELAPSED_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 < 60
            THEN ROUND(JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(JAVA_EXEC_TIME / DECODE(EXECUTIONS, 0, 1, EXECUTIONS) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS JAVA_WAIT_PER,
    SUBSTR(FIRST_LOAD_TIME, 6, 10) || '.' || SUBSTR(LAST_LOAD_TIME, 6, 10) AS f_l_time
FROM v$sql s
WHERE sql_id = :sql_id_bind
ORDER BY plan_hash_value;



PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | information from awr   sysdate-7                                       |
PROMPT +------------------------------------------------------------------------+
PROMPT
  SELECT TO_CHAR (END_INTERVAL_TIME, 'dd hh24') end_time,
         TRIM (a.instance_number) instance_number,
         a.parsing_schema_name,
         a.plan_hash_value,
      CASE
        WHEN executions_delta < 1000 THEN TO_CHAR(executions_delta)
        WHEN executions_delta < 10000 THEN TO_CHAR(ROUND(executions_delta / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(executions_delta / 10000, 2)) || 'W'
    END AS EXECUTIONS,
    CASE
        WHEN cpu_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 < 1000 THEN ROUND(cpu_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2) || 'ms'
        WHEN cpu_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 < 60 THEN ROUND(cpu_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60, 2) || 's'
        WHEN cpu_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 < 60 THEN ROUND(cpu_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(cpu_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS CPU_PRE_EXEC,
    CASE
        WHEN elapsed_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 < 1000 THEN ROUND(elapsed_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2) || 'ms'
        WHEN elapsed_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 < 60 THEN ROUND(elapsed_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60, 2) || 's'
        WHEN elapsed_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 < 60 THEN ROUND(elapsed_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(elapsed_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS ELA_PRE_EXEC,
    CASE
        WHEN disk_reads_delta / DECODE(executions_delta, 0, 1, executions_delta) < 1000 THEN TO_CHAR(ROUND(disk_reads_delta / DECODE(executions_delta, 0, 1, executions_delta),2))
        WHEN disk_reads_delta / DECODE(executions_delta, 0, 1, executions_delta) < 10000 THEN TO_CHAR(ROUND(disk_reads_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(disk_reads_delta / DECODE(executions_delta, 0, 1, executions_delta) / 10000, 2)) || 'W'
    END AS DISK_PRE_EXEC,
        CASE
        WHEN BUFFER_GETS_DELTA / DECODE(executions_delta, 0, 1, executions_delta) < 1000 THEN TO_CHAR(ROUND(BUFFER_GETS_DELTA / DECODE(executions_delta, 0, 1, executions_delta),2))
        WHEN BUFFER_GETS_DELTA / DECODE(executions_delta, 0, 1, executions_delta) < 10000 THEN TO_CHAR(ROUND(BUFFER_GETS_DELTA / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(BUFFER_GETS_DELTA / DECODE(executions_delta, 0, 1, executions_delta) / 10000, 2)) || 'W'
    END AS GET_PRE_EXEC,
    CASE
        WHEN rows_processed_delta / DECODE(executions_delta, 0, 1, executions_delta) < 1000 THEN TO_CHAR(ROUND(rows_processed_delta / DECODE(executions_delta, 0, 1, executions_delta),2))
        WHEN rows_processed_delta / DECODE(executions_delta, 0, 1, executions_delta) < 10000 THEN TO_CHAR(ROUND(rows_processed_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(rows_processed_delta / DECODE(executions_delta, 0, 1, executions_delta) / 10000, 2)) || 'W'
    END AS ROWS_PRE_EXEC,
    CASE
        WHEN fetches_delta / DECODE(executions_delta, 0, 1, executions_delta) < 1000 THEN TO_CHAR(ROUND(fetches_delta / DECODE(executions_delta, 0, 1, executions_delta),2))
        WHEN fetches_delta / DECODE(executions_delta, 0, 1, executions_delta) < 10000 THEN TO_CHAR(ROUND(fetches_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(fetches_delta / DECODE(executions_delta, 0, 1, executions_delta) / 10000, 2)) || 'W'
    END AS ROWS_PRE_FETCHES,
    CASE
        WHEN direct_writes_delta / DECODE(executions_delta, 0, 1, executions_delta) < 1000 THEN TO_CHAR(ROUND(direct_writes_delta / DECODE(executions_delta, 0, 1, executions_delta),2))
        WHEN direct_writes_delta / DECODE(executions_delta, 0, 1, executions_delta) < 10000 THEN TO_CHAR(ROUND(direct_writes_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(direct_writes_delta / DECODE(executions_delta, 0, 1, executions_delta) / 10000, 2)) || 'W'
    END AS WRITE_PRE_EXEC,
    CASE
        WHEN IOWAIT_DELTA / DECODE(executions_delta, 0, 1, executions_delta) / 1000 < 1000 THEN ROUND(IOWAIT_DELTA / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2) || 'ms'
        WHEN IOWAIT_DELTA / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 < 60 THEN ROUND(IOWAIT_DELTA / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60, 2) || 's'
        WHEN IOWAIT_DELTA / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 < 60 THEN ROUND(IOWAIT_DELTA / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(IOWAIT_DELTA / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS IOWAIT_PRE_EXEC,
    CASE
        WHEN parse_calls_delta / DECODE(executions_delta, 0, 1, executions_delta) < 1000 THEN TO_CHAR(ROUND(parse_calls_delta / DECODE(executions_delta, 0, 1, executions_delta),2))
        WHEN parse_calls_delta / DECODE(executions_delta, 0, 1, executions_delta) < 10000 THEN TO_CHAR(ROUND(parse_calls_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(parse_calls_delta / DECODE(executions_delta, 0, 1, executions_delta) / 10000, 2)) || 'W'
    END AS PARSE_PRE_EXEC,
    CASE
        WHEN sorts_delta / DECODE(executions_delta, 0, 1, executions_delta) < 1000 THEN TO_CHAR(ROUND(sorts_delta / DECODE(executions_delta, 0, 1, executions_delta),2))
        WHEN sorts_delta / DECODE(executions_delta, 0, 1, executions_delta) < 10000 THEN TO_CHAR(ROUND(sorts_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(sorts_delta / DECODE(executions_delta, 0, 1, executions_delta) / 10000, 2)) || 'W'
    END AS SORTS_PRE_EXEC,
    CASE
        WHEN apwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 < 1000 THEN ROUND(apwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2) || 'ms'
        WHEN apwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 < 60 THEN ROUND(apwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60, 2) || 's'
        WHEN apwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 < 60 THEN ROUND(apwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(apwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS APP_WAIT_PRE_EXEC,
    CASE
        WHEN ccwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 < 1000 THEN ROUND(ccwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2) || 'ms'
        WHEN ccwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 < 60 THEN ROUND(ccwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60, 2) || 's'
        WHEN ccwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 < 60 THEN ROUND(ccwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(ccwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS CONC_WAIT_PRE_EXEC,
    CASE
        WHEN clwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 < 1000 THEN ROUND(clwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2) || 'ms'
        WHEN clwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 < 60 THEN ROUND(clwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60, 2) || 's'
        WHEN clwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 < 60 THEN ROUND(clwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(clwait_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS CLUSTER_WAIT_PRE_EXEC,
    CASE
        WHEN plsexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 < 1000 THEN ROUND(plsexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2) || 'ms'
        WHEN plsexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 < 60 THEN ROUND(plsexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60, 2) || 's'
        WHEN plsexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 < 60 THEN ROUND(plsexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(plsexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS PLSQL_WAIT_PRE_EXEC,
    CASE
        WHEN javexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 < 1000 THEN ROUND(javexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000, 2) || 'ms'
        WHEN javexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 < 60 THEN ROUND(javexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60, 2) || 's'
        WHEN javexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 < 60 THEN ROUND(javexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60, 2) || 'm'
        ELSE ROUND(javexec_time_delta / DECODE(executions_delta, 0, 1, executions_delta) / 1000 / 60 / 60 / 60, 2) || 'h'
    END AS JAVA_WAIT_PRE_EXEC
    FROM dba_hist_sqlstat a, dba_hist_snapshot b
   WHERE     a.sql_id = :sql_id_bind
         AND a.snap_id = b.snap_id
         AND b.END_INTERVAL_TIME > SYSDATE - 5
         AND a.instance_number = b.instance_number
ORDER BY 1
/



prompt
prompt ****************************************************************************************
prompt SQL WAIT HIST
prompt ****************************************************************************************
break on program
SELECT substr(PROGRAM,1,30) PROGRAM,EVENT, SUM(CNT) TOTAL, WAIT_CLASS
  FROM (SELECT DECODE(SESSION_STATE,
                      'ON CPU',
                      DECODE(SESSION_TYPE, 'BACKGROUND', 'BCPU', 'CPU'),
                      EVENT) EVENT,
               REPLACE(TRANSLATE(DECODE(SESSION_STATE,
                                        'ON CPU',
                                        DECODE(SESSION_TYPE,
                                               'BACKGROUND',
                                               'BCPU',
                                               'CPU'),
                                        WAIT_CLASS),
                                 ' $',
                                 '____'),
                       '/') WAIT_CLASS,
               PROGRAM,
               1 CNT
          FROM V$ACTIVE_SESSION_HISTORY
         WHERE SQL_ID = :sql_id_bind
           AND SAMPLE_TIME >= SYSDATE - 4 / 24
           AND SAMPLE_TIME <= SYSDATE)
 GROUP BY EVENT, WAIT_CLASS, PROGRAM
 ORDER BY PROGRAM,TOTAL DESC;

prompt
prompt ****************************************************************************************
prompt OBJECT SIZE
prompt ****************************************************************************************
break on owner on segment_name
/* Formatted on 2016/3/10 10:06:06 (QP5 v5.256.13226.35510) */
--WITH t
--     AS (SELECT /*+ materialize */
--                DISTINCT OBJECT_OWNER, OBJECT_NAME
--           FROM (SELECT OBJECT_OWNER, OBJECT_NAME
--                   FROM V$SQL_PLAN
--                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL
--                 UNION ALL
--                 SELECT OBJECT_OWNER, OBJECT_NAME
--                   FROM DBA_HIST_SQL_PLAN
--                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL)),
--     tt
--     AS (SELECT /*+materialize  no_merge */
--                DISTINCT table_owner, table_name
--           FROM dba_indexes
--          WHERE (owner, index_name) IN (SELECT object_owner, object_name
--                                          FROM t)),
--     t_index
--     AS (  SELECT /*+ materialize merge  */
--                 owner,
--                  segment_name,
--                  segment_type,
--                  TRUNC (SUM (bytes / 1024 / 1024)) s_size,
--                  '***' i_index
--             FROM (SELECT /*+  */
--                         NVL (u.name, 'SYS') owner,
--                          o.name segment_name,
--                          so.object_type segment_type,
--                          s.blocks * ts.blocksize bytes
--                     FROM sys.user$ u,
--                          sys.obj$ o,
--                          sys.ts$ ts,
--                          sys.sys_objects so,
--                          sys.seg$ s,
--                          sys.file$ f
--                    WHERE     s.file# = so.header_file
--                          AND s.block# = so.header_block
--                          AND s.ts# = so.ts_number
--                          AND s.ts# = ts.ts#
--                          AND o.obj# = so.object_id
--                          AND o.owner# = u.user#(+)
--                          AND s.type# = so.segment_type_id
--                          AND o.type# = so.object_type_id
--                          AND s.ts# = f.ts#
--                          AND s.file# = f.relfile#) a
--            WHERE (owner, segment_name) IN (SELECT table_owner, table_name
--                                              FROM tt)
--         GROUP BY a.owner, a.segment_type, a.segment_name),
--     t_table
--     AS (  SELECT /*+ materialize merge */
--                 owner,
--                  segment_name,
--                  segment_type,
--                  TRUNC (SUM (bytes / 1024 / 1024)) s_size
--             FROM (SELECT /*+  */
--                         NVL (u.name, 'SYS') owner,
--                          o.name segment_name,
--                          so.object_type segment_type,
--                          s.blocks * ts.blocksize bytes
--                     FROM sys.user$ u,
--                          sys.obj$ o,
--                          sys.ts$ ts,
--                          sys.sys_objects so,
--                          sys.seg$ s,
--                          sys.file$ f
--                    WHERE     s.file# = so.header_file
--                          AND s.block# = so.header_block
--                          AND s.ts# = so.ts_number
--                          AND s.ts# = ts.ts#
--                          AND o.obj# = so.object_id
--                          AND o.owner# = u.user#(+)
--                          AND s.type# = so.segment_type_id
--                          AND o.type# = so.object_type_id
--                          AND s.ts# = f.ts#
--                          AND s.file# = f.relfile#) a
--            WHERE (a.owner, a.segment_name) IN (SELECT object_owner,
--                                                       object_name
--                                                  FROM t)
--         GROUP BY owner, segment_type, segment_name)
--  SELECT t_table.owner,
--            (SELECT t_index.i_index
--               FROM t_index
--              WHERE     t_index.owner = t_table.owner
--                    AND t_index.segment_name = t_table.segment_name
--                    AND t_index.segment_type = t_table.segment_type)
--         || t_table.segment_name
--            segment_name,
--         t_table.segment_type,
--         t_table.s_size
--    FROM t_table
--ORDER BY owner, segment_name, segment_type
--/
--

/* Formatted on 2016/3/10 12:20:48 (QP5 v5.256.13226.35510) */
/* Formatted on 2018/4/26 14:32:54 (QP5 v5.300) */
WITH t
     AS (SELECT /*+ materialize */
                DISTINCT OBJECT_OWNER, OBJECT_NAME
           FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM V$SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL
                 UNION ALL
                 SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM DBA_HIST_SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL)),
     tt
     AS (SELECT /*+materialize  no_merge */
                DISTINCT table_owner, table_name
           FROM (SELECT table_owner, table_name
                   FROM dba_indexes
                  WHERE (owner, index_name) IN
                            (SELECT object_owner, object_name
                               FROM t)
                 UNION
                 SELECT owner, table_name
                   FROM dba_tables
                  WHERE (owner, table_name) IN
                            (SELECT object_owner, object_name
                               FROM t)))
  SELECT owner,
         segment_name,
         segment_type,
         TRUNC (SUM (bytes / 1024 / 1024)) s_size
    FROM (SELECT owner,
                    (SELECT '***'
                       FROM tt
                      WHERE     a.owner = tt.table_owner
                            AND a.segment_name = tt.table_name)
                 || segment_name
                     segment_name,
                 segment_type,
                 bytes
            FROM (SELECT owner,
                         segment_name,
                         segment_type,
                           DECODE (BITAND (segment_flags, 131072),
                                   131072, blocks,
                                   (DECODE (BITAND (segment_flags, 1),
                                            1, DBMS_SPACE_ADMIN.segment_number_blocks (
                                                   tablespace_id,
                                                   relative_fno,
                                                   header_block,
                                                   segment_type_id,
                                                   buffer_pool_id,
                                                   segment_flags,
                                                   segment_objd,
                                                   blocks),
                                            blocks)))
                         * blocksize
                             bytes
                    FROM (SELECT NVL (u.name, 'SYS')   OWNER,
                                 o.name                SEGMENT_NAME,
                                 so.object_type        SEGMENT_TYPE,
                                 s.type#               SEGMENT_TYPE_ID,
                                 ts.ts#                TABLESPACE_ID,
                                 ts.name               TABLESPACE_NAME,
                                 ts.blocksize          BLOCKSIZE,
                                 f.file#               HEADER_FILE,
                                 s.block#              HEADER_BLOCK,
                                 s.blocks * ts.blocksize BYTES,
                                 s.blocks              BLOCKS,
                                 s.file#               RELATIVE_FNO,
                                 s.cachehint           BUFFER_POOL_ID,
                                 NVL (s.spare1, 0)     SEGMENT_FLAGS,
                                 o.dataobj#            SEGMENT_OBJD
                            FROM sys.user$      u,
                                 sys.obj$       o,
                                 sys.ts$        ts,
                                 sys.sys_objects so,
                                 sys.seg$       s,
                                 sys.file$      f
                           WHERE     s.file# = so.header_file
                                 AND s.block# = so.header_block
                                 AND s.ts# = so.ts_number
                                 AND s.ts# = ts.ts#
                                 AND o.obj# = so.object_id
                                 AND o.owner# = u.user#(+)
                                 AND s.type# = so.segment_type_id
                                 AND o.type# = so.object_type_id
                                 AND s.ts# = f.ts#
                                 AND s.file# = f.relfile#)) a
           WHERE (a.owner, a.segment_name) IN (SELECT object_owner, object_name
                                                 FROM t))
GROUP BY owner, segment_type, segment_name
ORDER BY owner, segment_name
/

prompt
prompt ****************************************************************************************
prompt TABLES
prompt ****************************************************************************************
break on owner
/* Formatted on 2015/5/6 22:38:10 (QP5 v5.240.12305.39446) */
WITH t
     AS (SELECT /*+ materialize */
               DISTINCT OBJECT_OWNER, OBJECT_NAME
           FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM V$SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL
                 UNION ALL
                 SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM DBA_HIST_SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL))
  SELECT a.owner,
         a.TABLE_NAME,
         -- TABLESPACE_NAME,
         a.LOGGING||'.'||a.TEMPORARY l_t,
         a.BUFFER_POOL,
         LTRIM (a.DEGREE) DEGREE,
         a.PARTITIONED,
         a.NUM_ROWS,
         a.BLOCKS,
         a.EMPTY_BLOCKS,
         --a.AVG_SPACE,
         --a.AVG_ROW_LEN,
         trunc((a.blocks*tp.block_size)/1024/1024) block_size,
         trunc((a.AVG_ROW_LEN*a.NUM_ROWS)/1024/1024) avg_size,
--        STALE_STATS,
         a.LAST_ANALYZED
    FROM DBA_TABLES a
--     , dba_tab_statistics b
        ,dba_tablespaces tp
   WHERE     (a.OWNER, a.TABLE_NAME) IN
                (SELECT table_owner, table_name
                   FROM dba_indexes
                  WHERE (owner, index_name) IN (SELECT * FROM t)
                 UNION ALL
                 SELECT * FROM t)
--         AND a.owner = b.owner(+)
--         AND a.table_name = b.table_name(+)
         and a.tablespace_name=tp.tablespace_name
ORDER BY owner, table_name;
clear breaks;

prompt
prompt ****************************************************************************************
prompt TABLE COLUMNS
prompt ****************************************************************************************
break on owner on table_name

col column_id for 999 heading 'Col|Id'
col d_type for a18 heading 'Column|Date Type'
col num_distinct for 9999999 heading 'NUM|DISTINCT'
col num_buckets for 9999 heading 'BUCK'
WITH t AS
(SELECT /*+ materialize */DISTINCT OBJECT_OWNER, OBJECT_NAME
          FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                  FROM V$SQL_PLAN
                 WHERE SQL_ID = :sql_id_bind
                   AND OBJECT_NAME IS NOT NULL
                UNION ALL
                SELECT OBJECT_OWNER, OBJECT_NAME
                  FROM DBA_HIST_SQL_PLAN
                 WHERE SQL_ID = :sql_id_bind
                   AND OBJECT_NAME IS NOT NULL))
SELECT OWNER,
       TABLE_NAME,
       COLUMN_NAME,
       data_type || '(' || data_length || ')' d_type,
       NULLABLE,
       DENSITY,
       NUM_NULLS,
       num_distinct,
       NUM_BUCKETS,
       AVG_COL_LEN,
       sample_size,
       substr(HISTOGRAM,0,5) HISTOGRAM,
       LAST_ANALYZED
  FROM DBA_TAB_COLS tb
 WHERE (OWNER, TABLE_NAME) IN
       (SELECT table_owner,table_name FROM dba_indexes
         WHERE (owner,index_name) IN (SELECT * FROM t)
        UNION ALL SELECT * FROM t)
 ORDER BY owner,table_name,COLUMN_ID;
clear breaks;


prompt
prompt ****************************************************************************************
prompt TABLE COLUMNS Min and MAX VALUE
prompt ****************************************************************************************


DECLARE
     CURSOR c_stats IS
         WITH t AS
         (SELECT /*+ materialize */DISTINCT OBJECT_OWNER, OBJECT_NAME
                   FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                           FROM V$SQL_PLAN
                          WHERE SQL_ID = :sql_id_bind
                            AND OBJECT_NAME IS NOT NULL
                         UNION ALL
                         SELECT OBJECT_OWNER, OBJECT_NAME
                           FROM DBA_HIST_SQL_PLAN
                          WHERE SQL_ID = :sql_id_bind
                            AND OBJECT_NAME IS NOT NULL))
         SELECT tb.OWNER,
                tb.TABLE_NAME,
                tb.COLUMN_NAME,
                tb.data_type || '(' || tb.data_length || ')' d_type,
                tb.data_type,
                s.low_value,
                s.high_value
           FROM DBA_TAB_COLS tb
           LEFT JOIN dba_tab_col_statistics s
             ON tb.owner = s.owner
            AND tb.table_name = s.table_name
            AND tb.column_name = s.column_name
          WHERE (tb.OWNER, tb.TABLE_NAME) IN
                (SELECT table_owner,table_name FROM dba_indexes
                  WHERE (owner,index_name) IN (SELECT * FROM t)
                 UNION ALL SELECT * FROM t)
          ORDER BY tb.owner, tb.table_name, tb.COLUMN_ID;

     v_number NUMBER;
     v_date DATE;
     v_varchar VARCHAR2(4000);
     v_min_readable VARCHAR2(30);
     v_max_readable VARCHAR2(30);
     v_output_line VARCHAR2(200);
BEGIN
     DBMS_OUTPUT.PUT_LINE(RPAD('OWNER', 15) || ' ' ||
                         RPAD('TABLE_NAME', 30) || ' ' ||
                         RPAD('COLUMN_NAME', 20) || ' ' ||
                         RPAD('COLUMN_TYPE', 15) || ' ' ||
                         RPAD('MIN_VALUE', 30) || ' ' ||
                         RPAD('MAX_VALUE', 30));
     DBMS_OUTPUT.PUT_LINE(RPAD('-', 15, '-') || ' ' ||
                         RPAD('-', 30, '-') || ' ' ||
                         RPAD('-', 20, '-') || ' ' ||
                         RPAD('-', 15, '-') || ' ' ||
                         RPAD('-', 30, '-') || ' ' ||
                         RPAD('-', 30, '-'));

&_TABLE_COL_VALUE     FOR rec IN c_stats LOOP
&_TABLE_COL_VALUE         BEGIN
&_TABLE_COL_VALUE             IF rec.low_value IS NULL THEN
&_TABLE_COL_VALUE                 v_min_readable := 'NULL';
&_TABLE_COL_VALUE             ELSE
&_TABLE_COL_VALUE                 CASE rec.data_type
&_TABLE_COL_VALUE                     WHEN 'NUMBER' THEN
&_TABLE_COL_VALUE                         DBMS_STATS.CONVERT_RAW_VALUE(rec.low_value, v_number);
&_TABLE_COL_VALUE                         v_min_readable := TO_CHAR(v_number);
&_TABLE_COL_VALUE                     WHEN 'DATE' THEN
&_TABLE_COL_VALUE                         DBMS_STATS.CONVERT_RAW_VALUE(rec.low_value, v_date);
&_TABLE_COL_VALUE                         v_min_readable := TO_CHAR(v_date, 'YYYY-MM-DD HH24:MI:SS');
&_TABLE_COL_VALUE                     WHEN 'VARCHAR2' THEN
&_TABLE_COL_VALUE                         DBMS_STATS.CONVERT_RAW_VALUE(rec.low_value, v_varchar);
&_TABLE_COL_VALUE                         v_min_readable := v_varchar;
&_TABLE_COL_VALUE                     WHEN 'CHAR' THEN
&_TABLE_COL_VALUE                         DBMS_STATS.CONVERT_RAW_VALUE(rec.low_value, v_varchar);
&_TABLE_COL_VALUE                         v_min_readable := v_varchar;
&_TABLE_COL_VALUE                     ELSE
&_TABLE_COL_VALUE                         v_min_readable := 'N/A';
&_TABLE_COL_VALUE                 END CASE;
&_TABLE_COL_VALUE             END IF;
&_TABLE_COL_VALUE         EXCEPTION
&_TABLE_COL_VALUE             WHEN OTHERS THEN
&_TABLE_COL_VALUE                 v_min_readable := 'ERROR';
&_TABLE_COL_VALUE         END;
&_TABLE_COL_VALUE
&_TABLE_COL_VALUE         -- substitute MAX_VALUE
&_TABLE_COL_VALUE         BEGIN
&_TABLE_COL_VALUE             IF rec.high_value IS NULL THEN
&_TABLE_COL_VALUE                 v_max_readable := 'NULL';
&_TABLE_COL_VALUE             ELSE
&_TABLE_COL_VALUE                 CASE rec.data_type
&_TABLE_COL_VALUE                     WHEN 'NUMBER' THEN
&_TABLE_COL_VALUE                         DBMS_STATS.CONVERT_RAW_VALUE(rec.high_value, v_number);
&_TABLE_COL_VALUE                         v_max_readable := TO_CHAR(v_number);
&_TABLE_COL_VALUE                     WHEN 'DATE' THEN
&_TABLE_COL_VALUE                         DBMS_STATS.CONVERT_RAW_VALUE(rec.high_value, v_date);
&_TABLE_COL_VALUE                         v_max_readable := TO_CHAR(v_date, 'YYYY-MM-DD HH24:MI:SS');
&_TABLE_COL_VALUE                     WHEN 'VARCHAR2' THEN
&_TABLE_COL_VALUE                         DBMS_STATS.CONVERT_RAW_VALUE(rec.high_value, v_varchar);
&_TABLE_COL_VALUE                         v_max_readable := v_varchar;
&_TABLE_COL_VALUE                     WHEN 'CHAR' THEN
&_TABLE_COL_VALUE                         DBMS_STATS.CONVERT_RAW_VALUE(rec.high_value, v_varchar);
&_TABLE_COL_VALUE                         v_max_readable := v_varchar;
&_TABLE_COL_VALUE                     ELSE
&_TABLE_COL_VALUE                         v_max_readable := 'N/A';
&_TABLE_COL_VALUE                 END CASE;
&_TABLE_COL_VALUE             END IF;
&_TABLE_COL_VALUE         EXCEPTION
&_TABLE_COL_VALUE             WHEN OTHERS THEN
&_TABLE_COL_VALUE                 v_max_readable := 'ERROR';
&_TABLE_COL_VALUE         END;
&_TABLE_COL_VALUE         IF LENGTH(v_min_readable) > 30 THEN
&_TABLE_COL_VALUE             v_min_readable := SUBSTR(v_min_readable, 1, 27) || '...';
&_TABLE_COL_VALUE         END IF;
&_TABLE_COL_VALUE
&_TABLE_COL_VALUE         IF LENGTH(v_max_readable) > 30 THEN
&_TABLE_COL_VALUE             v_max_readable := SUBSTR(v_max_readable, 1, 27) || '...';
&_TABLE_COL_VALUE         END IF;
&_TABLE_COL_VALUE         DBMS_OUTPUT.PUT_LINE(RPAD(rec.OWNER, 15) || ' ' ||
&_TABLE_COL_VALUE                             RPAD(rec.TABLE_NAME, 30) || ' ' ||
&_TABLE_COL_VALUE                             RPAD(rec.COLUMN_NAME, 20) || ' ' ||
&_TABLE_COL_VALUE                             RPAD(rec.d_type, 15) || ' ' ||
&_TABLE_COL_VALUE                             RPAD(v_min_readable, 30) || ' ' ||
&_TABLE_COL_VALUE                             RPAD(v_max_readable, 30));
&_TABLE_COL_VALUE     END LOOP;
 END;
/


prompt
prompt ****************************************************************************************
prompt INDEX STATUS
prompt ****************************************************************************************
break on OWNER on INDEX_NAME
WITH t
     AS (SELECT /*+ materialize */
                DISTINCT OBJECT_OWNER, OBJECT_NAME
           FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM V$SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL
                 UNION ALL
                 SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM DBA_HIST_SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL)),
     tt
     AS (SELECT /*+ materialize */
               i.OWNER,
                i.INDEX_NAME,
                i.status,
                PARTITIONED
           FROM DBA_INDEXES i
          WHERE     (i.TABLE_OWNER, i.TABLE_NAME) IN (SELECT table_owner,
                                                             table_name
                                                        FROM dba_indexes
                                                       WHERE (owner,
                                                              index_name) IN (SELECT *
                                                                                FROM t)
                                                      UNION ALL
                                                      SELECT * FROM t)
                AND i.status NOT IN ('VALID'))
SELECT OWNER,
       INDEX_NAME,
       '' PARTITION_NAME,
       '' SUBPARTITION_NAME,
       status
  FROM tt
 WHERE tt.PARTITIONED = 'NO'
UNION ALL
SELECT p.INDEX_OWNER,
       p.INDEX_NAME,
       PARTITION_NAME,
       '' SUBPARTITION_NAME,
       p.status
  FROM dba_ind_partitions p
 WHERE     (p.INDEX_OWNER, p.INDEX_NAME) IN (SELECT index_owner, INDEX_NAME
                                               FROM tt
                                              WHERE tt.PARTITIONED = 'YES')
       AND p.status NOT IN ('USABLE')
UNION ALL
SELECT p.INDEX_OWNER,
       p.INDEX_NAME,
       PARTITION_NAME,
       SUBPARTITION_NAME,
       p.status
  FROM dba_ind_subpartitions p
 WHERE     (p.INDEX_OWNER, p.INDEX_NAME) IN (SELECT index_owner, INDEX_NAME
                                               FROM tt
                                              WHERE tt.PARTITIONED = 'YES')
       AND p.status NOT IN ('USABLE')
ORDER BY 1,2,3,4
/
prompt
prompt ****************************************************************************************
prompt INDEX INFO
prompt ****ucptdvs "UNIQUENESS COMPRESSION PARTITIONED TEMPORARY  VISIBILITY SEGMENT_CREATED"**
prompt ****************************************************************************************
break on table_owner on table_name on index_name on ucpt
--WITH t AS
--(SELECT /*+ materialize */DISTINCT OBJECT_OWNER, OBJECT_NAME
--          FROM (SELECT OBJECT_OWNER, OBJECT_NAME
--                  FROM V$SQL_PLAN
--                 WHERE SQL_ID = :sql_id_bind
--                   AND OBJECT_NAME IS NOT NULL
--                UNION ALL
--                SELECT OBJECT_OWNER, OBJECT_NAME
--                  FROM DBA_HIST_SQL_PLAN
--                 WHERE SQL_ID = :sql_id_bind
--                   AND OBJECT_NAME IS NOT NULL))
--SELECT A.TABLE_OWNER,
--       A.TABLE_NAME,
--       A.INDEX_NAME,
--       UNIQUENESS,
--       COLUMN_NAME,
--       COLUMN_POSITION,
--       DESCEND
--  FROM DBA_INDEXES A, DBA_IND_COLUMNS B
-- WHERE (A.OWNER, A.table_name) IN
--       (SELECT table_owner,table_name FROM dba_indexes
--         WHERE (owner,index_name) IN (SELECT * FROM t)
--        UNION ALL SELECT * FROM t)
--   AND A.OWNER = B.INDEX_OWNER
--   AND A.INDEX_NAME = B.INDEX_NAME
--   order by table_owner,table_name,index_name,COLUMN_POSITION;

               WITH t
                    AS (SELECT /*+ materialize */
                               DISTINCT OBJECT_OWNER, OBJECT_NAME
                          FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                                  FROM V$SQL_PLAN
                                 WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL
                                UNION ALL
                                SELECT OBJECT_OWNER, OBJECT_NAME
                                  FROM DBA_HIST_SQL_PLAN
                                 WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL))
                 SELECT A.TABLE_OWNER,
                        A.TABLE_NAME,
                        A.INDEX_NAME,
                           DECODE (A.UNIQUENESS,  'UNIQUE', 'U',  'NONUNIQUE', 'N',  'O')
                        || DECODE (A.COMPRESSION,  'ENABLED', 'E',  'DISABLED', 'N',  'O')
                        || DECODE (A.PARTITIONED,  'YES', 'Y',  'NO', 'N',  'O')
                        || DECODE (A.TEMPORARY,  'Y', 'Y',  'N', 'N',  'O')
                        || DECODE (A.DROPPED,  'YES', 'Y',  'NO', 'N',  'O')
&_VERSION_11            || DECODE (A.VISIBILITY,  'VISIBLE', 'V',  'INVISIBLE', 'I',  'O')
&_VERSION_11            || DECODE (A.SEGMENT_CREATED,  'YES', 'Y',  'NO', 'N',  'O')
                           ucptdvs,
                        B.COLUMN_NAME,
                        B.COLUMN_POSITION,
                        B.DESCEND
                   FROM DBA_INDEXES A, DBA_IND_COLUMNS B
                  WHERE     (A.OWNER, A.table_name) IN (SELECT table_owner, table_name
                                                          FROM dba_indexes
                                                         WHERE (owner, index_name) IN (SELECT *
                                                                                         FROM t)
                                                        UNION ALL
                                                        SELECT * FROM t)
                        AND A.OWNER = B.INDEX_OWNER
                        AND A.INDEX_NAME = B.INDEX_NAME
               ORDER BY table_owner,
                        table_name,
                        index_name,
                        COLUMN_POSITION
/
clear breaks;

prompt
prompt ****************************************************************************************
prompt PARTITION INDEX
prompt ****************************************************************************************
prompt
break on owner on name
/* Formatted on 2016/8/24 15:04:44 (QP5 v5.256.13226.35510) */
WITH t
     AS (SELECT /*+ materialize */
                DISTINCT OBJECT_OWNER, OBJECT_NAME
           FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM V$SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL
                 UNION ALL
                 SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM DBA_HIST_SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL))
  SELECT a.owner,
         a.name index_name,
         b.partitioning_type,
         b.subpartitioning_type,
         b.partition_count,
         b.def_subpartition_count,
         b.partitioning_key_count,
         b.LOCALITY,
         b.ALIGNMENT,
         a.COLUMN_NAME,
         a.COLUMN_POSITION
    FROM sys.DBA_PART_KEY_COLUMNS a, sys.dba_part_indexes b
   WHERE     a.name = b.index_name
         AND (b.owner, b.index_name) IN (SELECT owner, index_name
                                           FROM dba_indexes
                                          WHERE (table_owner, table_name) IN (SELECT table_owner,
                                                                                     table_name
                                                                                FROM dba_indexes
                                                                               WHERE (owner,
                                                                                      index_name) IN (SELECT *
                                                                                                        FROM t)
                                                                              UNION ALL
                                                                              SELECT *
                                                                                FROM t))
         AND a.owner = b.owner
ORDER BY a.owner,a.name,a.column_position
/
prompt ****************************************************************************************
prompt INDEX STATS
prompt ****************************************************************************************
col DENSITY                               heading "DENSITY"                 for 999,999,999
col owner                                 heading 'TABLE|OWNER'             for a15
col name                                  heading 'TABLE|NAME'              for a20
col COLUMN_NAME                           heading 'PARTITION|COLUMN NAME'   for a15
col COLUMN_POSITION                       heading 'COLUMN|POSITION'         for 99
col partition_name                        heading 'PARTITION|NAME'          for a20
col HIGH_VALUE                            heading 'HIGH_VALUE'              for  a15
col HIGH_VALUE_LENGTH                     heading 'HIGH_VALUE|LENGTH'       for 99
col tablespace_name                       heading 'TABLESPACE|NAME'         for a15
col num_rows                              heading 'NUM_ROWS'                for 9999999
col blocks                                heading 'BLOCKS'                  for 9999999
col EMPTY_BLOCKS for 999 heading 'EMPTY|BLOCKS'
col l_time for a19 heading 'LAST TIME|ANALYZED'
COL AVG_SPACE FOR 999999
col SUBPARTITION_COUNT for 99 heading 'SUBPARTITION|COUNT'
col compression for a11
col t_size for a10 heading 'PARTITION|SIZE_KB'
col partitioning_type for a10 heading 'PARTITION|TYPE'
col subpartitioning_type for a10 heading 'SUBPART|TYPE'
col partition_count for 99 heading 'PART|COUNT'
col def_subpartition_count for 99 heading 'SUBPART|COUNT'
col partitioning_key_count for 99 heading 'PARTITION|KEY COUNT'
BREAK ON OWNER on table_name

/* Formatted on 2016/8/24 16:01:28 (QP5 v5.256.13226.35510) */
WITH t
     AS (SELECT /*+ materialize */
                DISTINCT OBJECT_OWNER, OBJECT_NAME
           FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM V$SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL
                 UNION ALL
                 SELECT OBJECT_OWNER, OBJECT_NAME
                   FROM DBA_HIST_SQL_PLAN
                  WHERE SQL_ID = :sql_id_bind AND OBJECT_NAME IS NOT NULL))
  SELECT t.OWNER,
         t.table_name,
         t.INDEX_NAME,
         t.LOGGING,
            DECODE (b.LOCALITY,  'LOCAL', 'L',  'GLOBAL', 'G')
         || '|'
         || DECODE (b.ALIGNMENT,  'PREFIXED', 'PRE',  'NON_PREFIXED', 'NO')
            index_local,
         trim(t.BLEVEL) BLEV,
         t.LEAF_BLOCKS,
         t.DISTINCT_KEYS,
         t.NUM_ROWS,
         t.AVG_LEAF_BLOCKS_PER_KEY,
         t.AVG_DATA_BLOCKS_PER_KEY,
         t.CLUSTERING_FACTOR,
         TRIM (t.degree) degree,
         t.LAST_ANALYZED
    FROM DBA_INDEXES T, dba_part_indexes b
   WHERE     (t.TABLE_OWNER, t.TABLE_NAME) IN (SELECT table_owner, table_name
                                                 FROM dba_indexes
                                                WHERE (owner, index_name) IN (SELECT *
                                                                                FROM t)
                                               UNION ALL
                                               SELECT * FROM t)
         AND t.owner = b.owner(+)
         AND t.INDEX_NAME = b.INDEX_NAME(+)
ORDER BY 1
/
clear breaks;
prompt
prompt ****************************************************************************************
prompt PARTITION TABLE
prompt ****************************************************************************************

WITH t AS
(SELECT /*+ materialize */DISTINCT OBJECT_OWNER, OBJECT_NAME
          FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                  FROM V$SQL_PLAN
                 WHERE SQL_ID = :sql_id_bind
                   AND OBJECT_NAME IS NOT NULL
                UNION ALL
                SELECT OBJECT_OWNER, OBJECT_NAME
                  FROM DBA_HIST_SQL_PLAN
                 WHERE SQL_ID = :sql_id_bind
                   AND OBJECT_NAME IS NOT NULL))
SELECT a.owner,
       a.name,
       b.partitioning_type,
       b.subpartitioning_type,
       b.partition_count,
       b.def_subpartition_count,
       b.partitioning_key_count,
       a.COLUMN_NAME,
       a.COLUMN_POSITION
  FROM sys.DBA_PART_KEY_COLUMNS a, sys.dba_part_tables b
 WHERE a.name = b.table_name
   AND (a.owner, a.name) in (SELECT table_owner, table_name
                               FROM dba_indexes
                              WHERE (owner, index_name) IN (SELECT * FROM t)
                             UNION ALL
                             SELECT * FROM t)
   AND a.owner = b.owner
 ORDER BY a.NAME, a.COLUMN_POSITION
/

prompt
prompt ****************************************************************************************
prompt display every partition  info
prompt ****************************************************************************************
break on table_name
WITH t AS
(SELECT /*+ materialize */DISTINCT OBJECT_OWNER, OBJECT_NAME
          FROM (SELECT OBJECT_OWNER, OBJECT_NAME
                  FROM V$SQL_PLAN
                 WHERE SQL_ID = :sql_id_bind
                   AND OBJECT_NAME IS NOT NULL
                UNION ALL
                SELECT OBJECT_OWNER, OBJECT_NAME
                  FROM DBA_HIST_SQL_PLAN
                 WHERE SQL_ID = :sql_id_bind
                   AND OBJECT_NAME IS NOT NULL))
SELECT table_name ,PARTITION_NAME,
       HIGH_VALUE,
       HIGH_VALUE_LENGTH,
       TABLESPACE_NAME,
       NUM_ROWS,
       BLOCKS,
       round(blocks * 8 / 1024, 2) || 'KB' t_size,
       EMPTY_BLOCKS,
       to_char(LAST_ANALYZED, 'yyyy-mm-dd') l_time,
       AVG_SPACE,
       SUBPARTITION_COUNT,
       COMPRESSION
  FROM sys.DBA_TAB_PARTITIONS
 WHERE (table_owner, table_name) in
       (SELECT table_owner, table_name
          FROM dba_indexes
         WHERE (owner, index_name) IN (SELECT * FROM t)
        UNION ALL
        SELECT * FROM t)
 ORDER BY table_name,PARTITION_POSITION
/
clear breaks

-- Clean up bind variable
var sql_id_bind varchar2(30)
undefine sqlid;


