-- File Name: we_by_mutex.sql
-- Purpose: Oracle We By Mutex
-- Created: 20260516  by  huangtingzhong

set echo off 
set lines 200 heading on verify off pages 4000

COL event FORMAT a25
COL program FORMAT a23
COL os_sess FOR a25 heading 'SESS_SERIAL|OSPID'
col u_s for a22 heading 'USERNMAE|LAST_CALL|SEQ#'
COL client FOR a31
col sql_id for a18
col status for a20  heading 'STATUS|STATE'
col command for a15
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col inst_id for 9 heading 'I'
col blocking_sid for 9999999 heading 'BLOCKING|SESSION'
col shared_refcount heading "RFC" format 99
col location_id heading "LOC" format 99
col sleeps  noprint format 99999
col mutex_object format a30
break on inst_id
  SELECT b.inst_id,
         SUBSTR (b.event, 1, 25) event,
         SUBSTR (b.program, 1, 22) program,
         b.username || ':' || last_call_et || ':' || b.seq# u_s,
         b.sid || ':' || b.serial# || ':' || c.spid os_sess,
         SUBSTR (b.status || ':' || b.state, 1, 19) status,
         a.name command,
            DECODE (b.sql_id,
                    '0', b.prev_sql_id,
                    '', b.prev_sql_id,
                    b.sql_id)
         || ':'
         || sql_child_number
            sql_id,
         FLOOR (b.p2 / POWER (2, 4 * ws)) blocking_sid,
         MOD (b.p2, POWER (2, 4 * ws)) shared_refcount,
         FLOOR (b.p3 / POWER (2, 4 * ws)) location_id,
         MOD (b.p3, POWER (2, 4 * ws)) sleeps,
         CASE
            WHEN (b.event LIKE 'library cache:%' AND b.p1 <= POWER (2, 17))
            THEN
               'library cache bucket: ' || b.p1
            ELSE
               (SELECT kglnaobj
                  FROM x$kglob
                 WHERE kglnahsh = b.p1 AND (kglhdadr = kglhdpar) AND ROWNUM = 1)
         END
            mutex_object
    FROM gv$session b,
         gv$process c,
         gv$session_wait s,
         sys.audit_actions a,
         (SELECT DECODE (INSTR (banner, '64'), 0, '4', '8') ws
            FROM v$version
           WHERE ROWNUM = 1) wordsize
   WHERE     b.paddr = c.addr
         AND s.SID = b.SID
         AND b.inst_id = c.inst_id
         AND c.inst_id = s.inst_id
         AND a.action = b.command
         AND b.p1text = 'idn'
         AND b.state = 'WAITING'
ORDER BY inst_id, sql_id
/