-- File Name: ash_topsql1.sql
-- Purpose: Oracle ASH Topsql1
-- Created: 20260516  by  huangtingzhong

--------------------------------------------------------------------------------
--
-- File name:   ash_topsql.sql
-- Author:      zhangqiao
-- Copyright:   zhangqiaoc@olm.com.cn
--
--------------------------------------------------------------------------------

set linesize 250
set pagesize 999
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

SELECT *
  FROM (SELECT SQL_ID,
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
		 WHERE SAMPLE_TIME >=
		       sysdate-&&1/24
		   AND SAMPLE_TIME <=
		       sysdate-(&&1-&&2)/24
		UNION ALL
		SELECT SQL_ID,
		       SAMPLE_ID,
		       DECODE(NVL(SQL_ID, '0'), '0', 0, SQL_OPCODE) SQL_OPCODE,
		       DECODE(SESSION_STATE,'ON CPU',DECODE(SESSION_TYPE,'BACKGROUND','BCPU','ON CPU'),WAIT_CLASS) WAIT_CLASS,10 cnt,
		       SQL_PLAN_HASH_VALUE
		  FROM DBA_HIST_ACTIVE_SESS_HISTORY
		 WHERE SAMPLE_TIME >=sysdate-&&1/24
		   AND SAMPLE_TIME <=sysdate-(&&1-&&2)/24) ASH
	 GROUP BY SQL_ID, SQL_PLAN_HASH_VALUE
	 ORDER BY CPU DESC)
 WHERE ROWNUM < 20;  
 
undefine 1
undefine 2

