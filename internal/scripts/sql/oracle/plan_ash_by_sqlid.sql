-- File Name: plan_ash_by_sqlid.sql
-- Purpose: Oracle Plan ASH By Sqlid
-- Created: 20150905  by  huangtingzhong

alter session set nls_date_format='yyyymmdd';
set serveroutput on size 1000000

SET VERIFY OFF
set linesize 200
set echo off
set pages 0
undefine sqlid;
select '&&sqlid' from dual;
define _SQL_MONITOR = "  "
define _VERSION_11  = "--"
define _VERSION_12  = "--"
define _VERSION_10  = "--"
define _CDB_MODE    = "--"
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

prompt ****************************************************************************************
prompt CURSOR
prompt ****************************************************************************************
--select * from table(dbms_xplan.display_cursor('&&sqlid',0,'advanced allstats last'));
select t.*
  from v$sql s,
       table(dbms_xplan.display_cursor(s.sql_id, s.child_number)) t
 where s.sql_id = '&&sqlid';

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
&_VERSION_11                        WHERE sql_id = '&&sqlid'),
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
&_VERSION_11                                          WHERE a.sql_id = '&&sqlid')
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
