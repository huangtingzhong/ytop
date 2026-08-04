-- File Name: sql_sqlmap_by_sqlid.sql
-- Purpose: sql.sql-style v$sql/AWR plus SYS.SQL_MAP$ map_name by hash
-- Created: 20260803  by  huangtingzhong
--
-- Usage: ytop/yasql -f sql_sqlmap_by_sqlid.sql
--   blank   : v$sql rows covered by SQLMAP only (hash match); AWR returns 0
--   <sql_id>: same metrics as sql.sql for that sql_id, with map_name
--
-- Note: SQL_MAP$ has HASH_VALUE (no SQL_ID). v$sql cover = hash match.
--       AWR has no hash_value; map_name via live gv$sql hash and/or MAP_<sql_id>_%.

SET HEADING ON
SET SERVEROUTPUT ON

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | Enter sql_id (blank = list SQLMAP-covered v$sql only)                  |
PROMPT +------------------------------------------------------------------------+
PROMPT

ACCEPT sqlid PROMPT 'Enter sqlid (blank=list covered cursors): '

col EXEC                   for   a8
col CPU_P_E                for   a10
col ELA_P_E                for   a10
col DISK_P_E               for   a10
col GET_P_E                for   a10
col ROWS_P_E               for   a10
col ROWS_P_F               for   a10
col IO_W_P                 for   a10
col PLSQL_W_P              for   a10
col F_L_TIME               for   a15
col USERNAME               for   a15
col C                      for   a3
col PHV                    for   a12
col IOW_P_E                for   a10
col WRITE_P_E              for   a10
col i                      for   a1
col SORTS_P_E              for   a10
col END_TIME               for   a5
col MAP_NAME               for   a50

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | information from v$sql                 |
PROMPT +------------------------------------------------------------------------+
PROMPT

