-- File Name: awr_by_dbid.sql
-- Purpose: Oracle AWR By Dbid
-- Created: 20260516  by  huangtingzhong

-- #***************************************
--  awr.sql
--  
--  Created by zhangqiaoc@olm.com.cn
--  Last modify 20130520
-- 
--  Fetch load profile from AWR
--  Usage: 
--     @awr.sql <TYPE> <INST_ID>
--     type   =1 -> all data,normal format
--     type   =2 -> last four weeks,week format
--     type   =3 -> last seven days,day format
--     inst_id=0 -> all instances
-- #***************************************
define _GV_TOTAL = "--" 
define _GV_WEEK  = "--"
define _GV_DAY   = "--"
define _GV_INST  = "--"

define _BLK_SIZE = 8192

-- 20130128 ?

define _GV_CACHE = "--"
define _GV_FLOW  = "--"

set pagesize 50000 linesize 9999 arraysize 5000 headsep off verify off 

col total noprint new_value _GV_TOTAL
col week  noprint new_value _GV_WEEK
col day   noprint new_value _GV_DAY
col inst  noprint new_value _GV_INST
select decode(&&1,1,'','--') total,
       decode(&&1,2,'','--') week,
       decode(&&1,3,'','--') day,
       decode(&&2,0,'--','') inst
  from dual;

col END_TIME for A12
col NAME     for A20
col TIME     for A6
col HOUR     for 999
WITH SAMPLE AS
 (SELECT SNAP_ID,DECODE(STAT_NAME,'user commits','transactions','user rollbacks','transactions','consistent gets','logical reads','db block gets',
         'logical reads','sorts (memory)','sorts','sorts (disk)','sorts',STAT_NAME) NAME,VALUE
    FROM DBA_HIST_SYSSTAT
   WHERE STAT_NAME IN ('redo size','user commits','user rollbacks','logons cumulative','consistent gets','db block gets','db block changes',
         'physical writes','physical reads','parse count (hard)','parse count (total)','user calls','execute count','sorts (memory)','sorts (disk)')
&_GV_INST AND INSTANCE_NUMBER = &2
   UNION ALL
  SELECT SNAP_ID, STAT_NAME NAME, VALUE
    FROM DBA_HIST_SYS_TIME_MODEL
   WHERE STAT_NAME IN ('DB time','DB CPU')
&_GV_INST AND INSTANCE_NUMBER = &2 
   UNION ALL
SELECT SNAP_ID, 'Estd Interconnect traffic' NAME,
       CASE WHEN stat_name IN ('gc cr blocks received','gc cr blocks served','gc current blocks received','gc current blocks served') 
            THEN VALUE*&_BLK_SIZE ELSE VALUE*200 END
  FROM DBA_HIST_SYSSTAT
 WHERE STAT_NAME IN ('gc cr blocks received','gc cr blocks served','gc current blocks received','gc current blocks served','gcs messages sent','ges messages sent')   
&_GV_INST AND INSTANCE_NUMBER = &2 
   UNION ALL
SELECT SNAP_ID,'Estd Interconnect traffic' NAME, VALUE*200
  FROM DBA_HIST_DLM_MISC
 WHERE NAME IN ('gcs msgs received', 'ges msgs received')
&_GV_INST AND INSTANCE_NUMBER = &2 
------------------------------------------------
&_GV_FLOW     UNION ALL 
&_GV_FLOW  SELECT SNAP_ID, NAME, VALUE
&_GV_FLOW    FROM DBA_HIST_DLM_MISC
&_GV_FLOW   WHERE NAME IN ('messages flow controlled','messages sent directly','messages sent indirectly','flow control messages received', 'flow control messages sent')
&_GV_FLOW  &_GV_INST AND INSTANCE_NUMBER = &2  
&_GV_FLOW     UNION ALL
&_GV_FLOW  SELECT SNAP_ID,'gc cr grant 2-way time waited' name,TIME_WAITED_MICRO/1000000*1000 FROM DBA_HIST_SYSTEM_EVENT WHERE EVENT_NAME='gc cr grant 2-way'
&_GV_FLOW  &_GV_INST AND INSTANCE_NUMBER = &2  
&_GV_FLOW     UNION ALL
&_GV_FLOW  SELECT SNAP_ID,'gc cr grant 2-way total wait' name,TOTAL_WAITS FROM DBA_HIST_SYSTEM_EVENT WHERE EVENT_NAME='gc cr grant 2-way'
&_GV_FLOW  &_GV_INST AND INSTANCE_NUMBER = &2  
&_GV_FLOW     UNION ALL
&_GV_FLOW  SELECT SNAP_ID, LATCH_NAME NAME, GETS
&_GV_FLOW    FROM DBA_HIST_LATCH
&_GV_FLOW   WHERE LATCH_NAME = 'KJCT flow control latch'
&_GV_FLOW  &_GV_INST AND INSTANCE_NUMBER = &2    
------------------------------------------------
&_GV_CACHE  UNION ALL
&_GV_CACHE SELECT SNAP_ID, '[CACHE]'||CLASS NAME, CR_BLOCK + CURRENT_BLOCK VALUE
&_GV_CACHE   FROM DBA_HIST_INST_CACHE_TRANSFER  
&_GV_CACHE &_GV_INST AND INSTANCE_NUMBER = &2  
 ),
