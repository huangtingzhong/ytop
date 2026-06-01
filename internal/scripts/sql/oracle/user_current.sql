-- File Name: user_current.sql
-- Purpose: Oracle User Current
-- Created: 20260516  by  huangtingzhong

set serveroutput on
set linesize 200 pagesize 1400
declare
  l_audsid number;
  l_sid    number;
  l_serial number;
  l_module varchar2(128);
  l_pid    number;
  l_spid   number;
  l_trace  varchar2(2000);
  l_user   varchar2(128);
begin
  DBMS_APPLICATION_INFO.SET_MODULE(module_name => 'HTZ',
                                   action_name => 'ACTIVE');
  select audsid, sid, SERIAL#, module,username
    into l_audsid, l_sid, l_serial, l_module,l_user
    from v$session
   where sid = (select distinct sid from v$mystat);
  select pid, spid
    into l_pid, l_spid
    from v$process
   where addr = (select paddr
                   from v$session
                  where sid = l_sid
                    and serial# = l_serial);
  SELECT d.VALUE || '/' || LOWER(RTRIM(i.INSTANCE, CHR(0))) || '_ora_' ||
         p.spid || '.trc'
    into l_trace
    FROM (SELECT p.spid
            FROM v$mystat m, v$session s, v$process p
           WHERE m.statistic# = 1
             AND s.SID = m.SID
             AND p.addr = s.paddr) p,
         (SELECT t.INSTANCE
            FROM v$thread t, v$parameter v
           WHERE v.NAME = 'thread'
             AND (v.VALUE = 0 OR t.thread# = TO_NUMBER(v.VALUE))) i,
         (SELECT VALUE FROM v$parameter WHERE NAME = 'user_dump_dest') d;

  dbms_output.enable(9999999);
  dbms_output.put_line('===============================================');
  dbms_output.put_line(' USERNAME=' || l_user);
  dbms_output.put_line(' SESSION ID=' || l_sid || '  SERIAL#=' || l_serial);
  dbms_output.put_line(' AUDSID=' || l_audsid || '      MODULE#=' ||
                       l_module);
  dbms_output.put_line(' PID=' || l_pid || '          SPID#=' || l_spid);
  dbms_output.put_line(' TRACE_FILE_LOCATION=' || l_trace);
  dbms_output.put_line('===============================================');
  commit;
end;
/
