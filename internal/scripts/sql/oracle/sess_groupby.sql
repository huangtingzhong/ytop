-- File Name: sess_groupby.sql
-- Purpose: Oracle session Groupby
-- Created: 20260516  by  huangtingzhong

set echo off lines 300 pages 10000 verify off heading on
col program for a30
col username for a15
col machine for a30
col module for a20
col action for a20
PROMPT 'INST_ID,PROGRAM,USERNAME,MACHINE,STATUS,SERVER,OSUSER,MODULE,ACTION'
select &&order_column,count(*) from gv$session where type='USER' group by &&order_column order by &&order_column;
undefine order_column