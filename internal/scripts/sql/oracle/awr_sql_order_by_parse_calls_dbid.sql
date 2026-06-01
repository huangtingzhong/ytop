-- File Name: awr_sql_order_by_parse_calls_dbid.sql
-- Purpose: Oracle AWR SQL Order By Parse Calls Dbid
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

set term off
col  prse new_v prsei
SELECT SUM (e.VALUE) - SUM (b.VALUE) prse
                   FROM dba_hist_sysstat b, dba_hist_sysstat e
                  WHERE     b.STAT_NAME IN ('parse count (total)')
                        AND b.snap_id = :bid
                        AND e.snap_id = :eid
                        AND b.stat_name = e.stat_name
                        AND b.dbid = e.dbid
                        AND b.instance_number = e.instance_number
                        AND b.instance_number = :inst_num
                        and b.dbid = e.dbid
                        and b.dbid = :dbid
                        /
set term on 
variable prse number;

begin
  :prse  :=  &prsei;
end;
/

set lines 200
set pages 500
col  sql_prsc         for 9999999999999   heading 'Parse Calls';
col  sql_exec          for 999999999999999   heading 'Executions';
col  sql_norm_val      for 99999999.99   heading '% Total Parses';
col  sql_module        for  a30   heading 'SQL Module';
col  sql_text          for  a40   heading 'SQL Text';
/* Formatted on 2013/2/25 19:57:34 (QP5 v5.215.12089.38647) */
/* Formatted on 2013/2/25 21:01:33 (QP5 v5.215.12089.38647) */
/* Formatted on 2013/2/25 21:16:59 (QP5 v5.215.12089.38647) */
WITH sqt
     AS (SELECT exec,
                prsc,
                norm_val,
                sql_id,
                module,
                rnum
           FROM (SELECT sql_id,
                        module,
                        norm_val,
                        exec,
                        prsc,
                        ROWNUM rnum
                   FROM (  SELECT sql_id,
                                  MAX (module) module,
                                  (  100
                                   * (  SUM (parse_calls_delta)
                                      / NULLIF (:prse, 0)))
                                     norm_val,
                                  SUM (executions_delta) exec,
                                  SUM (parse_calls_delta) prsc
                             FROM dba_hist_sqlstat
                            WHERE instance_number = :inst_num AND dbid = :dbid
                                  AND :bid < snap_id AND snap_id <= :eid
                         GROUP BY sql_id
                         ORDER BY NVL (SUM (parse_calls_delta), -1) DESC,
                                  sql_id))
          WHERE rnum < 40 AND (rnum <= 20 OR norm_val > 0.01))
  SELECT /*+ NO_MERGE(sqt) */
        sqt.prsc sql_prsc,
         sqt.exec sql_exec ,
         sqt.norm_val sql_norm_val,
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