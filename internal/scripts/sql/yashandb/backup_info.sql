-- File Name: backup_info.sql
-- Purpose: Collect SQL backup sets and progress info
-- Supported: 23.4
-- Created: 20260706  by  huangtingzhong
--
-- SQL BACKUP DATABASE / BACKUP ARCHIVELOG metadata only (DBA_* views).
-- yasrman catalog backups: use "yasrman -c LIST BACKUP -D <catalog>".
-- Ref: DBA_BACKUP_SET, DBA_ARCHIVE_BACKUPSET, V$BACKUP_PROGRESS, V$ARCHIVED_LOG.

SET SERVEROUTPUT OFF
SET VERIFY OFF
SET FEEDBACK OFF

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | Backup information report (SQL backup views)                           |
PROMPT | Note: yasrman catalog is NOT included; use LIST BACKUP separately.   |
PROMPT +------------------------------------------------------------------------+
PROMPT

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | 0. Summary (at a glance)                                               |
PROMPT +------------------------------------------------------------------------+
PROMPT

col log_mode       for a12
col db_role        for a15
col db_bak_cnt     for a8
col arch_bak_cnt   for a8
col df_bak_cnt     for a8
col latest_db_bak  for a26
col latest_arch    for a26
col progress       for a12
col arch_files     for a10

WITH db_bak AS (
  SELECT COUNT(*) AS cnt,
         MAX(start_time) AS latest_start
    FROM dba_backup_set
),
arch_bak AS (
  SELECT COUNT(*) AS cnt,
         MAX(start_time) AS latest_start
    FROM dba_archive_backupset
),
df_bak AS (
  SELECT COUNT(*) AS cnt
    FROM dba_datafile_backupset
),
arch_log AS (
  SELECT COUNT(*) AS cnt
    FROM v$archived_log
),
prog AS (
  SELECT type, total_progress
    FROM v$backup_progress
)
SELECT d.log_mode,
       d.database_role AS db_role,
       TO_CHAR(db_bak.cnt) AS db_bak_cnt,
       TO_CHAR(arch_bak.cnt) AS arch_bak_cnt,
       TO_CHAR(df_bak.cnt) AS df_bak_cnt,
       CASE WHEN db_bak.latest_start IS NULL THEN '-'
            ELSE TO_CHAR(db_bak.latest_start, 'YYYY-MM-DD HH24:MI:SS')
       END AS latest_db_bak,
       CASE WHEN arch_bak.latest_start IS NULL THEN '-'
            ELSE TO_CHAR(arch_bak.latest_start, 'YYYY-MM-DD HH24:MI:SS')
       END AS latest_arch,
       NVL(prog.type, 'NONE')
         || CASE WHEN prog.type IN ('BACKUP', 'RESTORE')
                 THEN ' ' || TO_CHAR(prog.total_progress) || '%'
                 ELSE '' END AS progress,
       TO_CHAR(arch_log.cnt) AS arch_files
  FROM v$database d
 CROSS JOIN db_bak
 CROSS JOIN arch_bak
 CROSS JOIN df_bak
 CROSS JOIN arch_log
 CROSS JOIN prog;

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | 1. Database status (V$DATABASE)                                       |
PROMPT +------------------------------------------------------------------------+
PROMPT

col host_name      for a20
col db_name        for a15
col open_mode      for a12
col flashback_on   for a12
col curr_scn       for a22
col db_time        for a26

SELECT d.host_name,
       d.database_name AS db_name,
       d.log_mode,
       d.open_mode,
       d.flashback_on,
       d.database_role AS db_role,
       TO_CHAR(d.current_scn) AS curr_scn,
       TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF6') AS db_time
  FROM v$database d;

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | 2. Backup/restore progress (V$BACKUP_PROGRESS)                         |
PROMPT |    TOTAL_PROGRESS is estimated; see run.log for detail.                 |
PROMPT +------------------------------------------------------------------------+
PROMPT

col prog_type      for a10
col prog_stage     for a18
col stage_pct      for a10
col total_pct      for a10
col elapsed_sec    for a12
col in_size        for a12
col out_size       for a12
col compress_pct   for a10
col start_time     for a26
col end_time       for a26

SELECT p.type AS prog_type,
       p.stage AS prog_stage,
       TO_CHAR(p.stage_progress) AS stage_pct,
       TO_CHAR(p.total_progress) AS total_pct,
       TO_CHAR(p.elapsed_time) AS elapsed_sec,
       CASE
         WHEN p.input_bytes >= 1073741824
           THEN TO_CHAR(ROUND(p.input_bytes / 1073741824, 2)) || ' GB'
         WHEN p.input_bytes >= 1048576
           THEN TO_CHAR(ROUND(p.input_bytes / 1048576, 1)) || ' MB'
         ELSE TO_CHAR(NVL(p.input_bytes, 0)) || ' B'
       END AS in_size,
       CASE
         WHEN p.output_bytes >= 1073741824
           THEN TO_CHAR(ROUND(p.output_bytes / 1073741824, 2)) || ' GB'
         WHEN p.output_bytes >= 1048576
           THEN TO_CHAR(ROUND(p.output_bytes / 1048576, 1)) || ' MB'
         ELSE TO_CHAR(NVL(p.output_bytes, 0)) || ' B'
       END AS out_size,
       TO_CHAR(p.compression_ratio) AS compress_pct,
       TO_CHAR(p.start_time, 'YYYY-MM-DD HH24:MI:SS.FF6') AS start_time,
       TO_CHAR(p.end_time, 'YYYY-MM-DD HH24:MI:SS.FF6') AS end_time
  FROM v$backup_progress p;

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | 3. Database backup sets (DBA_BACKUP_SET)                               |
PROMPT |    (no rows = no BACKUP DATABASE via SQL on this database)             |
PROMPT +------------------------------------------------------------------------+
PROMPT