SELECT
    CASE
        WHEN s.EXECUTIONS < 1000 THEN TO_CHAR(s.EXECUTIONS)
        WHEN s.EXECUTIONS < 10000 THEN TO_CHAR(ROUND(s.EXECUTIONS / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(s.EXECUTIONS / 10000, 2)) || 'W'
    END AS EXEC,
    s.PLAN_HASH_VALUE || '' AS PHV,
    s.child_number || '' AS c,
    s.PARSING_SCHEMA_NAME AS username,
    SUBSTR(m.name, 1, 50) AS map_name,
    CASE
        WHEN s.CPU_TIME IS NULL THEN NULL
        WHEN s.CPU_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 < 1000
            THEN ROUND(s.CPU_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000, 2) || 'ms'
        WHEN s.CPU_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 < 60
            THEN ROUND(s.CPU_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000, 2) || 's'
        WHEN s.CPU_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60 < 60
            THEN ROUND(s.CPU_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60, 2) || 'm'
        ELSE ROUND(s.CPU_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60 / 60, 2) || 'h'
    END AS CPU_P_E,
    CASE
        WHEN s.ELAPSED_TIME IS NULL THEN NULL
        WHEN s.ELAPSED_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 < 1000
            THEN ROUND(s.ELAPSED_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000, 2) || 'ms'
        WHEN s.ELAPSED_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 < 60
            THEN ROUND(s.ELAPSED_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000, 2) || 's'
        WHEN s.ELAPSED_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60 < 60
            THEN ROUND(s.ELAPSED_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60, 2) || 'm'
        ELSE ROUND(s.ELAPSED_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60 / 60, 2) || 'h'
    END AS ELA_P_E,
    CASE
        WHEN s.DISK_READS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) < 1000
            THEN TO_CHAR(ROUND(s.DISK_READS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS), 2))
        WHEN s.DISK_READS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) < 10000
            THEN TO_CHAR(ROUND(s.DISK_READS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(s.DISK_READS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 10000, 2)) || 'W'
    END AS DISK_P_E,
    CASE
        WHEN s.BUFFER_GETS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) < 1000
            THEN TO_CHAR(ROUND(s.BUFFER_GETS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS), 2))
        WHEN s.BUFFER_GETS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) < 10000
            THEN TO_CHAR(ROUND(s.BUFFER_GETS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(s.BUFFER_GETS / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 10000, 2)) || 'W'
    END AS GET_P_E,
    CASE
        WHEN s.ROWS_PROCESSED / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) < 1000
            THEN TO_CHAR(ROUND(s.ROWS_PROCESSED / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS), 2))
        WHEN s.ROWS_PROCESSED / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) < 10000
            THEN TO_CHAR(ROUND(s.ROWS_PROCESSED / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(s.ROWS_PROCESSED / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 10000, 2)) || 'W'
    END AS ROWS_P_E,
    CASE
        WHEN s.ROWS_PROCESSED / DECODE(s.FETCHES, 0, 1, s.FETCHES) < 1000
            THEN TO_CHAR(ROUND(s.ROWS_PROCESSED / DECODE(s.FETCHES, 0, 1, s.FETCHES), 2))
        WHEN s.ROWS_PROCESSED / DECODE(s.FETCHES, 0, 1, s.FETCHES) < 10000
            THEN TO_CHAR(ROUND(s.ROWS_PROCESSED / DECODE(s.FETCHES, 0, 1, s.FETCHES) / 1000, 2)) || 'K'
        ELSE TO_CHAR(ROUND(s.ROWS_PROCESSED / DECODE(s.FETCHES, 0, 1, s.FETCHES) / 10000, 2)) || 'W'
    END AS ROWS_P_F,
    CASE
        WHEN s.USER_IO_WAIT_TIME IS NULL THEN NULL
        WHEN s.USER_IO_WAIT_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 < 1000
            THEN ROUND(s.USER_IO_WAIT_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000, 2) || 'ms'
        WHEN s.USER_IO_WAIT_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 < 60
            THEN ROUND(s.USER_IO_WAIT_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000, 2) || 's'
        WHEN s.USER_IO_WAIT_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60 < 60
            THEN ROUND(s.USER_IO_WAIT_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60, 2) || 'm'
        ELSE ROUND(s.USER_IO_WAIT_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60 / 60, 2) || 'h'
    END AS IO_W_P,
    CASE
        WHEN s.PLSQL_EXEC_TIME IS NULL THEN NULL
        WHEN s.PLSQL_EXEC_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 < 1000
            THEN ROUND(s.PLSQL_EXEC_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000, 2) || 'ms'
        WHEN s.PLSQL_EXEC_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 < 60
            THEN ROUND(s.PLSQL_EXEC_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000, 2) || 's'
        WHEN s.PLSQL_EXEC_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60 < 60
            THEN ROUND(s.PLSQL_EXEC_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60, 2) || 'm'
        ELSE ROUND(s.PLSQL_EXEC_TIME / DECODE(s.EXECUTIONS, 0, 1, s.EXECUTIONS) / 1000 / 1000 / 60 / 60, 2) || 'h'
    END AS PLSQL_W_P,
    SUBSTR(s.FIRST_LOAD_TIME, 6, 10) || '.' || SUBSTR(s.LAST_LOAD_TIME, 6, 10) AS f_l_time
  FROM v$sql s
  LEFT JOIN SYS.SQL_MAP$ m
    ON m.hash_value = s.hash_value
 WHERE (
         NULLIF(TRIM('&&sqlid'), '') IS NULL
         AND m.name IS NOT NULL
       )
    OR (
         NULLIF(TRIM('&&sqlid'), '') IS NOT NULL
         AND s.sql_id = TRIM('&&sqlid')
       )
 ORDER BY s.plan_hash_value, s.child_number
/

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | information from awr (END_INTERVAL_TIME > SYSDATE-5)                  |
PROMPT +------------------------------------------------------------------------+
PROMPT

SELECT TO_CHAR(b.END_INTERVAL_TIME, 'dd hh24') AS end_time,
       TRIM(a.instance_number) AS i,
       a.parsing_schema_name AS username,
       a.plan_hash_value || '' AS PHV,
       CASE
         WHEN a.executions_delta < 1000 THEN TO_CHAR(a.executions_delta)
         WHEN a.executions_delta < 10000 THEN TO_CHAR(ROUND(a.executions_delta / 1000, 2)) || 'K'
         ELSE TO_CHAR(ROUND(a.executions_delta / 10000, 2)) || 'W'
       END AS EXEC,
       (SELECT SUBSTR(MAX(m.name), 1, 50)
          FROM SYS.SQL_MAP$ m
         WHERE m.hash_value IN (
                 SELECT g.hash_value FROM gv$sql g WHERE g.sql_id = a.sql_id
               )
            OR UPPER(m.name) LIKE 'MAP_' || UPPER(a.sql_id) || '_%') AS map_name,
       CASE
         WHEN a.cpu_time_delta IS NULL THEN NULL
         WHEN a.cpu_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 < 1000
           THEN ROUND(a.cpu_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2) || 'ms'
         WHEN a.cpu_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 < 60
           THEN ROUND(a.cpu_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000, 2) || 's'
         WHEN a.cpu_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60 < 60
           THEN ROUND(a.cpu_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60, 2) || 'm'
         ELSE ROUND(a.cpu_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60 / 60, 2) || 'h'
       END AS CPU_P_E,
       CASE
         WHEN a.elapsed_time_delta IS NULL THEN NULL
         WHEN a.elapsed_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 < 1000
           THEN ROUND(a.elapsed_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2) || 'ms'
         WHEN a.elapsed_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 < 60
           THEN ROUND(a.elapsed_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000, 2) || 's'
         WHEN a.elapsed_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60 < 60
           THEN ROUND(a.elapsed_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60, 2) || 'm'
         ELSE ROUND(a.elapsed_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60 / 60, 2) || 'h'
       END AS ELA_P_E,
       CASE
         WHEN a.disk_reads_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 1000
           THEN TO_CHAR(ROUND(a.disk_reads_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta), 2))
         WHEN a.disk_reads_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 10000
           THEN TO_CHAR(ROUND(a.disk_reads_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2)) || 'K'
         ELSE TO_CHAR(ROUND(a.disk_reads_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 10000, 2)) || 'W'
       END AS DISK_P_E,
       CASE
         WHEN a.BUFFER_GETS_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 1000
           THEN TO_CHAR(ROUND(a.BUFFER_GETS_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta), 2))
         WHEN a.BUFFER_GETS_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 10000
           THEN TO_CHAR(ROUND(a.BUFFER_GETS_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2)) || 'K'
         ELSE TO_CHAR(ROUND(a.BUFFER_GETS_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 10000, 2)) || 'W'
       END AS GET_P_E,
       CASE
         WHEN a.rows_processed_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 1000
           THEN TO_CHAR(ROUND(a.rows_processed_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta), 2))
         WHEN a.rows_processed_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 10000
           THEN TO_CHAR(ROUND(a.rows_processed_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2)) || 'K'
         ELSE TO_CHAR(ROUND(a.rows_processed_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 10000, 2)) || 'W'
       END AS ROWS_P_E,
       CASE
         WHEN a.fetches_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 1000
           THEN TO_CHAR(ROUND(a.fetches_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta), 2))
         WHEN a.fetches_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 10000
           THEN TO_CHAR(ROUND(a.fetches_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2)) || 'K'
         ELSE TO_CHAR(ROUND(a.fetches_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 10000, 2)) || 'W'
       END AS ROWS_P_F,
       CASE
         WHEN a.direct_writes_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 1000
           THEN TO_CHAR(ROUND(a.direct_writes_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta), 2))
         WHEN a.direct_writes_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 10000
           THEN TO_CHAR(ROUND(a.direct_writes_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2)) || 'K'
         ELSE TO_CHAR(ROUND(a.direct_writes_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 10000, 2)) || 'W'
       END AS WRITE_P_E,
       CASE
         WHEN a.IOWAIT_DELTA IS NULL THEN NULL
         WHEN a.IOWAIT_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 < 1000
           THEN ROUND(a.IOWAIT_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2) || 'ms'
         WHEN a.IOWAIT_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 < 60
           THEN ROUND(a.IOWAIT_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000, 2) || 's'
         WHEN a.IOWAIT_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60 < 60
           THEN ROUND(a.IOWAIT_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60, 2) || 'm'
         ELSE ROUND(a.IOWAIT_DELTA / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60 / 60, 2) || 'h'
       END AS IOW_P_E,
       CASE
         WHEN a.sorts_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 1000
           THEN TO_CHAR(ROUND(a.sorts_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta), 2))
         WHEN a.sorts_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) < 10000
           THEN TO_CHAR(ROUND(a.sorts_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2)) || 'K'
         ELSE TO_CHAR(ROUND(a.sorts_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 10000, 2)) || 'W'
       END AS SORTS_P_E,
       CASE
         WHEN a.plsexec_time_delta IS NULL THEN NULL
         WHEN a.plsexec_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 < 1000
           THEN ROUND(a.plsexec_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000, 2) || 'ms'
         WHEN a.plsexec_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 < 60
           THEN ROUND(a.plsexec_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000, 2) || 's'
         WHEN a.plsexec_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60 < 60
           THEN ROUND(a.plsexec_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60, 2) || 'm'
         ELSE ROUND(a.plsexec_time_delta / DECODE(a.executions_delta, 0, 1, a.executions_delta) / 1000 / 1000 / 60 / 60, 2) || 'h'
       END AS PLSQL_W_P
  FROM WRH$_SQLSTAT a, WRM$_SNAPSHOT b
 WHERE NULLIF(TRIM('&&sqlid'), '') IS NOT NULL
   AND a.sql_id = TRIM('&&sqlid')
   AND a.snap_id = b.snap_id
   AND b.END_INTERVAL_TIME > SYSDATE - 5
   AND a.instance_number = b.instance_number
 ORDER BY 1
/
