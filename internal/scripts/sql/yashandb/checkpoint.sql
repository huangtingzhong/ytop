-- File Name: checkpoint.sql
-- Purpose: YashanDB Show checkpoint progress information
-- Created: 20260516  by  huangtingzhong

col CURRENT_STATUS for a20
select TOTAL_NUM,SCHEDULE_NUM,to_char(LAST_EXECUTED,'yyyy-mm-dd hh24:mi:ss') LAST_EXECUTED,CURRENT_STATUS,DIRTY_QUEUE_LENGTH,DIRTY_QUEUE_LAST,TRUNC_POINT from v$checkpoint;
