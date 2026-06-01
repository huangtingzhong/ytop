-- File Name: awr_database_size_trend.sql
-- Purpose: Oracle AWR Database Size Trend
-- Created: 20260516  by  huangtingzhong

-- +----------------------------------------------------------------------------+
-- |                               Travel Liu                                   |
-- |                          dbatravel@outlook.com                             |
-- |                         blog.csdn.com/dbatravel                            |
-- |----------------------------------------------------------------------------|
-- |      																															        |
-- |----------------------------------------------------------------------------|
-- | DATABASE : Oracle                                                          |
-- | FILE     : show_database_increase.sql                                      |
-- | CLASS    : Database Administration                                         |
-- | PURPOSE  : This script is listed in the relevant paragraph database        |	
-- | history of the use of space in a snapshot of time change information	      |
-- | This information is not contain undo and temp tablespace                   |
-- | NOTE     :                                                                 |
-- +----------------------------------------------------------------------------+

SET TERMOUT OFF;
COLUMN current_instance NEW_VALUE current_instance NOPRINT;
SELECT rpad(instance_name, 17) current_instance FROM v$instance;
COLUMN USER NEW_VALUE user_name NOPRINT;
SELECT USER FROM DUAL;
SET TERMOUT ON;

PROMPT 
PROMPT +------------------------------------------------------------------------+
PROMPT | Report   : show_database_increase                                      |
PROMPT | Instance : &current_instance                                           |
PROMPT | USER     : &user_name							 |
PROMPT +------------------------------------------------------------------------+


with tmp as 
(select rtime,
                       sum(tablespace_usedsize_MB) tablespace_usedsize_MB,
                       sum(tablespace_size_MB) tablespace_size_MB
                  from (select rtime,
                               e.tablespace_id,
                               (e.tablespace_usedsize) * (f.block_size) / 1024/1024 tablespace_usedsize_MB,
                               (e.tablespace_size) * (f.block_size) / 1024/1024 tablespace_size_MB
                          from dba_hist_tbspc_space_usage e,
                               dba_tablespaces            f,
                               v$tablespace               g
                         where e.tablespace_id = g.TS#
                           and f.tablespace_name = g.NAME
                           and f.contents not in ('TEMPORARY','UNDO'))
                 group by rtime)
       select tmp.rtime,
              tablespace_usedsize_MB,
              tablespace_size_MB,
              (tablespace_usedsize_MB -
              LAG(tablespace_usedsize_MB, 1, NULL) OVER(ORDER BY tmp.rtime)) AS DIFF_MB
         from tmp,
              (select max(rtime) rtime
                 from tmp
                group by substr(rtime, 1, 10)) t2
        where t2.rtime = tmp.rtime
        ORDER BY rtime 
        /
  /*      
                 select rtime,
                        sum(tablespace_usedsize) * 8192 / 1024,
                        sum(tablespace_size) * 8192 / 1024
                   from dba_hist_tbspc_space_usage u
                  where rtime in
                        ('11/15/2012 23:01:11', '11/16/2012 23:00:12',
                         '11/17/2012 23:01:09', '11/18/2012 23:00:49')
                         and u.tablespace_id not in (1,3)
                  group by rtime;
                  */