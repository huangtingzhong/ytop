-- File Name: sess_dblink.sql
-- Purpose: Oracle session Dblink
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 200 pages 40
set heading on
col client for a23 heading 'CLIENT|OSUSER_MACHINE_SPID'
col dbinfo for a30 heading 'TYPE_DBNAME_TRANid'
col u_s for a22 heading 'USERNMAE|LAST_CALL_SEQ#'
col STATE  for a30
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col sql_id for a17
COL os_sess FOR a20 heading 'SESS_SERIAL|OSPID'
col command for a15
col event for a25
col status for a19
undefine clientospid;
undefine dbusername;
undefine clientusername;
umdefine clienthostname;
SELECT SUBSTR(a.osuser || '@' || a.machine || '@' || a.process, 1, 24) AS client,
       nvl2(replace(g.k2gtibid, '0'), 'R', 'L') || '.' ||
       regexp_replace(g.k2gtitid_ora,
                      '^(.*)\.(\w+)\.(\d+\.\d+\.\d+)$',
                      '\1') || '.' ||
       regexp_replace(g.k2gtitid_ora,
                      '^(.*)\.(\w+)\.(\d+\.\d+\.\d+)$',
                      '\3') AS dbinfo,
       decode(bitand(g.k2gtdflg, 512), 512, '[ORACLE COORDINATED]') ||
       decode(bitand(g.k2gtdflg, 1024), 1024, '[MULTINODE]') ||
       decode(bitand(g.k2gtdflg, 511),
              0,
              'ACTIVE',
              1,
              'COLLECTING',
              2,
              'FINALIZED',
              4,
              'FAILED',
              8,
              'RECOVERING',
              16,
              'UNASSOCIATED',
              32,
              'FORGOTTEN',
              64,
              'READY FOR RECOVERY',
              128,
              'NO-READONLY FAILED',
              256,
              'SIBLING INFO WRITTEN') AS STATE,
       a.inst_id || ':' || a.username || ':' || a.last_call_et || ':' ||
       a.seq# u_s,
       a.sid || ':' || a.serial# || ':' || c.spid os_sess,
       substr(a.status || ':' || a.STATE, 1, 19) status,
       DECODE(a.sql_id, '0', a.prev_sql_id, '', a.prev_sql_id, a.sql_id) || ':' ||
       sql_child_number sql_id,
       d.name command
  FROM x$k2gte2          g,
       x$ktcxb           t,
       x$ksuse           s,
       gv$process        c,
       sys.audit_actions d,
       gv$session        a
 WHERE g.k2gtdxcb = t.ktcxbxba
   AND g.k2gtdses = t.ktcxbses
   AND s.addr = g.k2gtdses
   AND a.sid = s.indx
   AND a.inst_id(+) = c.inst_id
   AND a.paddr(+) = c.addr
   AND a.inst_id = s.inst_id
   AND d.action = a.command
   AND a.process = nvl('&clientospid', a.process)
   AND a.username = nvl(upper('&dbusername'), a.username)
   AND a.osuser = nvl(upper('&clientusername'), a.osuser)
   AND a.machine = nvl(upper('&clienthostname'), a.machine)
/