SNAPSHOT AS
 (SELECT DISTINCT SNAP_ID,STARTUP_TIME STARTUP_TIME,TRUNC(CAST(END_INTERVAL_TIME AS DATE), 'MI') END_TIME,EXTRACT(HOUR FROM END_INTERVAL_TIME) HOUR,
         TRUNC(TRUNC(SYSDATE) -TRUNC(CAST(END_INTERVAL_TIME AS DATE))) DAY,TO_CHAR(END_INTERVAL_TIME, 'D') DAY_OF_WEEK,
         TRUNC((TRUNC(SYSDATE) + 7 - TO_CHAR(SYSDATE, 'D') - TRUNC(CAST(END_INTERVAL_TIME AS DATE))) / 7) WEEK
    FROM (SELECT INSTANCE_NUMBER,SNAP_ID,CAST(MAX(STARTUP_TIME) OVER(PARTITION BY SNAP_ID) AS DATE) STARTUP_TIME,COUNT(*) OVER(PARTITION BY SNAP_ID) CNT,
                 COUNT(DISTINCT INSTANCE_NUMBER) OVER() INSTS,END_INTERVAL_TIME
            FROM DBA_HIST_SNAPSHOT) WHERE CNT = INSTS AND EXTRACT(MINUTE FROM END_INTERVAL_TIME) = 0)
