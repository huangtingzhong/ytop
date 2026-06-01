-- File Name: awr_redo.sql
-- Purpose: Oracle AWR Redo
-- Created: 20260516  by  huangtingzhong

/* Formatted on 2014/8/9 14:55:35 (QP5 v5.240.12305.39446) */
SET ECHO OFF
SET PAGESIZE 50000 LINESIZE 300 HEADING ON

COL instance_number             FORMAT 99                  heading 'I'
COL tim                                                    heading 'Period end' 
COL cpu_sec                     FORMAT 999999999          heading 'Cpu used|Sec'
COL phy_reads                   FORMAT 999999999         heading 'Physical|reads' 
COL phy_writes                  FORMAT 999999999         HEAD 'Physical|writes'                   
COL cr_served                   FORMAT 999999999          HEAD 'CR blocks|served'                 
COL current_served              FORMAT 999999999          HEAD 'CUR blocks|served'                
COL redo_mb                     FORMAT 999999999          HEAD 'Redo, MB'                         
COL processes                   FORMAT 999999             HEAD 'Proc|esses'                        
COL avg_df_seq                  FORMAT 99999              HEAD 'Avg 1|read'                       
COL avg_df_scat                 FORMAT 99999              HEAD 'Avg N|read'                       
COL redo_diff_to_md_pct         FORMAT 999999             HEAD 'Redo Diff|to median, %'            
COL avg_lfpw                    FORMAT 999.99             HEAD 'Avg|LFPW'                           
COL avg_log_sync                FORMAT 9999.99            HEAD 'Avg Log|Sync, ms'                  
COL log_ckpt_sec                FORMAT 999999             HEAD 'CKPT|waits, s'                     
COL redo_needed                 FORMAT 999999             HEAD 'Redo to|Add, MB'  
COL is_restart                  FORMAT a5                 HEAD 'Rstart'                 

COMPUTE MAX OF cpu_sec          ON instance_number
COMPUTE MAX OF phy_reads        ON instance_number
COMPUTE MAX OF phy_writes       ON instance_number
COMPUTE MAX OF cr_served        ON instance_number
COMPUTE MAX OF current_served   ON instance_number
COMPUTE MAX OF phy_writes       ON instance_number
COMPUTE MAX OF redo_needed      ON instance_number
COMPUTE MAX OF log_ckpt_sec     ON instance_number
COMPUTE MAX OF avg_log_sync     ON instance_number
COMPUTE MAX OF avg_lfpw         ON instance_number
COMPUTE MAX OF redo_mb          ON instance_number
COMPUTE MAX OF processes        ON instance_number
COMPUTE MAX OF avg_df_seq       ON instance_number
COMPUTE MAX OF avg_df_scat      ON instance_number

BREAK ON instance_number SKIP PAGE

