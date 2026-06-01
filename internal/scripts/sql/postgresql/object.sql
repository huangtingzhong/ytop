-- File Name: object.sql
-- Purpose: PostgreSQL Search objects by owner and name
-- Created: 20260516  by  huangtingzhong

\prompt 'please input user name: '  user
\prompt 'please input schema name: '  schema
\prompt 'please input object name: '  name
SELECT OWNER,
    object_schema,
    object_name,
    object_type,
    relfile_path,
    create_time,
    last_ddl_time
FROM
    (
    SELECT
        n.nspname AS object_schema,
        C.relname AS object_name,
        u.rolname AS OWNER,
    CASE
            C.relkind
            WHEN 'r' THEN
            'TABLE'
            WHEN 'v' THEN
            'VIEW'
            WHEN 'm' THEN
            'MATERIALIZED_VIEW'
            WHEN 'i' THEN
            'INDEX'
            WHEN 'S' THEN
            'SEQUENCE'
            WHEN 't' THEN
            'TOAST_TABLE' ELSE C.relkind :: TEXT
        END AS object_type,
        pg_catalog.pg_relation_filepath ( C.OID ) AS relfile_path,
        NULL :: TIMESTAMP AS create_time,
        NULL :: TIMESTAMP AS last_ddl_time
    FROM
        pg_class
        C JOIN pg_roles u ON C.relowner = u.
        OID JOIN pg_namespace n ON C.relnamespace = n.OID
    WHERE
        C.relkind IN (
            'r',
            'v',
            'm',
            'i',
            'S',
            't'
        ) UNION ALL
    SELECT
        n.nspname AS object_schema,
        P.proname AS object_name,
        u.rolname AS OWNER,
    CASE

            WHEN P.prokind = 'p' THEN
            'PROCEDURE'
            WHEN P.prokind = 'f' THEN
            'FUNCTION'
            WHEN P.prokind = 'a' THEN
            'AGGREGATE' ELSE'FUNCTION'
        END AS object_type,
        NULL AS relfile_path,
        NULL :: TIMESTAMP AS create_time,
        NULL :: TIMESTAMP AS last_ddl_time
    FROM
        pg_proc
        P JOIN pg_roles u ON P.proowner = u.
        OID JOIN pg_namespace n ON P.pronamespace = n.OID UNION ALL
    SELECT
        n.nspname AS object_schema,
        T.tgname AS object_name,
        u.rolname AS OWNER,
        'TRIGGER' AS object_type,
        NULL AS relfile_path,
        NULL :: TIMESTAMP AS create_time,
        NULL :: TIMESTAMP AS last_ddl_time
    FROM
        pg_trigger
        T JOIN pg_class C ON T.tgrelid = C.
        OID JOIN pg_namespace n ON C.relnamespace = n.
        OID JOIN pg_roles u ON C.relowner = u.OID
    WHERE
        NOT T.tgisinternal UNION ALL
    SELECT
        n.nspname AS object_schema,
        T.typname AS object_name,
        u.rolname AS OWNER,
        'TYPE' AS object_type,
        NULL AS relfile_path,
        NULL :: TIMESTAMP AS create_time,
        NULL :: TIMESTAMP AS last_ddl_time
    FROM
        pg_type
        T JOIN pg_roles u ON T.typowner = u.
        OID JOIN pg_namespace n ON T.typnamespace = n.OID
    WHERE
        T.typtype IN ( 'b', 'c', 'd', 'e', 'r' ) UNION ALL
    SELECT
        n.nspname AS object_schema,
        con.conname AS object_name,
        u.rolname AS OWNER,
        'CONSTRAINT' AS object_type,
        NULL AS relfile_path,
        NULL :: TIMESTAMP AS create_time,
        NULL :: TIMESTAMP AS last_ddl_time
    FROM
        pg_constraint con
        JOIN pg_class C ON con.conrelid = C.
        OID JOIN pg_roles u ON C.relowner = u.
    OID JOIN pg_namespace n ON C.relnamespace = n.OID
    ) AS all_object
where object_name LIKE '%' || :'name' || '%'
      and OWNER LIKE '%' || :'user' || '%'
      and object_schema LIKE '%' || :'schema' || '%';
