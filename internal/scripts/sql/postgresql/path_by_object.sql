-- File Name: path_by_object.sql
-- Purpose: PostgreSQL Path By Object
-- Created: 20260516  by  huangtingzhong

\prompt 'please input schema name: '  schema
\prompt 'please input table name: '   tablename

SELECT 
    :'schema' as schemaname,
    :'tablename' as tablename,
    pg_relation_filepath(
        CASE 
            WHEN :'schema' IS NULL OR :'schema' = '' THEN :'tablename'::regclass
            ELSE (:'schema'||'.'||:'tablename')::regclass
        END
    ) as relative_path,
    setting || '/' || pg_relation_filepath(
        CASE 
            WHEN :'schema' IS NULL OR :'schema' = '' THEN :'tablename'::regclass
            ELSE (:'schema'||'.'||:'tablename')::regclass
        END
    ) as absolute_path
FROM pg_settings s
WHERE s.name = 'data_directory';
