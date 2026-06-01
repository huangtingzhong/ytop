-- File Name: db_version.sql
-- Purpose: YashanDB Show database version and instance info
-- Created: 20260516  by  huangtingzhong

col version_banner for a60
col instance_name  for a15
col host_name      for a15
col startup_time   for a18
col database_status for a15

SELECT v.banner AS version_banner,
       i.instance_name,
       i.host_name,
       TO_CHAR(i.startup_time, 'YYYY-MM-DD HH24:MI:SS') AS startup_time,
       i.database_status
  FROM (SELECT banner
          FROM v$version
         WHERE ROWNUM = 1) v
 CROSS JOIN (SELECT instance_name,
                    host_name,
                    version,
                    startup_time,
                    database_status
               FROM v$instance
              WHERE ROWNUM = 1) i

