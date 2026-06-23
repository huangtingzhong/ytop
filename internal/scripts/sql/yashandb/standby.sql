-- File Name: standby.sql
-- Purpose: YashanDB Show standby database apply status
-- Created: 20260516  by  huangtingzhong

col database_role      for a16
col open_mode          for a12
col status             for a15
col protection_mode    for a20
col protection_level   for a20
col switchover_status  for a20
col rcy_point          for a24
col flush_point        for a24
col reset_point        for a24

SELECT database_role,
       open_mode,
       status,
       protection_mode,
       protection_level,
       switchover_status,
       rcy_point,
       flush_point,
       reset_point
FROM v$database;

col connection         for a16
col peer_role          for a12
col peer_mode          for a12
col peer_addr          for a25
col peer_point         for a15
col received_point     for a15
col applied_point      for a15
col error              for a60
col t_lag              for a10
col a_lag              for a10
col gap_seq            for a8
col last_msg_sec       for a10

SELECT connection,
       status,
       peer_role,
       peer_mode,
       peer_addr,
       peer_point,
       received_point,
       applied_point,
       transport_lag || '' AS t_lag,
       apply_lag     || '' AS a_lag,
       gap_seq#      || '' AS gap_seq,
       time_since_last_msg || '' AS last_msg_sec,
       error
FROM v$replication_status;

SELECT inst_id, id AS gap_id, low_sequence#, high_sequence#
FROM gv$archive_gap
ORDER BY inst_id, gap_id;

SELECT g.inst_id,
       g.id AS gap_id,
       g.low_sequence# + n.n - 1 AS missing_seq#
FROM gv$archive_gap g
CROSS JOIN (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 9999) n
WHERE g.low_sequence# + n.n - 1 <= g.high_sequence#
ORDER BY g.inst_id, g.id, missing_seq#;


SELECT * FROM v$recovery_status;
SELECT item, units, value FROM gv$recovery_progress;
