-- File Name: lock_by_object.sql
-- Purpose: Oracle Show locks held on a database object
-- Created: 20260516  by  huangtingzhong

set echo off
set heading on
set lines 200
set pages 40
col sess for a25
col l_s for a15 heading 'LAST_CALL_ET|SEQ#'
col command for a20
col object_name for a27 heading 'OWNER|OBJECT_NAME'
col sqlid for a16
col id1-id2 for a20
col l_r for a35 heading 'LMODE_REQUEST'
SELECT /*+ rule */
 DECODE(a.request, 0, 'Holder: ', 'Waiter: ') || c.instance_name || ':' ||
 a.sid sess,
 b.last_call_et || '.' || seq# l_s,
 aa.name command,
 do.owner || '.' || do.object_name object_name,
 DECODE(b.sql_id, '', b.prev_sql_id, b.sql_id) || ':' || sql_child_number AS SQLID,
 a.id1 || '-' || a.id2 "ID1-ID2",
 DECODE(a.lmode,
        1,
        '1||No Lock',
        2,
        '2||Row Share',
        3,
        '3||Row Exclusive',
        4,
        '4||Share',
        5,
        '5||Shr Row Excl',
        6,
        '6||Exclusive',
        NULL)||'.'||DECODE(a.REQUEST,
        1,
        '1||No Lock',
        2,
        '2||Row Share',
        3,
        '3||Row Exclusive',
        4,
        '4||Share',
        5,
        '5||Shr Row Excl',
        6,
        '6||Exclusive',
        NULL) l_r,
 a.type,
 a.ctime
  FROM sys.GV$LOCK          a,
       sys.gv$session       b,
       sys.gv$instance      c,
       sys.gv$locked_object lo,
       sys.audit_actions    aa,
       sys.dba_objects      do
 where a.inst_id = b.inst_id
   and c.inst_id = b.inst_id
   and lo.inst_id = a.inst_id
   and a.sid = b.sid
   and lo.session_id = a.sid
   and lo.object_id = do.object_id
   and aa.action = b.command
   and lo.object_id=a.id1
   and do.owner=nvl(upper('&owner'),do.owner)
   and do.object_name = nvl(upper('&object_name'),do.object_name)
   and a.lmode>1
 order by ctime
/
undefine owner;
undefine object_name;
set echo on