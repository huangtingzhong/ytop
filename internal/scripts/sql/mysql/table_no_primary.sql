-- File Name: table_no_primary.sql
-- Purpose: MySQL List tables without a primary key
-- Created: 20260516  by  huangtingzhong

SELECT
    TABLE_SCHEMA,TABLE_NAME,TABLE_TYPE,ENGINE,TABLE_ROWS,AVG_ROW_LENGTH,INDEX_LENGTH,AUTO_INCREMENT,CREATE_TIME,TABLE_COLLATION
FROM
    information_schema.TABLES
WHERE
    table_name NOT IN (
        SELECT DISTINCT
            TABLE_NAME
        FROM
            information_schema.COLUMNS
        WHERE
            (COLUMN_KEY = 'PRI' and extra='auto_increment') or (column_key in ('UNI','PRI' ))
        AND table_schema NOT IN ('mysql' , 'information_schema',
                                    'sys', 'performance_schema')
;