-- File Name: user.sql
-- Purpose: Oracle Show database users and profiles
-- Created: 20260516  by  huangtingzhong

set lines 200
set echo off
set verify off
set pages 1000
col username for a25;
col password for a17
col detb for a15 heading 'Default|Tablespace';
col tetb for a10 heading 'Temporary|Tablespace';
col crtime for a10 heading 'Create|Time';
col status for a17;
col profile for a25;
col failed for 99999 heading 'FAILED|LOGIN'
col locktime for a10 heading 'Lock|Time';
col expiretime for a10 heading 'Expire|Time';
set pages 200;
col limit for a15;
SELECT a.username,
       b.password,
       a.account_status status,
       b.lcount failed,
       a.default_tablespace detb,
       a.temporary_tablespace tetb,
       a.Profile,
       TO_CHAR (a.Created, 'MM-DD hh24') CRTIME,
       TO_CHAR (a.lock_date, 'mm-dd hh24') locktime,
       TO_CHAR (a.expiry_date, 'mm-dd hh24') expiretime
  FROM dba_users a,sys.user$ b
 WHERE a.username =
          DECODE (UPPER ('&username'),
                  'ALL', a.username,
                  UPPER ('&username'))
       AND a.username=b.name
 order by status
/
