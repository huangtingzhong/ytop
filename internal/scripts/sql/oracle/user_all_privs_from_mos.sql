-- File Name: user_all_privs_from_mos.sql
-- Purpose: Oracle User All Privs From Mos
-- Created: 20260516  by  huangtingzhong

set linesize 30
column role_name format a5
column priv format a60
set verify off
accept username char prompt 'Type the name of the user '

select '(object priv) '||privilege||' on '||owner||'.'||table_name||decode(grantable,'YES',' WITH GRANT OPTION','') priv , 'Granted directly ' role_name from dba_tab_privs where grantee in (upper('&username'))
union all
select '(object priv) '||privilege||' on '||owner||'.'||table_name||decode(grantable,'YES',' WITH GRANT OPTION','') priv , grantee role_name from dba_tab_privs where grantee in (select granted_role from dba_role_privs start with grantee=upper('&username') connect by prior granted_role=grantee)
union all
select '(system priv) '||privilege priv , 'Granted directly' role_name from dba_sys_privs where grantee in (upper('&username'))
union all
select '(system priv) '||privilege priv , grantee role_name from dba_sys_privs where grantee in (select granted_role from dba_role_privs start with grantee=upper('&username') connect by prior granted_role=grantee)
union all
select '(role without privs)' priv, granted_role from (select granted_role from dba_role_privs start with grantee=upper('&username') connect by prior granted_role=grantee) where granted_role not in (select grantee from dba_tab_privs union all select grantee from dba_sys_privs)
/