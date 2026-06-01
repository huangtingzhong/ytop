-- File Name: log_archive_dest.sql
-- Purpose: Oracle Log Archive Dest
-- Created: 20260516  by  huangtingzhong

set echo off;
set lines 3000 pages 40
set heading on
set verify off
col dest_name for a20 heading 'DEST_NAME'
col status for a10
col binding for a10
col target for a10 heading 'TARGET|ROLE'
col archiver for a10 heading 'ARCHIVER|PROCESS'
col destination for a25 heading 'DESTINATION'
col log_sequence for 99999999 heading 'LOG|SEQUENCE'
col reopen_secs for 99999 heading 'REOPEN|SECS'
col delay_mins for 99999 heading 'DELAY|MINS'
col process for a10 heading 'PROCESS'
col max_connections for 9999 heading 'MAX|CONN'
col net_timeout for 99999 heading 'NET|TIMEOUT'
col register for a10
col fail_sequence for 99999 heading 'FAIL|SEQ'
col fail_BLOCK for 99999 heading 'FAIL|BLOCK'
col failure_count for 9999 heading 'FAIL|CNT'

PROMPT 'V$ARCHIVE_DEST'
PROMPT '**************'
select dest_name,
       status,
       binding,
       target,
       archiver,
       schedule,
       destination,
       log_sequence,
       reopen_secs,
       delay_mins,
       max_connections,
       net_timeout,
       process,
       register,
       to_char(fail_date, 'hh24:mi:ss') fail_date,
       fail_sequence,
       fail_block,
       failure_count
  from v$archive_dest
 where dest_name in (select upper(name)
                       from v$parameter
                      where name like 'log_archive_dest_%'
                        and isdefault = 'FALSE');

PROMPT 'V$ARCHIVE_DEST_STATUS'
PROMPT '*********************'
col database_mode for a15 heading 'DATABASE|MODE'
col recovery_mode for a25 heading 'RECOVERY|MODE'
col db_unique_name for a10 heading 'UNIQUE|NAME'
col archive for a15 heading 'ARCHIVED|THREAD#-SEQ#'
select dest_name,
       status,
       type,
       database_mode,
       a.RECOVERY_MODE,
       destination,
       db_unique_name,
       ARCHIVED_THREAD#||'.'||ARCHIVED_SEQ# archive,
       gap_status,
       error
  from v$archive_dest_status a
 where dest_name in (select upper(name)
                       from v$parameter
                      where name like 'log_archive_dest_%'
                        and isdefault = 'FALSE');