-- File Name: awr3.sql
-- Purpose: Oracle Awr3
-- Created: 20260516  by  huangtingzhong

set lines 300 heading on pages 1000
col end_time for a15
col AAS for 9999
col CPU_AAS for 9999 heading 'CPU|AAS'
col REDO_KB         for 999999
col LOG_READ_MB     for 99999    heading 'LOG_R_MB'
col BLK_CHANGE_MB   for 99999    heading 'BLK_C_MB'
col PHY_READ_MB     for 99999    heading 'PHY_R_MB'
col PHY_WRT_MB      for 99999    heading 'PHY_W_MB'
col ICONN_KB        for 999999   heading 'ICON_KB'
col PARSE           for 999999   heading 'PARSE'
col TRANS           for 99999    heading 'TRANS'
col EXECNT          for 9999999
col IOPS_R          for 999999
col IOPS_W          for 999999
col IOPS            for 9999999
col LOGON           for 9999
col UCALL           for 9999999
col SORTS           for 99999

SELECT end_time,
       ROUND(SUM(DECODE(NAME, 'DB time', PER_SECOND, 0)) / 1000000) AAS,
       ROUND(SUM(DECODE(NAME, 'DB CPU', PER_SECOND, 0)) / 1000000) CPU_AAS,
       ROUND(SUM(DECODE(NAME, 'redo size', PER_SECOND, 0)) / 1024) REDO_KB,
       ROUND(SUM(DECODE(NAME, 'logons cumulative', PER_SECOND, 0))) LOGON,
       ROUND(SUM(DECODE(NAME, 'logical reads', PER_SECOND, 0)) * 8 / 1024) LOG_READ_MB,
       ROUND(SUM(DECODE(NAME, 'db block changes', PER_SECOND, 0)) * 8 / 1024) BLK_CHANGE_MB,
       ROUND(SUM(DECODE(NAME, 'physical reads', PER_SECOND, 0)) * 8 / 1024) PHY_READ_MB,
       ROUND(SUM(DECODE(NAME, 'physical writes', PER_SECOND, 0)) * 8 / 1024) PHY_WRT_MB,
       ROUND(SUM(DECODE(NAME, 'parse count (total)', PER_SECOND, 0))) PARSE,
       ROUND(SUM(DECODE(NAME, 'user calls', PER_SECOND, 0))) UCALL,
       ROUND(SUM(DECODE(NAME, 'execute count', PER_SECOND, 0))) EXECNT,
       ROUND(SUM(DECODE(NAME, 'sorts', PER_SECOND, 0))) SORTS,
       ROUND(SUM(DECODE(NAME, 'transactions', PER_SECOND, 0))) TRANS,
       ROUND(SUM(DECODE(NAME,
                        'physical write total IO requests',
                        per_second,
                        0))) IOPS_W,
       ROUND(SUM(DECODE(NAME,
                        'physical read total IO requests',
                        per_second,
                        0))) IOPS_R,
       ROUND(SUM(DECODE(NAME,
                        'physical write total IO requests',
                        per_second,
                        0))) +ROUND(SUM(DECODE(NAME,
                        'physical read total IO requests',
                        per_second,
                        0)))  IOPS
  FROM (SELECT a.instance_number,
               end_interval_time end_time,
               b.stat_name name,
               (b.VALUE - LAG(b.VALUE)
                OVER(PARTITION BY a.startup_time,
                     b.stat_name,
                     a.instance_number ORDER BY a.snap_id)) / elapsed_time per_second
          FROM (SELECT s.snap_id snap_id,
                       s.instance_number,
                       TO_CHAR(s.end_interval_time, 'yyyymmdd hh24:mi') end_interval_time,
                       startup_time,
                       (TO_DATE(TO_CHAR(s.end_interval_time,
                                        'yyyy-mm-dd hh24:mi:ss'),
                                'yyyy-mm-dd hh24:mi:ss') -
                       TO_DATE(TO_CHAR(s.begin_interval_time,
                                        'yyyy-mm-dd hh24:mi:ss'),
                                'yyyy-mm-dd hh24:mi:ss')) * 24 * 60 * 60 elapsed_time
                  FROM dba_hist_snapshot s) a,
               (SELECT snap_id, instance_number, stat_name, SUM(VALUE) VALUE
                  FROM ((SELECT snap_id,
                                instance_number,
                                DECODE(STAT_NAME,
                                       'user commits',
                                       'transactions',
                                       'user rollbacks',
                                       'transactions',
                                       'consistent gets',
                                       'logical reads',
                                       'db block gets',
                                       'logical reads',
                                       'sorts (memory)',
                                       'sorts',
                                       'sorts (disk)',
                                       'sorts',
                                       STAT_NAME) stat_NAME,
                                VALUE
                           FROM DBA_HIST_SYSSTAT
                          WHERE STAT_NAME IN
                                ('redo size', 'user commits', 'user rollbacks',
                                 'logons cumulative', 'consistent gets',
                                 'db block gets', 'db block changes',
                                 'physical writes', 'physical reads',
                                 'parse count (hard)', 'parse count (total)',
                                 'user calls', 'execute count',
                                 'sorts (memory)', 'sorts (disk)',
                                 'physical write total IO requests',
                                 'physical read total IO requests')) UNION ALL
                         SELECT SNAP_ID, instance_number, STAT_NAME, VALUE
                           FROM DBA_HIST_SYS_TIME_MODEL
                          WHERE STAT_NAME IN ('DB time', 'DB CPU'))
                          GROUP BY snap_id, instance_number, stat_name
                ) b
         WHERE a.instance_number = b.instance_number
           AND a.snap_id = b.snap_id)
 GROUP BY end_time
 ORDER BY 1
/
