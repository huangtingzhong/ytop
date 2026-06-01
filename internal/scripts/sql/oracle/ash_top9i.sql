-- File Name: ash_top9i.sql
-- Purpose: Oracle ASH Top9i
-- Created: 20260516  by  huangtingzhong

--------------------------------------------------------------------------------
--
-- File name:   ash_top9i.sql
-- Author   :   zhangqiao
-- Copyright:   zhangqiaoc@olm.com.cn
-- Warning  :   Execution plan must use B for drive table,
--              and A must be connected by nested loop
--------------------------------------------------------------------------------

-- CREATE OR REPLACE FUNCTION F_SLEEP(AN_SEC NUMBER)
-- RETURN NUMBER
-- AS 
-- BEGIN
--   dbms_lock.sleep(AN_SEC);
--   RETURN AN_SEC;
-- END;
-- /

SET pagesize 999 linesize 130
break on ID
col info for a50
set timing on

WITH SAMPLE AS (
select /*+MATERIALIZE*/* from(
-- **************************************************************************
  select /*+leading(b) use_nl(a)*/* FROM
  -- view a beg -------------------------------------------------------------
  (SELECT S.SID,S.USERNAME,S.COMMAND,S.OSUSER,
          S.PROCESS,S.MACHINE,S.TERMINAL,S.PROGRAM,S.SQL_HASH_VALUE,
          W.SEQ#,decode(W.STATE,'WAITING',W.EVENT,'ON CPU') EVENT,
          W.STATE,dbms_utility.get_time sample_id 
     FROM V$SESSION S,V$SESSION_WAIT W 
    WHERE S.SID = W.SID 
      AND S.USERNAME IS NOT NULL 
      AND S.STATUS = 'ACTIVE' 
      AND s.SID <> (SELECT SID FROM V$MYSTAT WHERE ROWNUM=1)
    UNION ALL 
   SELECT (0-F_SLEEP(1)) s1,null s2,null s3,null s4,null s5,null s6,
          null s7,null s8,null s9,null s10,null s11,null s12,null s13 
     FROM dual ) a,
  -- view b beg -------------------------------------------------------------
  (select * from dual connect by rownum<=&&1) b
-- **************************************************************************
) where SID>0)
SELECT '[1] TOPSQL' id,to_char(SQL_HASH_VALUE) INFO ,
       substr(DECODE(COMMAND,1,'DDL',2,'INSERT',3,'Query',6,'UPDATE',7,'DELETE',
                     47,'PL/SQL_package_call',50,'Explain Plan',170,'CALL',189,
                     'MERGE',TO_CHAR(COMMAND)),1,8) OPCODE,COUNT(*) 
  FROM SAMPLE
 GROUP BY SQL_HASH_VALUE,
       substr(DECODE(COMMAND,1,'DDL',2,'INSERT',3,'Query',6,'UPDATE',7,'DELETE',
                     47,'PL/SQL_package_call',50,'Explain Plan',170,'CALL',189,
                     'MERGE',TO_CHAR(COMMAND)),1,8)
HAVING count(*) > &1/10
 UNION ALL
SELECT '[2] TOPEET' ID,event,NULL,COUNT(*) FROM SAMPLE GROUP BY event 
 UNION ALL
SELECT '[3] TOPPGM' id,substr(PROGRAM,1,INSTR(program,'@')-1) PROGRAM,NULL,COUNT(*) 
  FROM SAMPLE GROUP BY substr(PROGRAM,1,INSTR(program,'@')-1) HAVING count(*) > &1/10
 ORDER BY 1,4 DESC;
 
undefine 1;


