-- File Name: arch_list.sql
-- Purpose: YashanDB List archived redo files in a time window
-- Created: 20260612  by  huangtingzhong
-- Usage: &hours_back = oldest boundary (hours ago); &interval_hours = newest boundary (hours ago, 0=now)

col thread#          for a8
col sequence#        for a10
col archive_path     for a64
col first_time       for a26
col completion_time  for a26
col hours_ago        for a12

SELECT thread# || '' AS thread#,
       sequence# || '' AS sequence#,
       name AS archive_path,
       first_time,
       completion_time,
       ROUND((SYSDATE - CAST(completion_time AS DATE)) * 24, 2) || '' AS hours_ago
  FROM v$archived_log
 WHERE completion_time >= SYSDATE - (&hours_back / 24)
   AND completion_time <= SYSDATE - ((&hours_back-&interval_hours) / 24)
 ORDER BY completion_time DESC;
