-- File Name: user_sys_priv.sql
-- Purpose: Oracle User Sys privileges
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set lines 170
set pages 1000
col username for a20
col rollname for a20
col PRIVILEGE for a40

undefine username
SELECT *
  FROM (SELECT DECODE (SA1.GRANTEE#, 1, 'PUBLIC', U1.NAME) username,
               SUBSTR (U2.NAME, 1, 20) rollname,
               SUBSTR (SPM.NAME, 1, 27) privilege
          FROM SYS.SYSAUTH$ SA1,
               SYS.SYSAUTH$ SA2,
               SYS.USER$ U1,
               SYS.USER$ U2,
               SYS.SYSTEM_PRIVILEGE_MAP SPM
         WHERE     SA1.GRANTEE# = U1.USER#
               AND SA1.PRIVILEGE# = U2.USER#
               AND U2.USER# = SA2.GRANTEE#
               AND SA2.PRIVILEGE# = SPM.PRIVILEGE
        UNION
        SELECT U.NAME username,
               NULL rollname,
               SUBSTR (SPM.NAME, 1, 27) privilege
          FROM SYS.SYSTEM_PRIVILEGE_MAP SPM, SYS.SYSAUTH$ SA, SYS.USER$ U
         WHERE SA.GRANTEE# = U.USER# AND SA.PRIVILEGE# = SPM.PRIVILEGE)
 WHERE username = nvl(upper('&&username'),username);
undefine username;
