-- File Name: user_all_priv.sql
-- Purpose: Oracle Show user roles and object privileges
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 200 pages 10000 verify off heading on
column role_name format a40
column priv format a60 
undefine username; 
select '(object priv) ' || privilege || ' on ' || owner || '.' ||
       table_name || decode(grantable, 'YES', ' WITH GRANT OPTION', '') priv,
       'Granted directly ' role_name
  from dba_tab_privs
 where grantee in (upper('&&username'))
union all
select '(object priv) ' || privilege || ' on ' || owner || '.' ||
       table_name || decode(grantable, 'YES', ' WITH GRANT OPTION', '') priv,
       grantee role_name
  from dba_tab_privs
 where grantee in (select granted_role
                     from dba_role_privs
                    start with grantee = upper('&&username')
                   connect by prior granted_role = grantee)
union all
select '(system priv) ' || privilege priv, 'Granted directly' role_name
  from dba_sys_privs
 where grantee in (upper('&&username'))
union all
select '(system priv) ' || privilege priv, grantee role_name
  from dba_sys_privs
 where grantee in (select granted_role
                     from dba_role_privs
                    start with grantee = upper('&&username')
                   connect by prior granted_role = grantee)
union all
select '(role without privs)' priv, granted_role
  from (select granted_role
          from dba_role_privs
         start with grantee = upper('&&username')
        connect by prior granted_role = grantee)
 where granted_role not in (select grantee
                              from dba_tab_privs
                            union all
                            select grantee
                              from dba_sys_privs)
order by 1,2
;
undefine username; 