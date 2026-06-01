-- File Name: awr_sql_order_by_get.sql
-- Purpose: Oracle AWR SQL Order By Get
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info.sql

set echo off
set verify off
set serveroutput on
set feedback off
set lines 300
set pages 1000


ACCEPT begin_snap prompt 'Enter Search Begin Snapshot  (i.e. 2) : '
ACCEPT end_snap prompt 'Enter Search End Snapshot  (i.e. 4) : '
ACCEPT instance_number prompt 'Enter Search Instance Number  (i.e. 1(default)) : ' default '1'

define _VERSION_11  = "--"
define _VERSION_12  = "--"
col version12  noprint new_value _VERSION_12
col version11  noprint new_value _VERSION_11
SELECT /*+ no_parallel */
      CASE
          WHEN     SUBSTR (
                      banner,
                      INSTR (banner, 'Release ') + 8,
                      INSTR (SUBSTR (banner, INSTR (banner, 'Release ') + 8),
                             ' ')) >= '10.2'
               AND SUBSTR (
                      banner,
                      INSTR (banner, 'Release ') + 8,
                      INSTR (SUBSTR (banner, INSTR (banner, 'Release ') + 8),
                             ' ')) < '12'
          THEN
             '  '
          ELSE
             '--'
       END
          version11,
       CASE
          WHEN SUBSTR (
                  banner,
                  INSTR (banner, 'Release ') + 8,
                  INSTR (SUBSTR (banner, INSTR (banner, 'Release ') + 8),
                         ' ')) >= '12.1'
          THEN
             '  '
          ELSE
             '--'
       END
          version12
  FROM v$version
 WHERE banner LIKE 'Oracle Database%';

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
col slr new_v slri
SELECT SUM (e.VALUE) - SUM (b.VALUE) slr
                   FROM dba_hist_sysstat b, dba_hist_sysstat e
                  WHERE     b.STAT_NAME IN ('session logical reads')
                        AND b.snap_id = :bid
                        AND e.snap_id = :eid
                        AND b.stat_name = e.stat_name
                        AND b.dbid = e.dbid
                        AND b.dbid = (SELECT dbid FROM v$database)
                        AND b.instance_number = e.instance_number
                        AND b.instance_number = :inst_num
                        /
set term on
variable slr number;

begin
  :slr  :=  &slri ;
end;
/

set lines 200
set pages 500
col  sql_bget          for 9999999999999   heading 'Buffer Gets';
col  sql_exec          for 999999999999   heading 'Executions';
col  sql_per_get       for 9999999999.99    heading 'Gets per Exec ';
col  sql_norm_val      for 99.99   heading '%Total';
col  sql_elap          for  99999999.99  heading 'Elapsed Time (s)';
col  sql_cpu           for  99.99  heading '%CPU';
col  sql_io            for  99.99   heading '%IO';
col  sql_id            for  a16  heading 'SQL Id';
col  sql_module        for  a24  heading 'SQL Module';
col  sql_text          for  a40   heading 'SQL Text';
col  pdb_name          for  a15   heading 'PDB_NAME'
WITH sqt
     AS (SELECT elap,
&_VERSION_12    pdb_name,
                cput,
                exec,
                uiot,
                bget,
                norm_val,
                sql_id,
                substr(module,1,20) module,
                rnum
           FROM (SELECT sql_id,
&_VERSION_12            pdb_name,
                        module,
                        elap,
                        norm_val,
                        cput,
                        exec,
                        uiot,
                        bget,
                        ROWNUM rnum
                   FROM (  SELECT sql_id,
&_VERSION_12                      c.name pdb_name,
                                  MAX (module) module,
                                  SUM (elapsed_time_delta) elap,
                                  (  100
                                   * (SUM (buffer_gets_delta) / NVL (:slr, 0)))
                                     norm_val,
                                  SUM (cpu_time_delta) cput,
                                  SUM (executions_delta) exec,
                                  SUM (iowait_delta) uiot,
                                  SUM (buffer_gets_delta) bget
                             FROM dba_hist_sqlstat d
&_VERSION_12                      ,v$containers     c
                            WHERE     instance_number = :inst_num /*AND dbid = :dbid*/
                                  AND :bid < snap_id
                                  AND snap_id <= :eid
 &_VERSION_12                     AND c.con_id(+)=d.con_id     and d.con_dbid=c.dbid (+)
                         GROUP BY sql_id
 &_VERSION_12                     ,c.name
                         ORDER BY NVL (SUM (buffer_gets_delta), -1) DESC,
                                  sql_id))
          WHERE rnum < 40 AND (rnum <= 20 OR norm_val > 0.01))
  SELECT /*+ NO_MERGE(sqt) */
        sqt.bget sql_bget,
         sqt.exec sql_exec,
         ROUND (DECODE (sqt.exec, 0, TO_NUMBER (NULL), (sqt.bget / sqt.exec)),
                2)
            sql_per_get,
         ROUND (sqt.norm_val, 2) sql_norm_val,
         ROUND (NVL ( (sqt.elap / 1000000), TO_NUMBER (NULL)), 2) sql_elap,
         ROUND (
            DECODE (
               sqt.elap,
               0, ' ',
               LPAD (
                  TO_CHAR (ROUND ( (100 * (sqt.cput / sqt.elap)), 1), 'TM9'),
                  5)),
            2)
            sql_cpu,
         ROUND (
            DECODE (
               sqt.elap,
               0, '     ',
               LPAD (
                  TO_CHAR (ROUND ( (100 * (sqt.uiot / sqt.elap)), 1), 'TM9'),
                  5)),
            2)
            sql_io,
         sqt.sql_id,
&_VERSION_12            pdb_name,
         DECODE (sqt.module, NULL, NULL, sqt.module) sql_module,
         NVL (DBMS_LOB.SUBSTR (st.sql_text, 40, 1),
              TO_CLOB ('** SQL Text Not Available **'))
            sql_text
    FROM sqt, dba_hist_sqltext st
   WHERE st.sql_id(+) = sqt.sql_id                  /*AND st.dbid(+) = :dbid*/
ORDER BY sqt.rnum
 /
 clear    breaks

