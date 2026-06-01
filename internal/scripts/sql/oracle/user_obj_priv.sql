-- File Name: user_obj_priv.sql
-- Purpose: Oracle User object privileges
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set lines 170
set pages 1000
col username for a20
col grantee for a20
col PRIVILEGE for a20
col GRANTOR for a20
col granted_role for a40
col admin_option for a6 heading 'ADMIN|OPTION'
undefine grantee_username;
undefine objectname;

PROMPT | display one user user object privs                                     |

select * from dba_tab_privs a          where  (a.grantee = UPPER ('&&grantee_username')
       OR a.grantee IN  ( SELECT DISTINCT b.grantee
                              FROM DBA_role_PRIVS b
                        START WITH b.grantee = UPPER ('&&grantee_username')
                        CONNECT BY PRIOR b.granted_role = grantee)) and a.table_name =nvl(upper('&objectname'),a.table_name)
/

PROMPT | display one user column object privs                                   |


select * from dba_col_privs a where ( a.grantee = UPPER ('&&grantee_username')
       OR a.grantee IN  ( SELECT DISTINCT b.grantee
                              FROM DBA_role_PRIVS b
                        START WITH b.grantee = UPPER ('&&grantee_username')
                        CONNECT BY PRIOR b.granted_role = grantee)) and a.table_name=nvl(upper('&objectname'),a.table_name)
/
undefine grantee_username;
undefine objectname;