col recid          for a6
col bak_type       for a12
col incr_lvl       for a6
col incr_id        for a6
col tag            for a28
col path           for a55
col start_time     for a26
col complete_time  for a26
col in_bytes       for a12
col out_bytes      for a12
col trunc_lsn      for a14
col default_base   for a12
col bs_status      for a10

SELECT TO_CHAR(b.recid#) AS recid,
       b.type AS bak_type,
       TO_CHAR(b.increment_level) AS incr_lvl,
       TO_CHAR(b.increment_id#) AS incr_id,
       b.tag,
       b.path,
       TO_CHAR(b.start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
       TO_CHAR(b.completion_time, 'YYYY-MM-DD HH24:MI:SS') AS complete_time,
       CASE
         WHEN b.input_bytes >= 1048576
           THEN TO_CHAR(ROUND(b.input_bytes / 1048576, 1)) || ' MB'
         ELSE TO_CHAR(NVL(b.input_bytes, 0)) || ' B'
       END AS in_bytes,
       CASE
         WHEN b.output_bytes >= 1048576
           THEN TO_CHAR(ROUND(b.output_bytes / 1048576, 1)) || ' MB'
         ELSE TO_CHAR(NVL(b.output_bytes, 0)) || ' B'
       END AS out_bytes,
       TO_CHAR(b.trunc_lsn) AS trunc_lsn,
       CASE WHEN b.default_base THEN 'TRUE' ELSE 'FALSE' END AS default_base,
       b.bs_status
  FROM dba_backup_set b
 ORDER BY b.start_time DESC;

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | 4. Archive log backup sets (DBA_ARCHIVE_BACKUPSET)                     |
PROMPT +------------------------------------------------------------------------+
PROMPT

col inst_num       for a4
col seq_begin      for a10
col seq_end        for a10
col scn_begin      for a22
col scn_end        for a22
col compress_algo  for a10
col encrypt_algo   for a10

SELECT TO_CHAR(a.recid#) AS recid,
       TO_CHAR(a.instance_number#) AS inst_num,
       a.type AS bak_type,
       a.tag,
       a.path,
       TO_CHAR(a.start_time, 'YYYY-MM-DD HH24:MI:SS') AS start_time,
       TO_CHAR(a.completion_time, 'YYYY-MM-DD HH24:MI:SS') AS complete_time,
       TO_CHAR(a.sequence_begin#) AS seq_begin,
       TO_CHAR(a.sequence_end#) AS seq_end,
       TO_CHAR(a.min_first_change#) AS scn_begin,
       TO_CHAR(a.max_next_change#) AS scn_end,
       CASE
         WHEN a.input_bytes >= 1048576
           THEN TO_CHAR(ROUND(a.input_bytes / 1048576, 1)) || ' MB'
         ELSE TO_CHAR(NVL(a.input_bytes, 0)) || ' B'
       END AS in_bytes,
       CASE
         WHEN a.output_bytes >= 1048576
           THEN TO_CHAR(ROUND(a.output_bytes / 1048576, 1)) || ' MB'
         ELSE TO_CHAR(NVL(a.output_bytes, 0)) || ' B'
       END AS out_bytes,
       a.compress_algo,
       a.encrypt_algo,
       a.bs_status
  FROM dba_archive_backupset a
 ORDER BY a.start_time DESC;

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | 5. Datafile backup summary (DBA_DATAFILE_BACKUPSET by BS_KEY)          |
PROMPT +------------------------------------------------------------------------+
PROMPT

col bs_key         for a8
col file_cnt       for a8
col total_in       for a12
col total_out      for a12

SELECT TO_CHAR(d.bs_key) AS bs_key,
       TO_CHAR(COUNT(*)) AS file_cnt,
       CASE
         WHEN SUM(d.input_bytes) >= 1048576
           THEN TO_CHAR(ROUND(SUM(d.input_bytes) / 1048576, 1)) || ' MB'
         ELSE TO_CHAR(SUM(NVL(d.input_bytes, 0))) || ' B'
       END AS total_in,
       CASE
         WHEN SUM(d.output_bytes) >= 1048576
           THEN TO_CHAR(ROUND(SUM(d.output_bytes) / 1048576, 1)) || ' MB'
         ELSE TO_CHAR(SUM(NVL(d.output_bytes, 0))) || ' B'
       END AS total_out
  FROM dba_datafile_backupset d
 GROUP BY d.bs_key
 ORDER BY d.bs_key DESC;

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | 6. Online archived redo files (V$ARCHIVED_LOG, not backup sets)        |
PROMPT +------------------------------------------------------------------------+
PROMPT

col sequence_num   for a8
col thread_num     for a4
col first_scn      for a22
col next_scn       for a22
col first_time     for a26
col name           for a55

SELECT TO_CHAR(a.sequence#) AS sequence_num,
       TO_CHAR(a.thread#) AS thread_num,
       TO_CHAR(a.first_change#) AS first_scn,
       TO_CHAR(a.next_change#) AS next_scn,
       TO_CHAR(a.first_time, 'YYYY-MM-DD HH24:MI:SS.FF6') AS first_time,
       a.name
  FROM v$archived_log a
 ORDER BY a.thread#, a.sequence# DESC;

PROMPT
PROMPT --- End of backup report (SQL views only) ---
PROMPT --- yasrman: yasrman ... -c "LIST BACKUP" -D <catalog_dir> ---
