-- File Name: user_role.sql
-- Purpose: Oracle User Role
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set lines 170
set pages 1000
col grantee for a40
col granted_role for a40
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display one user role info include Recursive                           |
PROMPT +------------------------------------------------------------------------+ 
PROMPT

ACCEPT username prompt 'Enter Search User Name (i.e. SCOTT) : '
    SELECT distinct grantee,granted_role,ADMIN_OPTION,default_role,LEVEL
      FROM DBA_role_PRIVS
START WITH grantee = upper('&username')
CONNECT BY PRIOR granted_role= grantee  order by level,grantee
/
