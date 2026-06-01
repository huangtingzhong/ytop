-- File Name: awr_sql_order_by_elapsed_time_by_dbid.sql
-- Purpose: Oracle AWR SQL Order By Elapsed Time By Dbid
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info_by_dbid.sql

set echo off
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
col dbtime new_v dbtimei
SELECT e.VALUE - b.VALUE dbtime
  FROM dba_hist_sys_time_model b, dba_hist_sys_time_model e
 WHERE     b.stat_name = 'DB time'
       AND e.stat_name = 'DB time'
       AND B.snap_id = :bid
       AND e.instance_number = b.instance_number
       AND e.instance_number = :inst_num
       AND e.snap_id = :eid
       AND b.dbid = :dbid
       and b.dbid= e.dbid
       AND e.instance_number = b.instance_number
       AND e.instance_number = :inst_num
 /
 
variable dbtime number;

begin
  :dbtime  :=  &dbtimei ;
end;
/


set lines 200
set pages 500
col  sql_elap          for 999.99    heading 'Elapsed Time (s)';
col  sql_exec          for 999999999999   heading '	Executions ';
col  sql_avg_exec      for 9999999999.99    heading 'Elapsed Time per Exec (s)';
col  sql_norm_val      for  9999.99   heading '%Total';
col  sql_elap          for   999.99  heading '%CPU';
col  sql_iowt          for  9999.99   heading '	%IO';
col  sql_id            for   a20  heading 'SQL Id';
col  sql_module        for  a30   heading 'SQL Module';
col  sql_text          for  a60   heading 'SQL Text';
WITH sqt
     AS (SELECT elap,
                cput,
                exec,
                iowt,
                norm_val,
                sql_id,
                module,
                rnum
           FROM (SELECT sql_id,
                        module,
                        elap,
                        norm_val,
                        cput,
                        exec,
                        iowt,
                        ROWNUM rnum
                   FROM (  SELECT sql_id,
                                  MAX (module) module,
                                  SUM (elapsed_time_delta) elap,
                                  (  100
                                   * (  SUM (elapsed_time_delta)
                                      / NVL (:dbtime, 0)))
                                     norm_val,
                                  SUM (cpu_time_delta) cput,
                                  SUM (executions_delta) exec,
                                  SUM (iowait_delta) iowt
                             FROM dba_hist_sqlstat
                            WHERE     instance_number = :inst_num /*AND  dbid = :dbid*/
                                  AND :bid < snap_id
                                  AND snap_id <= :eid
                                  AND dbid = :dbid          
                         GROUP BY sql_id
                         ORDER BY NVL (SUM (elapsed_time_delta), -1) DESC,
                                  sql_id))
          WHERE rnum < 60 AND (rnum <= 10 OR norm_val > 1.0))
  SELECT /*+ NO_MERGE(sqt) */
        ROUND (NVL ( (sqt.elap / 1000000), TO_NUMBER (NULL)), 2) sql_elap,
         sqt.exec sql_exec ,
         ROUND (
            DECODE (sqt.exec,
                    0, TO_NUMBER (NULL),
                    (sqt.elap / sqt.exec / 1000000)),
            2) sql_avg_exec,
         ROUND (sqt.norm_val, 2) sql_norm_val,
         ROUND (
            DECODE (sqt.elap,
                    0, TO_NUMBER (NULL),
                    (100 * (sqt.cput / sqt.elap))),
            2) sql_elap,
         ROUND (
            DECODE (sqt.elap,
                    0, TO_NUMBER (NULL),
                    (100 * (sqt.iowt / sqt.elap))),
            2) sql_iowt,
         sqt.sql_id,
         DECODE (sqt.module, NULL, NULL, 'Module: ' || sqt.module) sql_module,
         NVL (DBMS_LOB.SUBSTR (st.sql_text, 60, 1),
              TO_CLOB ('** SQL Text Not Available **')) sql_text
    FROM sqt, dba_hist_sqltext st
   WHERE st.sql_id(+) = sqt.sql_id     
   AND st.dbid = :dbid
ORDER BY sqt.rnum
 /
 clear    breaks  
