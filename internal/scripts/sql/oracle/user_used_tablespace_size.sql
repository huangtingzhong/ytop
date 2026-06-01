-- File Name: user_used_tablespace_size.sql
-- Purpose: Oracle User Used Tablespace Size
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
col tablespace_name for a20
col s_size for 99999999 heading 'total|size'


PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display owner's segment tablespace and size                            |
PROMPT +------------------------------------------------------------------------+ 

ACCEPT owner prompt 'Enter  Owner Name (i.e. SCOTT) : '

SELECT tablespace_name, SUM(bytes)/1024/1024 s_size
    FROM dba_segments
   WHERE owner = upper('&owner')
GROUP BY tablespace_name
/
