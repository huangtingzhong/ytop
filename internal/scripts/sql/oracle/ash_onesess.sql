-- File Name: ash_onesess.sql
-- Purpose: Oracle ASH Onesess
-- Created: 20260516  by  huangtingzhong

SET FEEDBACK OFF
SET VERIFY OFF
SET LINESIZE 300
SET PAGESIZE 100
SET HEADING ON
SET TRIMSPOOL ON

COL TIME            FORMAT A17    HEADING 'TIME'
COL SQLID           FORMAT A17    HEADING 'SQL'
COL SQL_EXEC_ID     FORMAT 999999999 HEADING 'EXEC_ID'
COL EXEC_DURATION   FORMAT A8     HEADING 'DUR'
COL PLSQL           FORMAT A40    HEADING 'PLSQL_OBJ_SUB'
COL PTEXT           FORMAT A50    HEADING 'PTEXT'
COL EVENT           FORMAT A15    HEADING 'EVENT'
COL USERNAME        FORMAT A15    HEADING 'USER'
COL SESSION         FORMAT A12    HEADING 'SESSION'
COL PROGRAM         FORMAT A10    HEADING 'PROG'
COL "DB%"           FORMAT 99.99  HEADING 'DB%'
COL "CPU%"          FORMAT 99.99  HEADING 'CPU%'
COL IOPS            FORMAT A5     HEADING 'IOPS'
COL MBPS            FORMAT A5     HEADING 'MBPS'
COL LOGICAL         FORMAT A5     HEADING 'LOG'
COL PGA_ALLOCATED   FORMAT A5     HEADING 'PGA'
COL TEMP_ALLOCATED  FORMAT A5     HEADING 'TEMP'
COL OBJ             FORMAT A40    HEADING 'OBJ'
COL SID             FORMAT A15    HEADING 'SID'

define _PLSQL_MODE   = "--"
define _P_MODE       = "  "

ACCEPT begin_hours PROMPT 'Enter Search Hours Ago (i.e. 2(default)) : '  DEFAULT '0.083'
ACCEPT interval_hours PROMPT 'Enter How Interval Hours  (i.e. 2(default)) : ' DEFAULT '0.083'
ACCEPT sid PROMPT 'Enter Session ID  : '
VARIABLE begin_hours NUMBER;
VARIABLE interval_hours NUMBER;
VARIABLE sid NUMBER;

BEGIN
    :begin_hours := &begin_hours;
    :interval_hours := &interval_hours;
    :sid := &sid;
END;
/

SET FEEDBACK OFF;

