-- File Name: awr_sql_order_by_user_io_wait_time_dbid.sql
-- Purpose: Oracle AWR SQL Order By User Io Wait Time Dbid
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
set termout off
col uiowt new_v uiowti
SELECT a.VALUE - c.VALUE uiowt
  FROM (SELECT SUM (E.TIME_WAITED_MICRO) VALUE
          FROM DBA_HIST_SYSTEM_EVENT E
         WHERE     e.snap_id = :eid
               AND E.WAIT_CLASS = 'User I/O'
               AND e.instance_number = :inst_num
               and e.dbid = :dbid) a,
       (SELECT SUM (b.TIME_WAITED_MICRO) VALUE
          FROM DBA_HIST_SYSTEM_EVENT b
         WHERE     b.snap_id = :bid
               AND b.WAIT_CLASS = 'User I/O'
               AND b.instance_number = :inst_num
               and b.dbid = :dbid) c
 /
 
variable uiowt number;

begin
  :uiowt  :=  &uiowti ;
end;
/
set termount on

set lines 200
set pages 500
col  sql_uio           for 9999999.99    heading 'User I/O Time (s)';
col  sql_exec          for 999999999999   heading 'Executions';
col  sql_avg_uio     for 9999999999.99    heading 'UIO per Exec (s)';
col  sql_norm_val      for 99999999.99   heading '%Total';
col  sql_elap          for  99999999.99  heading 'Elapsed Time (s)';
col  sql_cpu           for  9999999999.99  heading '%CPU';
col  sql_iowt          for  99999999.99   heading '%IO';
col  sql_id            for   a20  heading 'SQL Id';
col  sql_module        for  a30   heading 'SQL Module';
col  sql_text          for  a40   heading 'SQL Text';
/* Formatted on 2013/2/25 18:05:50 (QP5 v5.215.12089.38647) */
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
                                   * (SUM (iowait_delta) / NULLIF (:uiowt, 0)))
                                     norm_val,
                                  SUM (cpu_time_delta) cput,
                                  SUM (executions_delta) exec,
                                  SUM (iowait_delta) uiot
                             FROM dba_hist_sqlstat
                            WHERE instance_number = :inst_num 
                                  AND dbid = :dbid
                                  AND :bid < snap_id 
                                  AND snap_id <= :eid
                         GROUP BY sql_id
                         ORDER BY NVL (SUM (iowait_delta), -1) DESC, sql_id))
          WHERE rnum < 60 AND (rnum <= 10 OR norm_val > 0.01))
  SELECT /*+ NO_MERGE(sqt) */
        round(NVL ( (sqt.uiot / 1000000), TO_NUMBER (NULL)),2) sql_uio,
         sqt.exec sql_exec  ,
         round(DECODE (sqt.exec,
                 0, TO_NUMBER (NULL),
                 (sqt.uiot / sqt.exec / 1000000)),2) sql_avg_uio,
         round(sqt.norm_val,2) sql_norm_val,
         round(NVL ( (sqt.elap / 1000000), TO_NUMBER (NULL)),2) sql_elap ,
         round(DECODE (sqt.elap, 0, TO_NUMBER (NULL), (100 * (sqt.cput / sqt.elap))),2) sql_cpu,
         round(DECODE (sqt.elap, 0, TO_NUMBER (NULL), (100 * (sqt.uiot / sqt.elap))),2) sql_io
, 
         sqt.sql_id,
         DECODE (sqt.module, NULL, NULL, 'Module: ' || sqt.module) sql_module ,
         NVL (DBMS_LOB.SUBSTR (st.sql_text, 40, 1),
              TO_CLOB ('** SQL Text Not Available **')) sql_text   
    FROM sqt, dba_hist_sqltext st
   WHERE st.sql_id(+) = sqt.sql_id                  
   AND st.dbid(+) = :dbid
ORDER BY sqt.rnum
 /
 clear    breaks  