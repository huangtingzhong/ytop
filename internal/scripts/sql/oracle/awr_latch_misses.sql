-- File Name: awr_latch_misses.sql
-- Purpose: Oracle AWR Latch Misses
-- Created: 20161010  by  huangtingzhong

set echo off
set lines 250 pages 100 verify off heading on
col inst                for    99            heading 'I';
col end_time            for    a14           heading 'END_TIME';
col parent              for    a30           heading 'PARENT';
col where_from          for    a30           heading 'WHERE_FROM';
col nwmisses            for    99999999      heading 'NOWAIT|MISSES';
col sleeps              for    99999999      heading 'SLEEPS';
col waiter_sleeps       for    99999999      heading 'WAIT_SLEEPS';
undefine latchname;
SELECT inst, end_time, parent, where_from, nwmisses, sleeps, waiter_sleeps
  FROM (SELECT inst,
               end_time,
               parent,
               where_from,
               nwmisses,
               sleeps,
               waiter_sleeps,
               ROW_NUMBER() OVER(PARTITION BY parent ORDER BY sleeps DESC) m_num,
               ROW_NUMBER() OVER(PARTITION BY parent ORDER BY waiter_sleeps DESC) w_num
          FROM (SELECT a.instance_number inst,
                       TO_CHAR(a.end_interval_time, 'mm-dd hh24:mi') end_time,
                       e.parent_name parent,
                       e.where_in_code where_from,
                       e.nwfail_count - NVL(b.nwfail_count, 0) nwmisses,
                       e.sleep_count - NVL(b.sleep_count, 0) sleeps,
                       e.wtr_slp_count - NVL(b.wtr_slp_count, 0) waiter_sleeps
                  FROM dba_hist_latch_misses_summary b,
                       dba_hist_latch_misses_summary e,
                       dba_hist_snapshot             a
                 WHERE b.instance_number(+) = e.instance_number
                   AND b.parent_name(+) = e.parent_name
                   AND b.where_in_code(+) = e.where_in_code
                   AND e.sleep_count > NVL(b.sleep_count, 0)
                   AND a.snap_id = e.snap_id
                   AND e.snap_id = b.snap_id + 1
                   and e.parent_name=nvl('&latchname',e.parent_name)
                   AND a.instance_number = e.instance_number))
 WHERE (m_num < 4 OR w_num < 4)
 ORDER BY inst,
          end_time,
          parent,
          sleeps     DESC,
          where_from,
          m_num      desc,
          w_num      desc;
undefine latchname;