WITH t_interval AS (SELECT /*+ inline */
                          SYSDATE - 30 begin, SYSDATE AS end FROM DUAL)
  SELECT 
         stats.instance_number instance_number,
         TO_CHAR (stats.begin_interval_time, 'YYYYMMDD HH24MI') tim,
         stats.cpu_used / 100 cpu_sec,
         stats.phy_reads phy_reads,
         stats.phy_writes phy_writes,
         stats.cr_served cr_served,
         stats.current_served current_served,
         stats.redo_size / 1024 / 1024 redo_mb,
         procs.current_utilization processes,
         --
         waits.df_seq_micro / 1000 / NULLIF (waits.df_seq_waits, 0) avg_df_seq,
         waits.df_scat_micro / 1000 / NULLIF (waits.df_scat_waits, 0)
            avg_df_scat,
         (stats.redo_size - stats.md_redo_size) * 100 / stats.md_redo_size
            redo_diff_to_md_pct,
         stats.redo_write_time * 10 / stats.redo_writes avg_lfpw,
         waits.log_sync_micro / NULLIF (waits.log_sync_waits, 0) / 1000
            avg_log_sync,
         waits.log_ckpt_micro / 1e6 log_ckpt_sec,
           (stats.redo_size / (waits.snap_interval * 86400))
         * (waits.log_ckpt_micro / 1e6)
         / 1024
         / 1024
            redo_needed,
         stats.is_restart
    FROM (SELECT snap_id,
                 begin_interval_time,
                 snap_interval,
                 instance_number,
                 dbid,
                 log_sync_micro,
                 log_sync_waits,
                 log_ckpt_micro,
                 log_ckpt_waits,
                 df_seq_micro,
                 df_seq_waits,
                 df_scat_micro,
                 df_scat_waits,
                 direct_micro,
                 direct_waits,
                 MEDIAN (log_sync_micro / NULLIF (log_sync_waits, 0))
                    OVER (PARTITION BY dbid, instance_number)
                    md_log_sync_micro
            FROM (  SELECT snap_id,
                           begin_interval_time,
                           instance_number,
                           dbid,
                           MAX (snap_interval) snap_interval,
                           MAX (DECODE (event_name, 'log file sync', wait_micro))
                              log_sync_micro,
                           MAX (
                              DECODE (event_name, 'log file sync', total_waits))
                              log_sync_waits,
                           MAX (
                              DECODE (
                                 event_name,
                                 'log file switch (checkpoint incomplete)', wait_micro))
                              log_ckpt_micro,
                           MAX (
                              DECODE (
                                 event_name,
                                 'log file switch (checkpoint incomplete)', total_waits))
                              log_ckpt_waits,
                           MAX (
                              DECODE (event_name,
                                      'db file sequential read', wait_micro))
                              df_seq_micro,
                           MAX (
                              DECODE (event_name,
                                      'db file sequential read', total_waits))
                              df_seq_waits,
                           MAX (
                              DECODE (event_name,
                                      'db file scattered read', wait_micro))
                              df_scat_micro,
                           MAX (
                              DECODE (event_name,
                                      'db file scattered read', total_waits))
                              df_scat_waits,
                           MAX (
                              DECODE (event_name, 'direct path read', wait_micro))
                              direct_micro,
                           MAX (
                              DECODE (event_name,
                                      'direct path read', total_waits))
                              direct_waits
                      FROM (SELECT e.snap_id,
                                   e.instance_number,
                                   e.dbid,
                                   sn.begin_interval_time,
                                     CAST (begin_interval_time AS DATE)
                                   - CAST (
                                        LAG (
                                           begin_interval_time)
                                        OVER (
                                           PARTITION BY e.dbid,
                                                        e.instance_number,
                                                        e.event_name
                                           ORDER BY sn.begin_interval_time) AS DATE)
                                      snap_interval,
                                   sn.startup_time,
                                   e.event_name,
                                   CASE
                                      WHEN (    sn.begin_interval_time >=
                                                   sn.startup_time
                                            AND LAG (
                                                   sn.begin_interval_time)
                                                OVER (
                                                   PARTITION BY e.dbid,
                                                                e.instance_number,
                                                                e.event_name
                                                   ORDER BY
                                                      sn.begin_interval_time) <
                                                   sn.startup_time)
                                      THEN
                                         e.time_waited_micro
                                      ELSE
                                           e.time_waited_micro
                                         - LAG (
                                              e.time_waited_micro)
                                           OVER (
                                              PARTITION BY e.dbid,
                                                           e.instance_number,
                                                           e.event_name
                                              ORDER BY sn.begin_interval_time)
                                   END
                                      wait_micro,
                                   CASE
                                      WHEN (    sn.begin_interval_time >=
                                                   sn.startup_time
                                            AND LAG (
                                                   sn.begin_interval_time)
                                                OVER (
                                                   PARTITION BY e.dbid,
                                                                e.instance_number,
                                                                e.event_name
                                                   ORDER BY
                                                      sn.begin_interval_time) <
                                                   sn.startup_time)
                                      THEN
                                         e.total_waits
                                      ELSE
                                           e.total_waits
                                         - LAG (
                                              e.total_waits)
                                           OVER (
                                              PARTITION BY e.dbid,
                                                           e.instance_number,
                                                           e.event_name
                                              ORDER BY sn.begin_interval_time)
                                   END
                                      total_waits
                              FROM dba_hist_system_event e,
                                   dba_hist_snapshot sn,
                                   t_interval t
                             WHERE     sn.snap_id = e.snap_id
                                   AND sn.dbid = e.dbid
                                   AND sn.instance_number = e.instance_number
                                   AND sn.begin_interval_time BETWEEN t.begin
                                                                  AND t.end
                                   AND e.event_name IN
                                          ('log file sync',
                                           'log file switch (checkpoint incomplete)',
                                           'db file sequential read',
                                           'db file scattered read',
                                           'direct path read'))
                  GROUP BY dbid,
                           instance_number,
                           begin_interval_time,
                           snap_id)) waits,
         (SELECT snap_id,
                 begin_interval_time,
                 instance_number,
                 dbid,
                 redo_size,
                 redo_write_time,
                 redo_writes,
                 is_restart,
                 cpu_used,
                 phy_reads,
                 phy_reads_cache,
                 phy_writes,
                 phy_writes_cache,
                 cr_served,
                 current_served,
                 MEDIAN (redo_size) OVER (PARTITION BY dbid, instance_number)
                    md_redo_size
            FROM (  SELECT snap_id,
                           begin_interval_time,
                           instance_number,
                           dbid,
                           MAX (is_restart) is_restart,
                           MAX (DECODE (stat_name, 'redo size', stat_diff))
                              redo_size,
                           MAX (DECODE (stat_name, 'redo write time', stat_diff))
                              redo_write_time,
                           MAX (DECODE (stat_name, 'redo writes', stat_diff))
                              redo_writes,
                           MAX (
                              DECODE (stat_name,
                                      'CPU used by this session', stat_diff))
                              cpu_used,
                           MAX (
                              DECODE (
                                 stat_name,
                                 'physical read total IO requests', stat_diff))
                              phy_reads,
                           MAX (
                              DECODE (stat_name,
                                      'physical reads cache', stat_diff))
                              phy_reads_cache,
                           MAX (
                              DECODE (
                                 stat_name,
                                 'physical write total IO requests', stat_diff))
                              phy_writes,
                           MAX (
                              DECODE (stat_name,
                                      'physical writes from cache', stat_diff))
                              phy_writes_cache,
                           MAX (
                              DECODE (stat_name,
                                      'gc cr blocks served', stat_diff))
                              cr_served,
                           MAX (
                              DECODE (stat_name,
                                      'gc current blocks served', stat_diff))
                              current_served
                      FROM (SELECT stats.snap_id,
                                   stats.instance_number,
                                   stats.dbid,
                                   sn.begin_interval_time,
                                   sn.startup_time,
                                   stats.stat_name,
                                   CASE
                                      WHEN (    sn.begin_interval_time >=
                                                   sn.startup_time
                                            AND LAG (
                                                   sn.begin_interval_time)
                                                OVER (
                                                   PARTITION BY stats.dbid,
                                                                stats.instance_number,
                                                                stats.stat_id
                                                   ORDER BY
                                                      sn.begin_interval_time) <
                                                   sn.startup_time)
                                      THEN
                                         stats.VALUE
                                      ELSE
                                           stats.VALUE
                                         - LAG (
                                              stats.VALUE)
                                           OVER (
                                              PARTITION BY stats.dbid,
                                                           stats.instance_number,
                                                           stats.stat_id
                                              ORDER BY stats.snap_id)
                                   END
                                      stat_diff,
                                   CASE
                                      WHEN (    sn.begin_interval_time >=
                                                   sn.startup_time
                                            AND LAG (
                                                   sn.begin_interval_time)
                                                OVER (
                                                   PARTITION BY stats.dbid,
                                                                stats.instance_number,
                                                                stats.stat_id
                                                   ORDER BY
                                                      sn.begin_interval_time) <
                                                   sn.startup_time)
                                      THEN
                                         'Yes'
                                   END
                                      is_restart
                              FROM dba_hist_sysstat stats,
                                   dba_hist_snapshot sn,
                                   t_interval t
                             WHERE     sn.snap_id = stats.snap_id
                                   AND sn.dbid = stats.dbid
                                   AND sn.instance_number = stats.instance_number
                                   AND sn.begin_interval_time BETWEEN t.begin
                                                                  AND t.end
                                   AND stats.stat_name IN
                                          ('redo size',
                                           'redo write time',
                                           'redo writes',
                                           'CPU used by this session',
                                           'physical read total IO requests',
                                           'physical reads cache',
                                           'physical write total IO requests',
                                           'physical writes from cache',
                                           'gc cr blocks served',
                                           'gc current blocks served'))
                  GROUP BY dbid,
                           instance_number,
                           begin_interval_time,
                           snap_id)) stats,
         (SELECT stats.snap_id,
                 stats.instance_number,
                 stats.dbid,
                 stats.resource_name,
                 stats.current_utilization
            FROM dba_hist_resource_limit stats,
                 dba_hist_snapshot sn,
                 t_interval t
           WHERE     sn.snap_id = stats.snap_id
                 AND sn.dbid = stats.dbid
                 AND sn.instance_number = stats.instance_number
                 AND sn.begin_interval_time BETWEEN t.begin AND t.end
                 AND stats.resource_name = 'processes') procs
   WHERE     waits.dbid = stats.dbid
         AND waits.instance_number = stats.instance_number
         AND waits.snap_id = stats.snap_id
         AND waits.dbid = procs.dbid
         AND waits.instance_number = procs.instance_number
         AND waits.snap_id = procs.snap_id
ORDER BY stats.dbid, stats.instance_number, stats.begin_interval_time;
