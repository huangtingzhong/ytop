-- File Name: lock_tx_undo.sql
-- Purpose: Oracle Lock Tx Undo
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 3000 pages 50 verify off heading on
col usn for 999999
col slot for 99999999
undefine id1;
select trunc(&&id1/65536) USN,mod(&&id1,65536) slot from dual;
undefine id1;
