-- File Name: sess_link.sql
-- Purpose: Oracle session Link
-- Created: 20260516  by  huangtingzhong

/* Formatted on 2016/7/20 13:48:58 (QP5 v5.256.13226.35510) */
set echo off
set verify off
set serveroutput on
set lines 200
set pages 1000
col o_hostname for a20
col o_spid for 99999999999
col o_txif for a60
col s_sid for 999999999
col s_serial# for 9999999999999
col O_TXID for a30
col machine for a20
col sid for a20
COL i_where NEW_V i_where NOPRINT;


SELECT DECODE ('&&LOCAL_OR_REMOTE',
               'LOCAL', 'a.dbname = UPPER (b.VALUE)',
               'REMOTE', 'a.dbname != UPPER (b.VALUE)')
          i_where
  FROM DUAL;


SELECT O_HOSTNAME,
       O_SPID,
       O_TXID,
       S_SID || '.' || S_SERIAL# "SID",
       s_status,
       dblink_user
  FROM (SELECT /*+ ORDERED */
              S.KSUSEMNM "O_HOSTNAME",
               S.KSUSEPID "O_SPID",
               SUBSTR (G.K2GTITID_ORA,
                       1,
                         REGEXP_INSTR (G.K2GTITID_ORA,
                                       '[.]',
                                       1,
                                       1)
                       - 1)
                  dbname,
               G.K2GTITID_ORA "O_TXID",
               S.INDX "S_SID",
               S.KSUSESER "S_SERIAL#",
               DECODE (
                  BITAND (s.KSUSEIDL, 11),
                  1, 'ACTIVE',
                  0, DECODE (BITAND (s.KSUSEFLG, 4096),
                             0, 'INACTIVE',
                             'CACHED'),
                  2, 'SNIPED',
                  3, 'SNIPED',
                  'KILLED')
                  "S_STATUS",
               S.KSUUDNAM "DBLINK_USER"
          FROM SYS.X$K2GTE G, SYS.X$KTCXB T, SYS.X$KSUSE S
         WHERE     G.K2GTDXCB = T.KTCXBXBA
               AND G.K2GTDSES = T.KTCXBSES
               AND S.ADDR = G.K2GTDSES) a,
       (SELECT VALUE
          FROM v$parameter
         WHERE name = 'db_name') b
 WHERE &i_where
/