-- File Name: awr_event_top5.sql
-- Purpose: Oracle Show top 5 wait events from AWR
-- Created: 20161010  by  huangtingzhong

set echo off
set lines 350 pages 1000 heading on
col snap_time for a11
col event1         for a25
col event2         for a25
col event3         for a20
col event4         for a20
col event5         for a20
col aas1           for 99999
col aas3           for 99999
col aas2           for 99999
col aas4           for 99999
col aas5           for 99999
col ratio1         for 999.99
col ratio2         for 999.99
col ratio3         for 999.99
col ratio4         for 999.99
col ratio5         for 999.99
col avg_time1      for a6
col avg_time2      for a6
col avg_time3      for a6
col avg_time4      for a6
col avg_time5      for a6
/* Formatted on 2016/10/10 22:16:14 (QP5 v5.256.13226.35510) */
SELECT snap_time,
       -- next_snap_time,
       SUBSTR(event1, 1, 25) event1,
       -- time_waited1,
       aas1,
       ratio1,
       avg_time1,
       SUBSTR(event2, 1, 25) event2,
       -- time_waited2,
       aas2,
       ratio2,
       avg_time2,
       SUBSTR(event3, 1, 20) event3,
       -- TIME_WAITED3,
       aas3,
       ratio3,
       avg_time3,
       SUBSTR(event4, 1, 15) event4,
       -- TIME_WAITED4,
       aas4,
       ratio4,
       avg_time4
       --SUBSTR(event5, 1, 10) event3,
       ---- TIME_WAITED5,
       --aas5,
       --ratio5,
       --avg_time5
  FROM (SELECT TO_CHAR(SNAP_TIME, 'mmdd hh24:mi') SNAP_TIME,
               TO_CHAR(NEXT_SNAP_TIME, 'mmdd hh24:mi') NEXT_SNAP_TIME,
               EVENT EVENT1,
               TIME_WAITED TIME_WAITED1,
               AAS AAS1,
               RATIO RATIO1,
               avg_time avg_time1,
               LEAD(EVENT, 1, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) EVENT2,
               LEAD(TIME_WAITED, 1, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) TIME_WAITED2,
               LEAD(AAS, 1, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) AAS2,
               LEAD(RATIO, 1, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) RATIO2,
               LEAD(avg_time, 1, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) avg_time2,
               LEAD(EVENT, 2, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) EVENT3,
               LEAD(TIME_WAITED, 2, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) TIME_WAITED3,
               LEAD(AAS, 2, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) AAS3,
               LEAD(RATIO, 2, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) RATIO3,
               LEAD(avg_time, 2, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) avg_time3,
               LEAD(EVENT, 3, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) EVENT4,
               LEAD(TIME_WAITED, 3, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) TIME_WAITED4,
               LEAD(AAS, 3, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) AAS4,
               LEAD(RATIO, 3, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) RATIO4,
               LEAD(avg_time, 3, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) avg_time4,
               LEAD(EVENT, 4, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) EVENT5,
               LEAD(TIME_WAITED, 4, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) TIME_WAITED5,
               LEAD(AAS, 4, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) AAS5,
               LEAD(RATIO, 4, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) RATIO5,
               LEAD(avg_time, 4, 0) OVER(PARTITION BY SNAP_TIME ORDER BY RN) avg_time5,
               RN
          FROM (SELECT SNAP_TIME,
                       NEXT_SNAP_TIME,
                       EVENT,
                       TIME_WAITED,
                       CASE
                         WHEN avg_time < 1000 THEN
                          to_char(avg_time)   
                         WHEN avg_time BETWEEN 1000 AND 1000000 THEN
                          ROUND(avg_time / 1000, 1) || 'S'
                         WHEN avg_time > 1000000 THEN
                          ROUND(avg_time / 1000 / 60) || 'M'
                       END avg_time,
                       ROUND(TIME_WAITED /
                             ((NEXT_SNAP_TIME - SNAP_TIME) * 24 * 60 * 60),
                             2) AAS,
                       ROUND(TIME_WAITED / TOTAL_TIME_WAITED * 100, 2) RATIO,
                       RN
                  FROM (SELECT SNAP_TIME,
                               NEXT_SNAP_TIME,
                               EVENT,
                               ROUND(DECODE(1000 * TIME_WAITED,
                                            0,
                                            NULL,
                                            1000 * TIME_WAITED) /
                                     DECODE(TOTAL_WAITS, 0, NULL, TOTAL_WAITS),
                                     1) avg_time,
                               TIME_WAITED,
                               SUM(TIME_WAITED) OVER(PARTITION BY SNAP_TIME) TOTAL_TIME_WAITED,
                               ROW_NUMBER() OVER(PARTITION BY SNAP_TIME ORDER BY TIME_WAITED DESC) RN
                          FROM (SELECT AA.SNAP_TIME,
                                       BB.SNAP_TIME NEXT_SNAP_TIME,
                                       AA.EVENT,
                                       ROUND(BB.TIME_WAITED - AA.TIME_WAITED, 2) TIME_WAITED,
                                       ROUND(BB.TOTAL_WAITS - AA.TOTAL_WAITS, 2) TOTAL_WAITS
                                  FROM (SELECT A.SNAP_ID,
                                               TO_DATE(TO_CHAR(END_INTERVAL_TIME,
                                                               'yyyy-mm-dd hh24:mi:ss'),
                                                       'yyyy-mm-dd hh24:mi:ss') SNAP_TIME,
                                               A.EVENT_NAME EVENT,
                                               A.TOTAL_WAITS,
                                               A.TIME_WAITED_MICRO / 1000000 TIME_WAITED,
                                               DENSE_RANK() OVER(ORDER BY B.SNAP_ID) DS
                                          FROM DBA_HIST_SYSTEM_EVENT A,
                                               DBA_HIST_SNAPSHOT     B
                                         WHERE A.SNAP_ID = B.SNAP_ID
                                           AND A.INSTANCE_NUMBER =
                                               B.INSTANCE_NUMBER
                                           AND B.INSTANCE_NUMBER =
                                               (SELECT INSTANCE_NUMBER
                                                  FROM V$INSTANCE)
                                           AND A.WAIT_CLASS <> 'Idle') AA,
                                       (SELECT A.SNAP_ID,
                                               TO_DATE(TO_CHAR(END_INTERVAL_TIME,
                                                               'yyyy-mm-dd hh24:mi:ss'),
                                                       'yyyy-mm-dd hh24:mi:ss') SNAP_TIME,
                                               A.EVENT_NAME EVENT,
                                               A.TOTAL_WAITS,
                                               A.TIME_WAITED_MICRO / 1000000 TIME_WAITED,
                                               DENSE_RANK() OVER(ORDER BY B.SNAP_ID) DS
                                          FROM DBA_HIST_SYSTEM_EVENT A,
                                               DBA_HIST_SNAPSHOT     B
                                         WHERE A.SNAP_ID = B.SNAP_ID
                                           AND A.INSTANCE_NUMBER =
                                               B.INSTANCE_NUMBER
                                           AND B.INSTANCE_NUMBER =
                                               (SELECT INSTANCE_NUMBER
                                                  FROM V$INSTANCE)
                                           AND A.WAIT_CLASS <> 'Idle') BB
                                 WHERE AA.DS = BB.DS - 1
                                   AND AA.EVENT = BB.EVENT))
                 WHERE RN <= 5))
 WHERE RN = 1;
