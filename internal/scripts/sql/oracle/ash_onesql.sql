-- File Name: ash_onesql.sql
-- Purpose: Oracle ASH Onesql
-- Created: 20260516  by  huangtingzhong

set echo off
ACCEPT b_hours prompt 'Enter Search Hours Ago (i.e. 3) : '
ACCEPT e_hours prompt 'Enter How Many Hours  (i.e. 3) : '
ACCEPT sql_id prompt 'Enter Search Sql_Id  (i.e. db 123) : '
variable b_hours number;
variable e_hours number;
variable i_sid varchar2(20);
begin
   :e_hours:=&e_hours;
   :b_hours:=&b_hours;
   :i_sid:='&sql_id';
   end;
   /

set linesize 250
set pagesize 999


col time for a19 heading 'sample_time'
col sess_id for a15 heading 'session|serial#'
col sqlid for a18 heading 'sql_id|child_number'
col pn_text for a30 heading 'P1_TEXT:P2_TEXT:P3_TEXT'
col pn for a20 heading 'P1:P2:P3'
col oevent for a30 heading 'Event'
col oprogram for a15 heading 'PROGRAM'
col obj for a15 heading 'waiting|obj#:file#block#'

SELECT TO_CHAR (sample_time, 'yyyy-mm-dd hh24:mi:ss') time,
       session_id || '-' || session_serial# sess_id,session_state,
       SUBSTR (program, 1, 30) oprogram,
       sql_id || ':' || sql_child_number sqlid,
       SUBSTR (event, 0, 15) oevent,
       p1text || ':' || p2text || ':' || p3text pn_text,
       p1 || ':' || p2 || ':' || p3 pn,
       current_obj#||':'||current_file#||':'||current_block#  obj
  FROM GV$ACTIVE_SESSION_HISTORY
 WHERE     SAMPLE_TIME >= SYSDATE - :b_hours / 24
       AND SAMPLE_TIME <= SYSDATE - (:b_hours - :e_hours) / 24
       AND sql_id = :i_sid
UNION ALL
SELECT TO_CHAR (sample_time, 'yyyy-mm-dd hh24:mi:ss') time,
       session_id || '-' || session_serial# sess_id,session_state,
       SUBSTR (program, 1, 30),
       sql_id || ':' || sql_child_number sqlid,
       SUBSTR (event, 0, 15) oevent,
       p1text || ':' || p2text || ':' || p3text pn_text,
       p1 || ':' || p2 || ':' || p3 pn,
       current_obj#||':'||current_file#||':'||current_block#  obj
  FROM DBA_HIST_ACTIVE_SESS_HISTORY
 WHERE     SAMPLE_TIME >= SYSDATE - :b_hours / 24
       AND SAMPLE_TIME <= SYSDATE - (:b_hours - :e_hours) / 24
       AND sql_id = :i_sid
ORDER BY TIME, sqlid
/

col opcode for a8
col SQL_PLAN_HASH_VALUE for 99999999999
col TOTAL  for 999999
col OTHER  for 9999 
col NET    for 99999
col APP    for 99999
col ADMIN  for 9999 
col CLUST  for 99999
col CONCUR for 99999
col CONFIG for 9999 
col COMMIT for 99999
col S_IO   for 99999
col UIO    for 99999
col CPU    for 99999
col BCPU   for 99999

SELECT SQL_ID,
	       sum(cnt) TOTAL,
	       SUM(DECODE(WAIT_CLASS, 'Other', cnt, 0)) OTHER,
	       SUM(DECODE(WAIT_CLASS, 'Network', cnt, 0)) NET,
	       SUM(DECODE(WAIT_CLASS, 'Application', cnt, 0)) APP,
	       SUM(DECODE(WAIT_CLASS, 'Administration', cnt, 0)) ADMIN,
	       SUM(DECODE(WAIT_CLASS, 'Cluster', cnt, 0)) CLUST,
	       SUM(DECODE(WAIT_CLASS, 'Concurrency', cnt, 0)) CONCUR,
	       SUM(DECODE(WAIT_CLASS, 'Configuration', cnt, 0)) CONFIG,
	       SUM(DECODE(WAIT_CLASS, 'Commit', cnt, 0)) COMMIT,
	       SUM(DECODE(WAIT_CLASS, 'System I/O', cnt, 0)) S_IO,
	       SUM(DECODE(WAIT_CLASS, 'User I/O', cnt, 0)) UIO,
	       SUM(DECODE(WAIT_CLASS, 'ON CPU', cnt, 0)) CPU,
	       SUM(DECODE(WAIT_CLASS, 'BCPU', cnt, 0)) BCPU,
	       substr(DECODE(MAX(SQL_OPCODE),1,'DDL',2,'INSERT',3,'Query',6,'UPDATE',7,'DELETE',47,'PL/SQL_package_call',50,'Explain Plan',170,'CALL',189,'MERGE',TO_CHAR(MAX(SQL_OPCODE))),1,6) OPCODE,
	       SQL_PLAN_HASH_VALUE
	  FROM (SELECT SQL_ID,
		       SAMPLE_ID,
		       DECODE(NVL(SQL_ID, '0'), '0', 0, SQL_OPCODE) SQL_OPCODE,
		       DECODE(SESSION_STATE,'ON CPU',DECODE(SESSION_TYPE,'BACKGROUND','BCPU','ON CPU'),WAIT_CLASS) WAIT_CLASS,1 cnt,
		       SQL_PLAN_HASH_VALUE
		  FROM GV$ACTIVE_SESSION_HISTORY
                             WHERE     SAMPLE_TIME >= SYSDATE - :b_hours / 24
                                   AND SAMPLE_TIME <=
                                          SYSDATE - (:b_hours - :e_hours) / 24
                                   AND sql_id = :i_sid
		UNION ALL
		SELECT SQL_ID,
		       SAMPLE_ID,
		       DECODE(NVL(SQL_ID, '0'), '0', 0, SQL_OPCODE) SQL_OPCODE,
		       DECODE(SESSION_STATE,'ON CPU',DECODE(SESSION_TYPE,'BACKGROUND','BCPU','ON CPU'),WAIT_CLASS) WAIT_CLASS,10 cnt,
		       SQL_PLAN_HASH_VALUE
		  FROM DBA_HIST_ACTIVE_SESS_HISTORY
                             WHERE     SAMPLE_TIME >= SYSDATE - :b_hours / 24
                                   AND SAMPLE_TIME <=
                                          SYSDATE - (:b_hours - :e_hours) / 24
                                   AND sql_id = :i_sid) ASH
	 GROUP BY SQL_ID, SQL_PLAN_HASH_VALUE
	 ORDER BY CPU DESC
	 /
undefine 1
undefine 2

