-- File Name: awr_sql_stat_diff.sql
-- Purpose: Oracle AWR SQL stats Diff
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 2000 pages 500 verify off heading on 
col snap_id for 999999
col sql_id for  a13
col parsing_schema_name for a15              heading 'PARSE|SCHEMA_NAME'
col elapsed             for 99999999         heading 'Elapsed Time';
col diff_elapsed        for 999999           heading 'Diff|Elapsed Time';
col cpu                 for 99999999         heading 'Cpu Time';
col diff_cpu            for 999999           heading 'Diff|Cpu Time';
col buffer              for 999999999999     heading 'Buffer Get';
col diff_buffer         for 99999999         heading 'Diff|Buffer Get';
col disk                for 99999999         heading 'Physical Read';
col diff_disk           for 99999999         heading 'Diff|Phy Read';
col direct              for 99999999         heading 'Direct Read';
col diff_direct         for 9999999          heading 'Diff|Direct Read';
col rr                  for 99999999         heading 'Row Process';
col diff_rr             for 9999999          heading 'Diff|Row Pro';
col fetches             for 99999999         heading 'Fecthes';
col diff_fetches        for 9999999          heading 'Diff|Fecthes';
undefine sqlid     
undefine column_name

/* Formatted on 2014/8/9 16:48:06 (QP5 v5.240.12305.39446) */
  SELECT *
    FROM (SELECT snap_id,
                 sql_id,
                 parsing_schema_name,
                 elapsed,
                 (elapsed - elapsed1) diff_elapsed,
                 cpu,
                 cpu - cpu1 diff_cpu,
                 buffer,
                 buffer - buffer1 diff_buffer,
                 disk,
                 disk - disk1 diff_disk,
                 direct,
                 direct - direct1 diff_direct,
                 rr,
                 rr - rr1 diff_rr,
                 fetches,
                 fetches - fetches1 diff_fetches
            FROM (SELECT snap_id,
                         sql_id,
                         parsing_schema_name,
                         elapsed,
                         LAG (
                            elapsed,
                            1,
                            0)
                         OVER (PARTITION BY sql_id, parsing_schema_name
                               ORDER BY snap_id)
                            elapsed1,
                         cpu,
                         LAG (
                            cpu,
                            1,
                            0)
                         OVER (PARTITION BY sql_id, parsing_schema_name
                               ORDER BY snap_id)
                            cpu1,
                         buffer,
                         LAG (
                            buffer,
                            1,
                            0)
                         OVER (PARTITION BY sql_id, parsing_schema_name
                               ORDER BY snap_id)
                            buffer1,
                         disk,
                         LAG (
                            disk,
                            1,
                            0)
                         OVER (PARTITION BY sql_id, parsing_schema_name
                               ORDER BY snap_id)
                            disk1,
                         direct,
                         LAG (
                            direct,
                            1,
                            0)
                         OVER (PARTITION BY sql_id, parsing_schema_name
                               ORDER BY snap_id)
                            direct1,
                         rr,
                         LAG (
                            rr,
                            1,
                            0)
                         OVER (PARTITION BY sql_id, parsing_schema_name
                               ORDER BY snap_id)
                            rr1,
                         fetches,
                         LAG (
                            fetches,
                            1,
                            0)
                         OVER (PARTITION BY sql_id, parsing_schema_name
                               ORDER BY snap_id)
                            fetches1
                    FROM (  SELECT snap_id,
                                   sql_id,
                                   parsing_schema_name,
                                   TRUNC (
                                        (SUM (elapsed_time_delta))
                                      / DECODE ( (SUM (executions_delta)),
                                                0, 1,
                                                (SUM (executions_delta))))
                                      elapsed,
                                   TRUNC (
                                        (SUM (cpu_time_delta))
                                      / DECODE ( (SUM (executions_delta)),
                                                0, 1,
                                                (SUM (executions_delta))))
                                      cpu,
                                   TRUNC (
                                        (SUM (buffer_gets_delta))
                                      / DECODE ( (SUM (executions_delta)),
                                                0, 1,
                                                (SUM (executions_delta))))
                                      buffer,
                                   TRUNC (
                                        (SUM (disk_reads_delta))
                                      / DECODE ( (SUM (executions_delta)),
                                                0, 1,
                                                (SUM (executions_delta))))
                                      disk,
                                   TRUNC (
                                        (SUM (direct_writes_delta))
                                      / DECODE ( (SUM (executions_delta)),
                                                0, 1,
                                                (SUM (executions_delta))))
                                      direct,
                                   TRUNC (
                                        (SUM (rows_processed_delta))
                                      / DECODE ( (SUM (executions_delta)),
                                                0, 1,
                                                (SUM (executions_delta))))
                                      rr,
                                   TRUNC (
                                        (SUM (fetches_delta))
                                      / DECODE ( (SUM (executions_delta)),
                                                0, 1,
                                                (SUM (executions_delta))))
                                      fetches
                              FROM dba_hist_sqlstat a
                             WHERE a.sql_id = NVL ('&sqlid', a.sql_id)
                          GROUP BY snap_id, sql_id, parsing_schema_name))
           WHERE cpu1 <> 0)
   WHERE &diff_buffer > NVL ('&number', 100)
ORDER BY sql_id, parsing_schema_name, snap_id
/
undefine sqlid;
undefine column_name;