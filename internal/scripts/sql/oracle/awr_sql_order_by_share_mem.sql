-- File Name: awr_sql_order_by_share_mem.sql
-- Purpose: Oracle AWR SQL Order By Share Mem
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info.sql

set echo off
store set sqlplusset replace
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000

ACCEPT begin_snap prompt 'Enter Search Begin Snapshot  (i.e. 2) : '
ACCEPT end_snap prompt 'Enter Search End Snapshot  (i.e. 4) : '
ACCEPT instance_number prompt 'Enter Search Instance Number  (i.e. 1(default)) : ' default '1'

variable bid  number;
variable eid  number;
variable inst_num  number;
variable top_n number;

begin
  :bid  :=  &begin_snap ;
  :eid  :=  &end_snap;
  :inst_num:=&instance_number;
end;
/

set term off
col  espm new_v espmi
SELECT p.VALUE espm
  FROM dba_hist_parameter p
 WHERE     p.parameter_name = '__shared_pool_size'
       AND ROWNUM = 1
       AND p.instance_number = :inst_num
       AND p.snap_id = :eid
                        /
set term on 
variable espm number;

begin
  :espm  :=  &espmi;
end;
/

set lines 200
set pages 500
col  sql_mem        for 9999999999999   heading 'Sharable Mem (b)';
col  sql_exec          for 999999999999999   heading 'Executions';
col  sql_per_mem      for 99999999.99   heading '% Total Parses';
col  sql_module        for  a30   heading 'SQL Module';
col  sql_text          for  a40   heading 'SQL Text';

WITH sqt
     AS (SELECT exec,
                sharable_mem,
                sql_id,
                module,
                rnum
           FROM (SELECT sql_id,
                        module,
                        exec,
                        sharable_mem,
                        ROWNUM rnum
                   FROM (  SELECT sql_id,
                                  module,
                                  exec,
                                  sharable_mem
                             FROM    (SELECT sharable_mem, sql_id
                                        FROM dba_hist_sqlstat
                                       WHERE     snap_id = :eid 
                                            /* AND dbid = :dbid*/
                                             AND instance_number = :inst_num
                                             AND sharable_mem > 1048576) y
                                  LEFT OUTER JOIN
                                     (  SELECT sql_id,
                                               MAX (module) module,
                                               SUM (executions_delta) exec
                                          FROM dba_hist_sqlstat
                                         WHERE     instance_number = :inst_num
                                               /*AND dbid = :dbid*/
                                               AND :bid < snap_id
                                               AND snap_id <= :eid
                                      GROUP BY sql_id) x
                                  USING (sql_id)
                         ORDER BY NVL (sharable_mem, -1) DESC, sql_id))
          WHERE rnum <= 40)
  SELECT /*+ NO_MERGE(sqt) */
        sqt.sharable_mem sql_mem,
         sqt.exec sql_exec ,
         DECODE (:espm, 0, 0, 100 * sqt.sharable_mem / :espm) sql_avg_mem,
         sqt.sql_id,
         DECODE (sqt.module, NULL, NULL, 'Module: ' || sqt.module) sql_module,
         NVL (DBMS_LOB.SUBSTR (st.sql_text, 40, 1),
              TO_CLOB ('** SQL Text Not Available **'))
            sql_text
    FROM sqt, dba_hist_sqltext st
   WHERE st.sql_id(+) = sqt.sql_id                  /*AND st.dbid(+) = :dbid*/
ORDER BY sqt.rnum
 /
 clear    breaks  
@sqlplusset
