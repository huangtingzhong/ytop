-- File Name: awr_sql_order_by_version_counts_dbid.sql
-- Purpose: Oracle AWR SQL Order By Version Counts Dbid
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info_dbid.sql

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000

ACCEPT begin_snap prompt 'Enter Search Begin Snapshot  (i.e. 2) : '
ACCEPT end_snap prompt 'Enter Search End Snapshot  (i.e. 4) : '


variable bid  number;
variable eid  number;
variable inst_num  number;
variable top_n number;
variable dbid number;

begin
  :bid  :=  &begin_snap ;
  :eid  :=  &end_snap;
  :inst_num:=&&instance_number;
  :dbid := &&dbid;
end;
/


set lines 200
set pages 500
col  sql_ver       for 9999999999999   heading 'Version Count';
col  sql_exec          for 999999999999999   heading 'Executions';
col  sql_module        for  a30   heading 'SQL Module';
col  sql_text          for  a40   heading 'SQL Text';

/* Formatted on 2013/2/25 22:05:48 (QP5 v5.215.12089.38647) */
WITH sqt
     AS (SELECT exec,
                version_count,
                sql_id,
                module,
                rnum
           FROM (SELECT sql_id,
                        module,
                        exec,
                        version_count,
                        ROWNUM rnum
                   FROM (  SELECT sql_id,
                                  module,
                                  exec,
                                  version_count
                             FROM    (SELECT version_count, sql_id
                                        FROM dba_hist_sqlstat
                                       WHERE     snap_id = :eid
                                             AND instance_number = :inst_num
                                             and dbid = :dbid
                                             AND version_count > 1) y
                                  LEFT OUTER JOIN
                                     (  SELECT sql_id,
                                               MAX (module) module,
                                               SUM (executions_delta) exec
                                          FROM dba_hist_sqlstat
                                         WHERE     instance_number = :inst_num
                                               AND dbid = :dbid
                                               AND :bid < snap_id
                                               AND snap_id <= :eid
                                      GROUP BY sql_id) x
                                  USING (sql_id)
                         ORDER BY NVL (y.version_count, -1) DESC, sql_id))
          WHERE rnum <= 40)
  SELECT /*+ NO_MERGE(sqt) */
        sqt.version_count sql_ver,
         sqt.exec sql_exec,
         sqt.sql_id,
         DECODE (sqt.module, NULL, NULL, 'Module: ' || sqt.module) sql_module,
         NVL (DBMS_LOB.SUBSTR (st.sql_text, 40, 1),
              TO_CLOB ('** SQL Text Not Available **'))
            sql_text
    FROM sqt, dba_hist_sqltext st
   WHERE st.sql_id(+) = sqt.sql_id                  
   AND st.dbid(+) = :dbid
ORDER BY sqt.rnum
 /
 clear    breaks  
