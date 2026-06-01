-- File Name: sess_by_sql.sql
-- Purpose: Oracle session By SQL
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 230 pages 20000 heading on verify off
COL event FORMAT a18
COL program FORMAT a23
COL os_sess FOR a25 heading 'SESS_SERIAL|OSPID'
col u_s for a22 heading 'USERNMAE|LAST_CALL|SEQ#'
COL client FOR a31
col sql_id for a18
col sql_fulltext for a200
undefine sql_text
SELECT b.inst_id,
         SUBSTR (
            DECODE (
               b.STATE,
               'WAITING', b.EVENT,
               DECODE (TYPE, 'BACKGROUND', '[BCPU]:', '[CPU]:') || b.event),
            1,
            18)
            event,
         SUBSTR (b.program, 1, 22) program,
         b.username || ':' || last_call_et || ':' || b.seq# u_s,
         b.sid || ':' || b.serial# sess,
         SUBSTR (b.status || ':' || b.state, 1, 19) status,
         b.sql_id,
         d.sql_fulltext
    FROM gv$session b, gv$session_wait s, gv$sqlarea d
   WHERE     s.SID = b.SID
         AND b.inst_id = s.inst_id
         AND b.inst_id = d.inst_id
         AND b.sql_id = d.sql_id
         AND b.username NOT IN ('SYS')
         AND d.sql_fulltext LIKE '%&sql_text%'
ORDER BY inst_id, sql_id
/
undefine sql_text