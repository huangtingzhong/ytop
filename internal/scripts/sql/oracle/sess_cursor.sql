-- File Name: sess_cursor.sql
-- Purpose: Oracle session Cursor
-- Created: 20260516  by  huangtingzhong

set lines 200 pages 1000
col machine for a20
col user_name for a20
col sql_id for a19
col cursor_type for a30

prompt "display open cursor   having >5 order by sql_id"

SELECT s.machine,
       oc.user_name,
       oc.SQL_ID,
       oc.CURSOR_TYPE,
       count(1)
FROM v$open_cursor oc,
                   v$session s
WHERE oc.sid = s.sid
  AND user_name != 'SYS'
GROUP BY user_name,
         oc.SQL_ID,
         oc.CURSOR_TYPE,
         machine HAVING COUNT(1) > 5
ORDER BY count(1) DESC;

PROMPT "display highest  open cursor"
col highest_open_cur  for 9999999
col MAX_OPEN_CUR      for a15
SELECT max(a.value) AS highest_open_cur,
       p.value AS max_open_cur
FROM v$sesstat a,
               v$statname b,
                          v$parameter p
WHERE a.statistic# = b.statistic#
  AND b.name = 'opened cursors current'
  AND p.name= 'open_cursors'
GROUP BY p.value;


PROMPT "display event session open_cursor value"
CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES

COLUMN sid               FORMAT 999999            HEADING 'SID'
COLUMN serial_id         FORMAT 99999999          HEADING 'Serial ID'
COLUMN session_status    FORMAT a9                HEADING 'Status'
COLUMN oracle_username   FORMAT a18               HEADING 'Oracle User'
COLUMN os_username       FORMAT a18               HEADING 'O/S User'
COLUMN os_pid            FORMAT a8                HEADING 'O/S PID'
COLUMN session_machine   FORMAT a30               HEADING 'Machine'          TRUNC
COLUMN session_program   FORMAT a40               HEADING 'Session Program'  TRUNC
COLUMN open_cursors      FORMAT 99,999            HEADING 'Open Cursors'
COLUMN open_pct          FORMAT 999               HEADING 'Open %'


CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES

COLUMN sid               FORMAT 999999            HEADING 'SID'
COLUMN serial_id         FORMAT 99999999          HEADING 'Serial ID'
COLUMN session_status    FORMAT a9                HEADING 'Status'
COLUMN oracle_username   FORMAT a18               HEADING 'Oracle User'
COLUMN os_username       FORMAT a18               HEADING 'O/S User'
COLUMN os_pid            FORMAT a8                HEADING 'O/S PID'
COLUMN session_machine   FORMAT a30               HEADING 'Machine'          TRUNC
COLUMN session_program   FORMAT a40               HEADING 'Session Program'  TRUNC
COLUMN open_cursors      FORMAT 99,999            HEADING 'Open Cursors'
COLUMN open_pct          FORMAT 999               HEADING 'Open %'

SELECT
    s.sid                             sid
  , s.serial#                         serial_id
  , s.status                          session_status
  , s.username                        oracle_username
  , s.osuser                          os_username
  , p.spid                            os_pid
  , s.machine                         session_machine
  , s.program                         session_program
  , sstat.value                       open_cursors
  , ROUND((sstat.value/u.value)*100)  open_pct
FROM
    v$process  p
  , v$session  s
  , v$sesstat  sstat
  , v$statname statname
  , (select name, value
     from v$parameter) u
WHERE
      p.addr (+)          = s.paddr
  AND s.sid               = sstat.sid
  AND statname.statistic# = sstat.statistic#
  AND statname.name       = 'opened cursors current'
  AND u.name              = 'open_cursors'
ORDER BY open_cursors DESC
/

