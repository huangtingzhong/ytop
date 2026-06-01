-- File Name: sess_kgl.sql
-- Purpose: Oracle session Kgl
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 300
set pages 1000
set heading on
set verify off
undefine inst_id;
undefine sid;
undefine owner
undefine object_name
col sess_saddr for a16
col kgllkhdl for a16
col kgllkmod for 9999999
col kgllkreq for 9999999
col kgllktype for a10
col obj for a80 heading 'OWNER:OBJECT_NAME'
col i_s for 9999999999 heading 'SID'
col event for a25
break on i_s on sess_saddr on kgllkhdl
select /*+ rule */b.sid i_s,
       a.kgllkuse sess_saddr,
       a.kgllkhdl,
       substr(b.event,1,25) event,
       a.kgllkmod,
       a.kgllkreq,
       a.kgllktype,
       c.kglnaown||'.'||c.kglnaobj obj
  from dba_kgllock a,
       x$kglob c,
       v$session b,
       v$session_wait d
 where b.sid = nvl('&sid', b.sid)
   and c.kglnaown=nvl('&owner',c.kglnaown)
   and c.kglnaobj=nvl('&object_name',c.kglnaobj)
   and a.kgllkmod>1
   and b.sid=d.sid
   and b.saddr = a.kgllkuse
   and a.kgllkhdl = c.kglhdadr
 order by kgllkhdl,kgllkmod;
undefine inst_id;
undefine sid;
undefine owner;
undefine object_name;