SELECT
-- TOTAL ************************************
&_GV_TOTAL  END_TIME,
&_GV_TOTAL  &_GV_CACHE  ROUND(SUM(DECODE(NAME, '[CACHE]data block', PER_SECOND, 0))) DATA_BLK, 
&_GV_TOTAL  &_GV_CACHE  ROUND(SUM(DECODE(NAME, '[CACHE]undo header', PER_SECOND, 0))) UDO_HDR, 
&_GV_TOTAL  &_GV_CACHE  ROUND(SUM(DECODE(NAME, '[CACHE]undo block', PER_SECOND, 0))) UDO_BLK, 
&_GV_TOTAL  &_GV_CACHE  ROUND(SUM(DECODE(NAME, '[CACHE]others', PER_SECOND, 0))) OTH_BOK,
&_GV_TOTAL  &_GV_FLOW   ROUND(SUM(DECODE(NAME, 'messages flow controlled', PER_SECOND, 0))) FLOW_MSG,
&_GV_TOTAL  &_GV_FLOW   ROUND(SUM(DECODE(NAME, 'messages sent directly', PER_SECOND, 0))) DIRECT_MSG,
&_GV_TOTAL  &_GV_FLOW   ROUND(SUM(DECODE(NAME, 'messages sent indirectly', PER_SECOND, 0))) INDIRECT_MSG,
&_GV_TOTAL  &_GV_FLOW   ROUND(SUM(DECODE(NAME, 'flow control messages received', PER_SECOND, 0))) FLOW_MSG_RECV,  
&_GV_TOTAL  &_GV_FLOW   ROUND(SUM(DECODE(NAME, 'flow control messages sent', PER_SECOND, 0))) FLOW_MSG_SENT,  
&_GV_TOTAL  &_GV_FLOW   ROUND(SUM(DECODE(NAME, 'gc cr grant 2-way time waited', PER_SECOND, 0))) GRANT_TIME_WAITED, 
&_GV_TOTAL  &_GV_FLOW   ROUND(SUM(DECODE(NAME, 'gc cr grant 2-way total wait', PER_SECOND, 0))) GRANT_TOTAL_WAITS, 
&_GV_TOTAL  &_GV_FLOW   ROUND(SUM(DECODE(NAME, 'KJCT flow control latch', PER_SECOND, 0))/1000) FLOW_LATCH,  
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'DB time', PER_SECOND, 0)) / 1000000) AAS,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'DB CPU', PER_SECOND, 0)) / 1000000) CPU_AAS,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'redo size', PER_SECOND, 0)) / 1024) REDO_KB,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'logons cumulative', PER_SECOND, 0))) LOGON,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'logical reads', PER_SECOND, 0)) * 8 / 1024) LOG_READ_MB,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'db block changes', PER_SECOND, 0)) * 8 / 1024) BLK_CHANGE_MB,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'physical reads', PER_SECOND, 0)) * 8 / 1024) PHY_READ_MB,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'physical writes', PER_SECOND, 0)) * 8 / 1024) PHY_WRT_MB,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'parse count (total)', PER_SECOND, 0))) PARSE,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'user calls', PER_SECOND, 0))) UCALL,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'execute count', PER_SECOND, 0))) EXECNT,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'sorts', PER_SECOND, 0))) SORTS,
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'transactions', PER_SECOND, 0))) TRANS, 
&_GV_TOTAL  ROUND(SUM(DECODE(NAME, 'Estd Interconnect traffic', PER_SECOND, 0))/1024) ICONN_KB
-- WEEK *************************************
&_GV_WEEK   NAME,
&_GV_WEEK   DAY_OF_WEEK || '*' || LPAD(HOUR, 2, '0') TIME,
&_GV_WEEK   ROUND(SUM(DECODE(WEEK, 0, PER_SECOND, 0))) THIS_WEEK,
&_GV_WEEK   ROUND(SUM(DECODE(WEEK, 1, PER_SECOND, 0))) LAST_WEEK,
&_GV_WEEK   ROUND(SUM(DECODE(WEEK, 2, PER_SECOND, 0))) LAST_TWO_WEEK,
&_GV_WEEK   ROUND(SUM(DECODE(WEEK, 3, PER_SECOND, 0))) LAST_THREE_WEEK
-- DAY **************************************
&_GV_DAY    NAME,
&_GV_DAY    HOUR,
&_GV_DAY    ROUND(SUM(DECODE(DAY, 0, PER_SECOND, 0))) TODAY,
&_GV_DAY    ROUND(SUM(DECODE(DAY, 1, PER_SECOND, 0))) YESTERDAY,
&_GV_DAY    ROUND(SUM(DECODE(DAY, 2, PER_SECOND, 0))) TWO_DAYS,
&_GV_DAY    ROUND(SUM(DECODE(DAY, 3, PER_SECOND, 0))) THREE_DAYS,
&_GV_DAY    ROUND(SUM(DECODE(DAY, 4, PER_SECOND, 0))) FOUR_DAYS,
&_GV_DAY    ROUND(SUM(DECODE(DAY, 5, PER_SECOND, 0))) FIVE_DAYS,  
&_GV_DAY    ROUND(SUM(DECODE(DAY, 6, PER_SECOND, 0))) SIX_DAYS,
&_GV_DAY    ROUND(SUM(DECODE(DAY, 7, PER_SECOND, 0))) SEVEN_DAYS
-- END **************************************       
FROM(
 SELECT TO_CHAR(END_TIME,'YYYYMMDD HH24') END_TIME,NAME,VALUE / INTERVAL PER_SECOND,HOUR,DAY,DAY_OF_WEEK,WEEK
   FROM (
         SELECT SNAP_ID,END_TIME,(END_TIME -(LAG(END_TIME) OVER(PARTITION BY STARTUP_TIME, NAME ORDER BY SNAP_ID))) * 1440 * 60 INTERVAL,
               (VALUE - (LAG(VALUE) OVER(PARTITION BY STARTUP_TIME, NAME ORDER BY SNAP_ID))) VALUE,NAME,STARTUP_TIME,HOUR,DAY,DAY_OF_WEEK,WEEK
          FROM (
                SELECT S.SNAP_ID,NAME,STARTUP_TIME,END_TIME,SUM(VALUE) VALUE,HOUR,DAY,DAY_OF_WEEK,WEEK
                  FROM SAMPLE S, SNAPSHOT N 
                 WHERE S.SNAP_ID = N.SNAP_ID
                 GROUP BY S.SNAP_ID,NAME,STARTUP_TIME,END_TIME,HOUR,DAY,DAY_OF_WEEK,WEEK
               )
       )
 WHERE INTERVAL IS NOT NULL
)
-- TOTAL ************************************
&_GV_TOTAL GROUP BY END_TIME
&_GV_TOTAL ORDER BY END_TIME
-- WEEK *************************************
&_GV_WEEK  GROUP BY NAME, DAY_OF_WEEK || '*' || LPAD(HOUR, 2, '0')
&_GV_WEEK  ORDER BY NAME, DAY_OF_WEEK || '*' || LPAD(HOUR, 2, '0')
-- DAY **************************************
&_GV_DAY   GROUP BY NAME, HOUR
&_GV_DAY   ORDER BY NAME, HOUR
-- END **************************************       
/

undefine 1
undefine 2