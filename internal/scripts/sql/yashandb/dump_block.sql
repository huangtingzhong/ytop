-- File Name: dump_block.sql
-- Purpose: YashanDB Dump data block and print trace file path
-- Created: 20251201  by  huangtingzhong

alter system dump datafile &datafile minblock &minblock  maxblock &maxblock;
SELECT value||'/'||SYS_CONTEXT('USERENV', 'DB_NAME')||'_'||to_char(sysdate,'yyyymmdd')||'_'||SYS_CONTEXT('USERENV', 'SID')||'.trc' from v$parameter where name='DIAGNOSTIC_DEST';
