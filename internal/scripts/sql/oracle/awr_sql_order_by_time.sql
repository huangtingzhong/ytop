-- File Name: awr_sql_order_by_time.sql
-- Purpose: Oracle AWR SQL Order By Time
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info.sql

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
set term on
col dbtime new_v dbtimei
SELECT e.VALUE - b.VALUE dbtime
  FROM dba_hist_sys_time_model b, dba_hist_sys_time_model e
 WHERE     b.stat_name = 'DB time'
       AND e.stat_name = 'DB time'
       AND B.snap_id = :bid
       AND e.instance_number = b.instance_number
       AND e.instance_number = :inst_num
       AND e.snap_id = :eid
       AND e.instance_number = b.instance_number
       AND e.instance_number = :inst_num
 /
set term off
variable tcpu number;

begin
  :tcpu  :=  &dbtimei ;
end;
/


set lines 200
set pages 500
col  sql_cpu1          for 999.99    heading 'CPU Time (s)';
col  sql_exec          for 999999999999   heading '	Executions ';
col  sql_avg_exec      for 9999999999.99    heading 'CPU per Exec (s)';
col  sql_norm_val      for 99999999.99   heading '%Total';
col  sql_elap          for  99999999.99  heading 'Elapsed Time (s)';
col  sql_cpu           for  9999999999.99  heading '%CPU';
col  sql_iowt          for  99999999.99   heading '	%IO';
col  sql_id            for   a20  heading 'SQL Id';
col  sql_module        for  a30   heading 'SQL Module';
col  sql_text          for  a40   heading 'SQL Text';
WITH sqt
     AS (SELECT elap,
                cput,
                exec,
                uiot,
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
                        uiot,
                        ROWNUM rnum
                   FROM (  SELECT sql_id,
                                  MAX (module) module,
                                  SUM (elapsed_time_delta) elap,
                                  (  100
                                   * (SUM (cpu_time_delta) / nvl (:tcpu, 0)))
                                     norm_val,
                                  SUM (cpu_time_delta) cput,
                                  SUM (executions_delta) exec,
                                  SUM (iowait_delta) uiot
                             FROM dba_hist_sqlstat
                            WHERE     instance_number = :inst_num
                                  /*AND dbid = :dbid*/
                                  AND :bid < snap_id
                                  AND snap_id <= :eid
                         GROUP BY sql_id
                         ORDER BY NVL (SUM (cpu_time_delta), -1) DESC, sql_id))
          WHERE rnum < 60 AND (rnum <= 10 OR norm_val > 0.01))
  SELECT /*+ NO_MERGE(sqt) */
        round(NVL ( (sqt.cput / 1000000), TO_NUMBER (NULL)),2) sql_cpu1 ,
         sqt.exec sql_exec ,
         round(DECODE (sqt.exec,
                 0, TO_NUMBER (NULL),
                 (sqt.cput / sqt.exec / 1000000)),2) sql_avg_exec,
         round(sqt.norm_val,2) sql_norm_val,
         round(NVL ( (sqt.elap / 1000000), TO_NUMBER (NULL)),2) sql_elap,
         round(DECODE (sqt.elap, 0, TO_NUMBER (NULL), (100 * (sqt.cput / sqt.elap))),2) sql_cpu,
         round(DECODE (sqt.elap, 0, TO_NUMBER (NULL), (100 * (sqt.uiot / sqt.elap))),2) sql_iowt,
         sqt.sql_id sql_id,
         DECODE (sqt.module, NULL, NULL, 'Module: ' || sqt.module) sql_module ,
         NVL (DBMS_LOB.SUBSTR (st.sql_text, 40, 1),
              TO_CLOB ('** SQL Text Not Available **')) sql_text       
    FROM sqt, dba_hist_sqltext st
   WHERE st.sql_id(+) = sqt.sql_id/* AND st.dbid(+) = :dbid*/
ORDER BY sqt.rnum
 /
 clear    breaks  

