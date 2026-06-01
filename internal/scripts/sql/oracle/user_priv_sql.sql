-- File Name: user_priv_sql.sql
-- Purpose: Oracle User privileges SQL
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 300 pages 0 heading off;
/* Formatted on 2022/5/26 23:48:13 (QP5 v5.381) */
SELECT    'grant '
       || priv
       || ' on '
       || owner
       || '.'
       || table_name
       || ' to '
       || grantee
       || ' '
       || DECODE (grantable, 'YES', ' WITH GRANT OPTION', '')
       || ';'    ddl
  FROM (  SELECT DISTINCT grantee,
                          owner,
                          table_name,
                          grantable,
                          LISTAGG (privilege, ',')
                              WITHIN GROUP (ORDER BY privilege)
                              OVER (PARTITION BY grantee,
                                                 owner,
                                                 table_name,
                                                 grantable)    priv
            FROM dba_tab_privs
           WHERE grantee IN (UPPER (upper('&username')))
        ORDER BY grantee, owner, table_name)
UNION ALL
SELECT    'grant '
       || priv
       || ' on '
       || owner
       || '.'
       || table_name
       || ' to '
       || grantee
       || ' '
       || DECODE (grantable, 'YES', ' WITH GRANT OPTION', '')
       || ';'    ddl
  FROM (SELECT DISTINCT grantee,
                        owner,
                        table_name,
                        grantable,
                        LISTAGG (privilege, ',')
                            WITHIN GROUP (ORDER BY privilege)
                            OVER (PARTITION BY grantee,
                                               owner,
                                               table_name,
                                               grantable)    priv
          FROM dba_tab_privs
         WHERE grantee IN (    SELECT granted_role
                                 FROM dba_role_privs
                           START WITH grantee = UPPER (upper('&username'))
                           CONNECT BY PRIOR granted_role = grantee))
UNION ALL
SELECT    'grant '
       || priv
       || ' to '
       || grantee
       || ' '
       || DECODE (admin_option, 'YES', ' WITH GRANT OPTION', '')
       || ';'    ddl
  FROM (SELECT DISTINCT
               grantee,
               admin_option,
               LISTAGG (privilege, ',')
                   WITHIN GROUP (ORDER BY privilege)
                   OVER (PARTITION BY grantee, admin_option)    priv
          FROM dba_sys_privs
         WHERE grantee = upper('&username'))
UNION ALL
SELECT    'grant '
       || priv
       || ' to '
       || grantee
       || ' '
       || DECODE (admin_option, 'YES', ' WITH GRANT OPTION', '')
       || ';'    ddl
  FROM (SELECT DISTINCT
               grantee,
               admin_option,
               LISTAGG (privilege, ',')
                   WITHIN GROUP (ORDER BY privilege)
                   OVER (PARTITION BY grantee, admin_option)    priv
          FROM dba_sys_privs
         WHERE grantee IN (    SELECT granted_role
                                 FROM dba_role_privs
                           START WITH grantee = UPPER (upper('&username'))
                           CONNECT BY PRIOR granted_role = grantee))
UNION ALL
    SELECT    'grant '
           || granted_role
           || ' to '
           || grantee
           || ' '
           || DECODE (admin_option, 'YES', ' WITH GRANT OPTION', '')
           || ';'    ddl
      FROM dba_role_privs
START WITH grantee = UPPER (upper('&username'))
CONNECT BY PRIOR granted_role = grantee;
