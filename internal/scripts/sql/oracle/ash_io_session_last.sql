-- File Name: ash_io_session_last.sql
-- Purpose: Oracle ASH Io Session Last
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 200 pages 1000 heading on verify off;
col stime               for  a10              heading "STIME";
col run_time            for  999999           heading "RUN|TIME";
col sid                 for  a15              heading "SID";
col sql_id              for  a18              heading "SQL_ID";
col program             for  a20              heading "PROGRAM";
col event               for  a15              heading "EVENT";
col delta_time          for  999999999999     heading "DELTA|TIME";
col read_iops           for  9999999          heading "READ|IOPS";
col write_iops          for  9999999          heading "WRITE|IOPS";
col read_kbps           for  9999999          heading "READ|KBPS";
col write_kpbs          for  9999999          heading "WRITE|KPBS";
col topr                for  99               heading "TOP|READ";
col topw                for  99               heading "TOP|WRITE";
undefine sid;
undefine serial#;
SELECT to_char(a.SAMPLE_TIME, 'hh24:mi:ss') stime,
       trunc((to_date(to_char(a.sample_time, 'yyyy-mm-dd hh24:mi:ss'),
                      'yyyy-mm-dd hh24:mi:ss') - a.SQL_EXEC_START) * 24 * 3600) run_time,
       a.session_id || '.' || a.session_serial# sid,
       case
         when a.sql_id = a.TOP_LEVEL_SQL_ID then
          '=' || a.sql_id
         else
          '<>' || a.sql_id
       end sql_id,
       substr(a.program, 1, 20) program,
       substr(a.event, 1, 15) event,
       a.DELTA_TIME,
       trunc((a.DELTA_READ_IO_REQUESTS * 1000000) / (DELTA_TIME)) read_iops,
       trunc((a.DELTA_WRITE_IO_REQUESTS * 1000000) / (DELTA_TIME)) write_iops,
       trunc((a.DELTA_READ_IO_BYTES * 1000000) / (DELTA_TIME * 1024)) read_kbps,
       trunc((a.DELTA_WRITE_IO_BYTES * 1000000) / (DELTA_TIME * 1024)) write_kpbs
  FROM GV$ACTIVE_SESSION_HISTORY a
 WHERE (a.DELTA_READ_IO_REQUESTS > 0 or a.DELTA_WRITE_IO_REQUESTS > 0 or
       a.DELTA_READ_IO_BYTES > 0 or a.DELTA_WRITE_IO_BYTES > 0)
   and a.session_id = '&sid'
   and a.session_serial# = nvl('&serial#', a.session_serial#)
 order by stime;
undefine sid;
undefine serial#;