-- File Name: sess_event_library_cache_by_object.sql
-- Purpose: Oracle session Event Library Cache By Object
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 300
set pages 40
set heading on
set verify off
col s_u_s for a40 heading 'INST_ID.SID|USERNAME.STATUS'
col sql_id for a20 heading 'SQL_ID|SQL_CHILD_NUMBER'
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col l_s for a15 heading 'LAST_CALL_ET|SEQ#'
col command for a20;
col client for a25;
col event for a20
col program for a25
undefine owner;
undefine object_name;
select a.inst_id || '.' || a.sid || '.' || a.username || '.' || a.status s_u_s,
       a.LAST_CALL_ET || '.' || a.seq# l_s,
       a.BLOCKING_SESSION_STATUS || ':' || a.BLOCKING_INSTANCE || ':' ||
       a.BLOCKING_SESSION block_s,
       DECODE(a.sql_id, '0', a.prev_sql_id, a.sql_id) || ':' ||
       sql_child_number sql_id,
       b.name AS command,
       substr(a.event, 1, 20) event,
       SUBSTR(a.program, 1, 25) program,
       substr(a.osuser || '@' || a.machine || '@' || a.process, 1, 24) AS client
  from gv$session a, audit_actions b
 where a.command = b.action
   and (a.inst_id, a.saddr) in
       (select inst_id, p.kgllkuse
          from (select inst_id, kgllkuse, kgllkhdl
                  from x$kgllk
                union all
                select inst_id, kglpnuse, kglpnhdl from x$kglpn) p
         where p.kgllkhdl in
               (select /*+ unnest */
                 a.kglhdadr
                  from x$kglob a
                 where a.kglnaown = nvl(upper('&owner'), a.kglnaown)
                   and a.KGLNAOBJ = nvl(upper('&object_name'), a.KGLNAOBJ)))
 order by 1;
undefine owner;
undefine object_name;