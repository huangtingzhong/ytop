-- File Name: user_used_total_size.sql
-- Purpose: Oracle User Used Total Size
-- Created: 20260516  by  huangtingzhong

set lines 200
 SELECT TO_CHAR (SYSDATE, 'yyyy-mm-dd hh24:mi:ss') GATHER_TIME,
         OWNER,
         TRUNC (SUM (BYTES) / 1024 / 1024) TOTAL_MB,
         TRUNC (
              SUM (
                 DECODE (A.SEGMENT_TYPE,
                         'TABLE', A.BYTES,
                         'TABLE PARTITION', A.BYTES,
                         0))
            / 1024
            / 1024)
            TABLE_MB,
         TRUNC (
              SUM (
                 DECODE (A.SEGMENT_TYPE,
                         'INDEX', A.BYTES,
                         'INDEX PARTITION', A.BYTES,
                         0))
            / 1024
            / 1024)
            INDEX_MB,
         TRUNC (
              SUM (
                 DECODE (A.SEGMENT_TYPE,
                         'LOBSEGMENT', A.BYTES,
                         'LOBINDEX', A.BYTES,
                         'LOB PARTITION', A.BYTES,
                         0))
            / 1024
            / 1024)
            LOB_MB
    FROM DBA_SEGMENTS A, DBA_USERS B
   WHERE A.OWNER = B.USERNAME AND B.ACCOUNT_STATUS = 'OPEN'
GROUP BY OWNER
ORDER BY 3 DESC
/