WITH ash_data
     AS (SELECT SAMPLE_TIME,
                SQL_ID,
                SQL_CHILD_NUMBER,
                SQL_EXEC_ID,
                SQL_EXEC_START,
                PLSQL_OBJECT_ID,
                PLSQL_SUBPROGRAM_ID,
                SESSION_STATE,
                EVENT,
                USER_ID,
                SESSION_ID,
                SESSION_SERIAL#,
                PROGRAM,
                TM_DELTA_DB_TIME,
                TM_DELTA_TIME,
                TM_DELTA_CPU_TIME,
                DELTA_READ_IO_REQUESTS,
                DELTA_WRITE_IO_REQUESTS,
                DELTA_READ_IO_BYTES,
                DELTA_WRITE_IO_BYTES,
                DELTA_READ_MEM_BYTES,
                DELTA_TIME,
                PGA_ALLOCATED,
                TEMP_SPACE_ALLOCATED,
                P1TEXT,
                P2TEXT,
                P3TEXT,
                CURRENT_OBJ#,
                CURRENT_FILE#,
                CURRENT_BLOCK#
           FROM GV$ACTIVE_SESSION_HISTORY
          WHERE     IS_AWR_SAMPLE = 'N'
                AND SAMPLE_TIME >= SYSDATE - :begin_hours / 24
                AND SAMPLE_TIME <=
                        SYSDATE - (:begin_hours - :interval_hours) / 24
                AND SESSION_ID = :sid)
  SELECT TO_CHAR (ash.SAMPLE_TIME, 'yyyymmdd hh24:mi:ss')              time,
         NVL (U.USERNAME, 'USER_' || ash.USER_ID)                      username,
         ash.SESSION_ID || ':' || ash.SESSION_SERIAL#                  sid,
         ash.SQL_ID || ':' || ash.SQL_CHILD_NUMBER                     sqlid,
         ash.SQL_EXEC_ID,
          CASE
              WHEN ash.SQL_EXEC_START IS NOT NULL
              THEN
                  CASE
                      WHEN EXTRACT(DAY FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 24 * 3600 + 
                           EXTRACT(HOUR FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 3600 +
                           EXTRACT(MINUTE FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 60 +
                           EXTRACT(SECOND FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) >= 3600
                      THEN
                             TO_CHAR (
                                 ROUND (
                                     EXTRACT(DAY FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 24 +
                                     EXTRACT(HOUR FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) +
                                     EXTRACT(MINUTE FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) / 60,
                                     1))
                          || 'h'
                      WHEN EXTRACT(DAY FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 24 * 3600 + 
                           EXTRACT(HOUR FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 3600 +
                           EXTRACT(MINUTE FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 60 +
                           EXTRACT(SECOND FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) >= 60
                      THEN
                             TO_CHAR (
                                 ROUND (
                                     EXTRACT(DAY FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 24 * 60 +
                                     EXTRACT(HOUR FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 60 +
                                     EXTRACT(MINUTE FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)),
                                     0))
                          || 'm'
                      ELSE
                             TO_CHAR (
                                 ROUND (
                                     EXTRACT(DAY FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 24 * 3600 +
                                     EXTRACT(HOUR FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 3600 +
                                     EXTRACT(MINUTE FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)) * 60 +
                                     EXTRACT(SECOND FROM (ash.SAMPLE_TIME - ash.SQL_EXEC_START)),
                                     0))
                          || 's'
                  END
              ELSE
                  'N/A'
          END
              exec_duration,
         CASE
             WHEN ash.SESSION_STATE = 'WAITING' THEN SUBSTR (ash.EVENT, 0, 15)
             WHEN ash.SESSION_STATE = 'ON CPU' THEN 'ON CPU'
             ELSE ash.SESSION_STATE
         END
             event,
         SUBSTR (ash.PROGRAM, 0, 10)                                   program,
         ROUND (ash.TM_DELTA_DB_TIME / NULLIF (ash.TM_DELTA_TIME, 0), 2) "DB%",
         ROUND (ash.TM_DELTA_CPU_TIME / NULLIF (ash.TM_DELTA_TIME, 0), 2) "CPU%",
         CASE
             WHEN   (ash.DELTA_READ_IO_REQUESTS + ash.DELTA_WRITE_IO_REQUESTS)
                  / NULLIF (ash.DELTA_TIME, 0) >= 10000
             THEN
                    TO_CHAR (
                        ROUND (
                              (  ash.DELTA_READ_IO_REQUESTS
                               + ash.DELTA_WRITE_IO_REQUESTS)
                            / NULLIF (ash.DELTA_TIME, 0)
                            / 10000,
                            0))
                 || 'W'
             WHEN   (ash.DELTA_READ_IO_REQUESTS + ash.DELTA_WRITE_IO_REQUESTS)
                  / NULLIF (ash.DELTA_TIME, 0) >= 1000
             THEN
                    TO_CHAR (
                        ROUND (
                              (  ash.DELTA_READ_IO_REQUESTS
                               + ash.DELTA_WRITE_IO_REQUESTS)
                            / NULLIF (ash.DELTA_TIME, 0)
                            / 1000,
                            0))
                 || 'K'
             ELSE
                 TO_CHAR (
                     ROUND (
                           (  ash.DELTA_READ_IO_REQUESTS
                            + ash.DELTA_WRITE_IO_REQUESTS)
                         / NULLIF (ash.DELTA_TIME, 0),
                         0))
         END
             IOPS,
         CASE
             WHEN   (ash.DELTA_READ_IO_BYTES + ash.DELTA_WRITE_IO_BYTES)
                  / NULLIF (ash.DELTA_TIME, 0) >= 1024 * 1024 * 1024
             THEN
                    TO_CHAR (
                        ROUND (
                              (  ash.DELTA_READ_IO_BYTES
                               + ash.DELTA_WRITE_IO_BYTES)
                            / NULLIF (ash.DELTA_TIME, 0)
                            / (1024 * 1024 * 1024),
                            0))
                 || 'GB'
             WHEN   (ash.DELTA_READ_IO_BYTES + ash.DELTA_WRITE_IO_BYTES)
                  / NULLIF (ash.DELTA_TIME, 0) >= 1024 * 1024
             THEN
                    TO_CHAR (
                        ROUND (
                              (  ash.DELTA_READ_IO_BYTES
                               + ash.DELTA_WRITE_IO_BYTES)
                            / NULLIF (ash.DELTA_TIME, 0)
                            / (1024 * 1024),
                            0))
                 || 'MB'
             WHEN   (ash.DELTA_READ_IO_BYTES + ash.DELTA_WRITE_IO_BYTES)
                  / NULLIF (ash.DELTA_TIME, 0) >= 1024
             THEN
                    TO_CHAR (
                        ROUND (
                              (  ash.DELTA_READ_IO_BYTES
                               + ash.DELTA_WRITE_IO_BYTES)
                            / NULLIF (ash.DELTA_TIME, 0)
                            / 1024,
                            0))
                 || 'KB'
             ELSE
                    TO_CHAR (
                        ROUND (
                              (  ash.DELTA_READ_IO_BYTES
                               + ash.DELTA_WRITE_IO_BYTES)
                            / NULLIF (ash.DELTA_TIME, 0),
                            0))
                 || 'B'
         END
             MBPS,
         CASE
             WHEN ash.DELTA_READ_MEM_BYTES / NULLIF (ash.DELTA_TIME, 0) >=
                      1024 * 1024 * 1024
             THEN
                    TO_CHAR (
                        ROUND (
                              ash.DELTA_READ_MEM_BYTES
                            / NULLIF (ash.DELTA_TIME, 0)
                            / (1024 * 1024 * 1024),
                            0))
                 || 'GB'
             WHEN ash.DELTA_READ_MEM_BYTES / NULLIF (ash.DELTA_TIME, 0) >=
                      1024 * 1024
             THEN
                    TO_CHAR (
                        ROUND (
                              ash.DELTA_READ_MEM_BYTES
                            / NULLIF (ash.DELTA_TIME, 0)
                            / (1024 * 1024),
                            0))
                 || 'MB'
             WHEN ash.DELTA_READ_MEM_BYTES / NULLIF (ash.DELTA_TIME, 0) >= 1024
             THEN
                    TO_CHAR (
                        ROUND (
                              ash.DELTA_READ_MEM_BYTES
                            / NULLIF (ash.DELTA_TIME, 0)
                            / 1024,
                            0))
                 || 'KB'
             ELSE
                    TO_CHAR (
                        ROUND (
                              ash.DELTA_READ_MEM_BYTES
                            / NULLIF (ash.DELTA_TIME, 0),
                            0))
                 || 'B'
         END
             LOGICAL,
         CASE
             WHEN ash.PGA_ALLOCATED >= 1024 * 1024 * 1024
             THEN
                    TO_CHAR (
                        ROUND (ash.PGA_ALLOCATED / (1024 * 1024 * 1024), 0))
                 || 'GB'
             WHEN ash.PGA_ALLOCATED >= 1024 * 1024
             THEN
                 TO_CHAR (ROUND (ash.PGA_ALLOCATED / (1024 * 1024), 0)) || 'MB'
             WHEN ash.PGA_ALLOCATED >= 1024
             THEN
                 TO_CHAR (ROUND (ash.PGA_ALLOCATED / 1024, 0)) || 'KB'
             ELSE
                 TO_CHAR (ash.PGA_ALLOCATED) || 'B'
         END
             PGA_ALLOCATED,
         CASE
             WHEN ash.TEMP_SPACE_ALLOCATED >= 1024 * 1024 * 1024
             THEN
                    TO_CHAR (
                        ROUND (ash.TEMP_SPACE_ALLOCATED / (1024 * 1024 * 1024),
                               0))
                 || 'GB'
             WHEN ash.TEMP_SPACE_ALLOCATED >= 1024 * 1024
             THEN
                    TO_CHAR (
                        ROUND (ash.TEMP_SPACE_ALLOCATED / (1024 * 1024), 0))
                 || 'MB'
             WHEN ash.TEMP_SPACE_ALLOCATED >= 1024
             THEN
                 TO_CHAR (ROUND (ash.TEMP_SPACE_ALLOCATED / 1024, 0)) || 'KB'
             ELSE
                 TO_CHAR (ash.TEMP_SPACE_ALLOCATED) || 'B'
         END
             TEMP_ALLOCATED,
         CASE
             WHEN ash.CURRENT_OBJ# IS NOT NULL
             THEN
                    NVL (OBJ_OWNER.OWNER, 'UNKNOWN')
                 || '.'
                 || NVL (OBJ_OWNER.OBJECT_NAME, 'UNKNOWN')
                 || '|'
                 || ash.CURRENT_OBJ#
                 || ':'
                 || ash.CURRENT_FILE#
                 || ':'
                 || ash.CURRENT_BLOCK#
             ELSE
                    ash.CURRENT_OBJ#
                 || ':'
                 || ash.CURRENT_FILE#
                 || ':'
                 || ash.CURRENT_BLOCK#
         END
             obj
&_P_MODE             ,P1TEXT||':'||P2TEXT||':'||P3TEXT PTEXT
&_PLSQL_MODE         ,CASE
&_PLSQL_MODE             WHEN ash.PLSQL_OBJECT_ID IS NOT NULL
&_PLSQL_MODE             THEN
&_PLSQL_MODE                    NVL (PLSQL_OWNER.OWNER, 'UNKNOWN')
&_PLSQL_MODE                 || '.'
&_PLSQL_MODE                 || NVL (PLSQL_OWNER.OBJECT_NAME, 'UNKNOWN')
&_PLSQL_MODE             ELSE
&_PLSQL_MODE                 'N/A'
&_PLSQL_MODE         END||':'||
&_PLSQL_MODE         CASE
&_PLSQL_MODE             WHEN ash.PLSQL_SUBPROGRAM_ID IS NOT NULL
&_PLSQL_MODE             THEN
&_PLSQL_MODE                    NVL (PLSQL_SUB.OWNER, 'UNKNOWN')
&_PLSQL_MODE                 || '.'
&_PLSQL_MODE                 || NVL (PLSQL_SUB.OBJECT_NAME, 'UNKNOWN')
&_PLSQL_MODE                 || '.'
&_PLSQL_MODE                 || NVL (PLSQL_SUB.PROCEDURE_NAME, 'UNKNOWN')
&_PLSQL_MODE             ELSE
&_PLSQL_MODE                 'N/A'
&_PLSQL_MODE         END
&_PLSQL_MODE             plsql
    FROM ash_data ash
         LEFT JOIN DBA_USERS U ON ash.USER_ID = U.USER_ID
         LEFT JOIN DBA_OBJECTS PLSQL_OWNER
             ON ash.PLSQL_OBJECT_ID = PLSQL_OWNER.OBJECT_ID
         LEFT JOIN DBA_PROCEDURES PLSQL_SUB
             ON ash.PLSQL_SUBPROGRAM_ID = PLSQL_SUB.OBJECT_ID
         LEFT JOIN DBA_OBJECTS OBJ_OWNER
             ON ash.CURRENT_OBJ# = OBJ_OWNER.OBJECT_ID
ORDER BY ash.SAMPLE_TIME;

CLEAR COLUMNS
