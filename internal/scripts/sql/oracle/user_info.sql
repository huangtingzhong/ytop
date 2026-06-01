-- File Name: user_info.sql
-- Purpose: Oracle User Info
-- Created: 20260516  by  huangtingzhong

set lines 200
set verify off
set echo off
col username for a10;
col password for a17
col detb for a15;
col tetb for a10;
col crtime for a15;
col status for a15;
col profile for a15;
col locktime for a15;
col expiretime for a15;
set pages 200;
col limit for a15;
set feed off;
col tablespace_name for a20
col unlimited for 999999999999999

accept userid prompt 'Enter username:'

Select username,Password,account_status status,to_char(lock_date,'yyyy-mm-dd') locktime,to_char(expiry_date,'yyyy-mm-dd') expiretime ,default_tablespace detb,
temporary_tablespace tetb,to_char(Created,'YYYY-MM-DD') CRTIME,Profile From dba_users where username=upper('&userid')
/
select a.profile profile,a.RESOURCE_NAME resource_name,a.LIMIT limit from dba_profiles a ,dba_users b where b.username=upper('&&userid') and b.profile=a.profile 
/

select tablespace_name
,      decode(max_bytes, -1, 'unlimited'
,      ceil(max_bytes / 1024 / 1024) || 'M' ) "QUOTA"
from   dba_ts_quotas
where  username = upper('&&userid')
/

select granted_role || ' ' || decode(admin_option, 'NO', '', 'YES', 'with admin option') "ROLE"
from   dba_role_privs
where  grantee = upper('&&userid')
/

select privilege || ' ' || decode(admin_option, 'NO', '', 'YES', 'with admin option') "PRIV"
from   dba_sys_privs
where  grantee = upper('&&userid')
/

undefine user
set verify on
set feedback on
