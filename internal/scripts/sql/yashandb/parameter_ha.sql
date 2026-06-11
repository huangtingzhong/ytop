-- File Name: parameter_ha.sql
-- Purpose: List HA and standby related parameters
-- Created: 20260610  by  huangtingzhong

col i              for a1
col name           for a30
col value          for a50
col IS_DEPRECATED  for a10

select inst_id||'' i,
name,value,default_value,
IS_DEPRECATED
 from (
 SELECT inst_id,name,value,default_value, IS_DEPRECATED FROM GV_$PARAMETER
 UNION
 SELECT inst_id,name,value,default_value, IS_DEPRECATED FROM GX_$PARAMETER) a
 where (
    a.name LIKE 'HA_%'
 OR a.name LIKE 'OM_ELECTION%'
 OR a.name LIKE 'FAILOVER_%'
 OR a.name LIKE 'ARCHIVELOG_%'
 OR a.name LIKE 'ARCHIVE_LOCAL%'
 OR a.name LIKE 'REPLICATION%'
 OR a.name LIKE 'STANDBY%'
 OR a.name LIKE 'QUORUM_SYNC%'
 OR a.name LIKE 'REQUIRED_SYNC%'
 OR a.name LIKE 'BLOCK_REPAIR%'
 OR a.name = 'RECOVERY_PARALLELISM'
 OR a.name = 'REDO_FILE_NAME_CONVERT'
 OR a.name = 'DB_FILE_NAME_CONVERT'
 OR a.name = 'DB_BUCKET_NAME_CONVERT'
 OR (a.name LIKE 'ARCHIVE_DEST_%' AND a.value IS NOT NULL AND LENGTH(TRIM(a.value)) > 0)
 )
 order by inst_id,name;
