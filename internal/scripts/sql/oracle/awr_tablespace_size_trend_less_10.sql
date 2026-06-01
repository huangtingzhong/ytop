-- File Name: awr_tablespace_size_trend_less_10.sql
-- Purpose: Oracle AWR Tablespace Size Trend Less 10
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 250 pages 10000 heading on
col rtime for a10
col name for a20
col tsize for 9999999
col max_size for 99999999
col used_size for 9999999
col inc_size for 99999
/* Formatted on 2016/01/22 11:36:54 (QP5 v5.256.13226.35510) */
/* Formatted on 2016/01/22 11:55:47 (QP5 v5.256.13226.35510) */
WITH tt
     AS (SELECT e.rtime,
                e.tablespace_id,
                e.tablespace_size,
                e.tablespace_maxsize,
                e.tablespace_usedsize,
                (  e.tablespace_usedsize
                 - NVL (
                      LAG (e.TABLESPACE_USEDSIZE)
                         OVER (PARTITION BY tablespace_id ORDER BY dnum),
                      e.tablespace_usedsize))
                   inc_use_size
           FROM (SELECT a.tablespace_id,
                        a.tablespace_size,
                        a.tablespace_maxsize,
                        a.TABLESPACE_USEDSIZE,
                        a.rtime,
                        ROW_NUMBER ()
                           OVER (PARTITION BY a.TABLESPACE_ID ORDER BY rtime)
                           dnum
                   FROM (SELECT b.tablespace_id,
                                b.tablespace_size,
                                b.tablespace_maxsize,
                                SUBSTR (b.rtime, 1, 10) rtime,
                                b.TABLESPACE_USEDSIZE,
                                ROW_NUMBER ()
                                OVER (
                                   PARTITION BY b.TABLESPACE_ID,
                                                SUBSTR (b.rtime, 1, 10)
                                   ORDER BY b.TABLESPACE_USEDSIZE DESC)
                                   rnum
                           FROM dba_hist_tbspc_space_usage b, v$database c
                          WHERE b.dbid = c.dbid) a
                  WHERE rnum = 1) e)
SELECT *
  FROM (SELECT i.rtime,
               i.name,
               i.tsize,
               i.max_size,
               i.used_size,
               TRUNC (i.tsize - i.used_size) free_size,
               TRUNC (i.avg_inc_size),
               TRUNC (
                  (i.tsize - i.used_size) / DECODE (i.avg_inc_size, 0, 1))
                  inc_day
          FROM (SELECT o.rtime,
                       o.name,
                       o.tsize,
                       o.max_size,
                       o.used_size,
                       MAX (rtime) OVER (PARTITION BY o.name) m_rtime,
                       MAX (used_size) OVER (PARTITION BY o.name)
                          max_used_size,
                       AVG (inc_size) OVER (PARTITION BY o.name) avg_inc_size
                  FROM (SELECT tt.rtime,
                               f.name,
                               TRUNC (
                                    tt.tablespace_size
                                  * h.BLOCK_SIZE
                                  / 1024
                                  / 1024)
                                  tsize,
                               TRUNC (
                                    tt.tablespace_maxsize
                                  * h.BLOCK_SIZE
                                  / 1024
                                  / 1024)
                                  max_size,
                               TRUNC (
                                    tt.tablespace_usedsize
                                  * h.BLOCK_SIZE
                                  / 1024
                                  / 1024)
                                  used_size,
                               TRUNC (
                                    tt.inc_use_size
                                  * h.BLOCK_SIZE
                                  / 1024
                                  / 1024)
                                  inc_size
                          FROM v$tablespace f, tt, dba_tablespaces h
                         WHERE     f.ts# = tt.tablespace_id(+)
                               AND tt.inc_use_size > 0
                               AND f.name = h.tablespace_name
                               AND h.CONTENTS IN ('PERMANENT')) o) i
         WHERE i.rtime = i.m_rtime)
 WHERE inc_day < 10
/