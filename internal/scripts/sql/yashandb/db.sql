-- File Name: db.sql
-- Purpose: YashanDB Show database open mode and log status
-- Created: 20260516  by  huangtingzhong

col host                   for a15
col name                   for a15
col log_mode               for a10
col open_mode              for a10
col scn                    for a20
col status                 for a15
col flashback              for a12
col role                   for a16
col prot_mode              for a20
col prot_level             for a20
col sw_status              for a20

SELECT host_name              AS host,
       database_name          AS name,
       log_mode,
       open_mode,
       TO_CHAR(current_scn)   AS scn,
       status,
       flashback_on           AS flashback,
       database_role          AS role,
       protection_mode        AS prot_mode,
       protection_level       AS prot_level,
       switchover_status      AS sw_status
  FROM v$database;
