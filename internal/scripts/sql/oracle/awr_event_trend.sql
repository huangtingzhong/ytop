-- File Name: awr_event_trend.sql
-- Purpose: Oracle AWR Event Trend
-- Created: 20260516  by  huangtingzhong

set ver off pages 100 lines 140 tab off
col inst for 9
col time for a19
col EVENT_NAME           for a40
col total_waits          for 9999999999999 heading 'TOTAL_WAITS'
col delta_time_waited    for 999999999.9   heading 'TIME_WAIT_S'
col avg_delta_time       for 999999999.9   heading 'AVG_TIME_MS'
undefine event_name_like
BREAK ON inst  ON event_name
  SELECT instance_number inst,
         event_name,
         TO_CHAR (end_interval_time, 'yyyy-mm-dd hh24:mi:ss') time,
         SUM (delta_total_waits) total_waits,
         ROUND (SUM (delta_time_waited / 1000000), 1) delta_time_waited,
         ROUND (
              SUM (delta_time_waited)
            / DECODE (SUM (delta_total_waits),
                      0, NULL,
                      SUM (delta_total_waits))
            / 1000,
            1)
            avg_delta_time
    FROM (SELECT a.instance_number,
                 a.snap_id,
                 b.end_interval_time,
                 a.event_name,
                   (LEAD (
                       a.total_waits,
                       1)
                    OVER (
                       PARTITION BY a.instance_number,
                                    b.startup_time,
                                    a.event_name
                       ORDER BY a.snap_id))
                 - a.total_waits
                    delta_total_waits,
                   (LEAD (
                       a.time_waited_micro,
                       1)
                    OVER (
                       PARTITION BY a.instance_number,
                                    b.startup_time,
                                    a.event_name
                       ORDER BY a.snap_id))
                 - a.time_waited_micro
                    delta_time_waited
            FROM dba_hist_system_event a, dba_hist_snapshot b
           WHERE     a.snap_id = b.snap_id
                 AND b.instance_number = a.instance_number
                 AND a.event_name LIKE '&event_name_link') a
GROUP BY instance_number, end_interval_time, event_name
ORDER BY inst, event_name, time;