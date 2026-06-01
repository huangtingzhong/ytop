-- File Name: user_status_dg.sql
-- Purpose: Oracle User Status Dg
-- Created: 20260516  by  huangtingzhong

set lines 200 pages 10000 heading on
col   username           for  a20
col   CON_ID             for  999
select * from V$RO_USER_ACCOUNT where FAILED_LOGINS>0;
