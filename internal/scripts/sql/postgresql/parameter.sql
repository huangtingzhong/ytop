-- File Name: parameter.sql
-- Purpose: PostgreSQL Show instance parameters and defaults
-- Created: 20260516  by  huangtingzhong

\prompt 'please input parameter name: '  name

SELECT name,
       CASE
           WHEN unit = '8kB' THEN (setting::int * 8) || 'kB'
           ELSE setting || coalesce(unit, ' ')
       END AS setting,
       context,
       boot_val as default_val,
       CASE source
        WHEN 'default' THEN 'Default'
        WHEN 'configuration file' THEN 'Config File'
        WHEN 'command line' THEN 'Command Line'
        WHEN 'environment variable' THEN 'Environment'
        WHEN 'database' THEN 'Database'
        WHEN 'user' THEN 'User Setting'
        WHEN 'override' THEN 'Override'
        ELSE source
        END AS type,
         CASE
        WHEN sourcefile IS NOT NULL THEN
            CASE
                WHEN sourcefile LIKE '%postgresql.auto.conf%' THEN 'Dynamic Config'
                WHEN sourcefile LIKE '%postgresql.conf%' THEN 'Main Config'
                ELSE 'Other Config'
            END
        ELSE '-'
       END AS file_type,
       pending_restart AS  R,
       short_desc
FROM pg_settings WHERE name LIKE '%' || :'name' || '%';
