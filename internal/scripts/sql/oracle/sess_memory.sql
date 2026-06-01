-- File Name: sess_memory.sql
-- Purpose: Oracle session Memory
-- Created: 20260516  by  huangtingzhong

SET ECHO OFF
SET PAGESIZE 2000
SET LINESIZE 200
SET HEADING ON
COL event FORMAT a15
COL program FORMAT a15
COL os_sess FOR a25 heading 'SESS_SERIAL|OSPID'
col u_s for a22 heading 'USERNMAE|LAST_CALL|SEQ#'
COL client FOR a31
col sql_id for a18
COL row_wait  for a22 heading 'ROW_WAIT|FILE#:OBJ#:BLOCK#:ROW#'
col logon_time for a12
col status for a20  heading 'STATUS|STATE'
col CATEGORY for a15
col pga_used_mem for 999999 heading 'PGA_USED|MEM(M)'
col pga_alloc_mem for 999999 heading 'PGA_ALLOC|MEM(M)'
col pga_freeable_mem for 999999 heading 'PGA_FREEABLE|MEM(M)'
col pga_max_mem for 999999 heading 'PGA_MAX|MEM(M)'
col allocated for 9999999 heading 'ALLOC'
col used for 999999 heading 'USED'
undefine sid
break on event on program on u_s on os_sess on status on sql_id on pga_used_mem on pga_alloc_mem on pga_freeable_mem on pga_max_mem
SELECT SUBSTR (b.event, 1, 15) event,
       SUBSTR (b.program, 1, 15) program,
       b.username || ':' || last_call_et || ':' || b.seq# u_s,
       b.sid || ':' || b.serial# || ':' || c.spid os_sess,
       SUBSTR (b.status || ':' || b.state, 1, 19) status,
          DECODE (b.sql_id,
                  '0', b.prev_sql_id,
                  '', b.prev_sql_id,
                  b.sql_id)
       || ':'
       || sql_child_number
          sql_id,
       TRUNC (pga_used_mem / 1024 / 1024) pga_used_mem,
       TRUNC (pga_alloc_mem / 1024 / 1024) pga_alloc_mem,
       TRUNC (pga_freeable_mem / 1024 / 1024) pga_freeable_mem,
       TRUNC (pga_max_mem / 1024 / 1024) pga_max_mem,
       category,
       TRUNC (allocated / 1024 / 1024) allocated,
       TRUNC (used / 1024 / 1024) used
  FROM V$PROCESS_MEMORY a, V$process c, v$session b
 WHERE     A.pid = c.pid
       AND c.background IS NULL
       AND b.paddr = c.addr
       AND b.sid = NVL ('&sid', b.sid);
undefine sid