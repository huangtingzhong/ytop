-- File Name: awr_control.sql
-- Purpose: YashanDB Show AWR snap interval retention
-- Created: 20260803  by  huangtingzhong

-- Source: SYS.WRM$_WR_CONTROL (Yashan has no DBA_HIST_WR_CONTROL).
-- Defaults: snap_interval=1h, retention=8d; change via DBMS_AWR.MODIFY_SNAPSHOT_SETTINGS(min).

col dbid            for a12
col snap_ivl        for a20
col reten           for a20
col interval_min    for a12
col retention_min   for a14
col retention_days  for a8
col topnsql         for a8

SELECT TO_CHAR(dbid) AS dbid,
       TO_CHAR(snap_interval) AS snap_ivl,
       TO_CHAR(retention) AS reten,
       TO_CHAR(EXTRACT(DAY FROM snap_interval) * 24 * 60
             + EXTRACT(HOUR FROM snap_interval) * 60
             + EXTRACT(MINUTE FROM snap_interval)) AS interval_min,
       TO_CHAR(EXTRACT(DAY FROM retention) * 24 * 60
             + EXTRACT(HOUR FROM retention) * 60
             + EXTRACT(MINUTE FROM retention)) AS retention_min,
       TO_CHAR(EXTRACT(DAY FROM retention)) AS retention_days,
       TO_CHAR(topnsql) AS topnsql
FROM   sys.wrm$_wr_control;
