-- File Name: sess_access_object.sql
-- Purpose: Oracle session Access Object
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set lines 170
set pages 100
col createtime for a20 heading 'Create|Time'
col ddtime for a20 heading 'Last_Ddl|Time'
col a_sid for a30 heading 'inst_id|session'
col a_owner for a50 heading 'Object Owner'
col a_object for a30 heading 'Object Name'
col a_type for a20 heading 'Object Type'
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | session accessing object info                                          |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
ACCEPT sid prompt 'Enter Search sid (i.e. 123|0(ALL)) : '

SELECT DISTINCT 'instance:sessiion ' || a.inst_id || ':' || b.sid as a_sid,
                '   that is accessing an object owner: ' || b.owner as a_owner,
                ' name : ' || b.object as a_object,
                ' type : ' || b.TYPE AS "a_type"
  FROM GV$LOCK a, gv$access b
 WHERE     a.inst_id = b.inst_id
       AND a.sid = b.sid
       AND a.sid = DECODE (&sid, 0, a.sid, &sid)
       AND a.lmode IN (2, 3, 4, 5, 6)
       ORDER BY to_number(substr(a_sid,21),'99999999999')  

/
clear    breaks  
set lines 80
set pages 5
set echo on
set verify on