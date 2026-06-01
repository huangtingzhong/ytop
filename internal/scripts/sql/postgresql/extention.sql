-- File Name: extention.sql
-- Purpose: PostgreSQL List installed PostgreSQL extensions
-- Created: 20260516  by  huangtingzhong

SELECT * FROM pg_available_extensions ORDER BY name;
SELECT e.extname,
       r.rolname AS owner,
       n.nspname AS schema,
       e.extversion,
       e.extrelocatable,
       extconfig,
       extcondition
FROM pg_extension e
JOIN pg_roles r ON r.oid = e.extowner
JOIN pg_namespace n ON n.oid = e.extnamespace;




WITH depend AS (
  SELECT 
    d.classid,
    d.objid,
    d.refobjid,
    d.deptype,
    e.extname
  FROM pg_depend d
  JOIN pg_extension e ON d.refobjid = e.oid
  WHERE e.extname = 'pg_stat_statements'
)
SELECT 
  dep.extname AS extension_name,
  dep.deptype,
  dep.classid,
  dep.objid,
  dep.refobjid,
  -- resolve object name by classid
  CASE dep.classid
    WHEN 'pg_class'::regclass::oid THEN cls.relname
    WHEN 'pg_proc'::regclass::oid THEN prc.proname
    WHEN 'pg_type'::regclass::oid THEN typ.typname
    WHEN 'pg_namespace'::regclass::oid THEN nsp.nspname
    WHEN 'pg_constraint'::regclass::oid THEN con.conname
    ELSE 'N/A'
  END AS object_name,
  CASE dep.classid
    WHEN 'pg_class'::regclass::oid THEN 'table/view/index/other'
    WHEN 'pg_proc'::regclass::oid THEN 'function'
    WHEN 'pg_type'::regclass::oid THEN 'type'
    WHEN 'pg_namespace'::regclass::oid THEN 'schema'
    WHEN 'pg_constraint'::regclass::oid THEN 'constraint'
    ELSE 'other'
  END AS object_type
FROM depend dep
LEFT JOIN pg_class cls ON cls.oid = dep.objid AND dep.classid = 'pg_class'::regclass
LEFT JOIN pg_proc prc ON prc.oid = dep.objid AND dep.classid = 'pg_proc'::regclass
LEFT JOIN pg_type typ ON typ.oid = dep.objid AND dep.classid = 'pg_type'::regclass
LEFT JOIN pg_namespace nsp ON nsp.oid = dep.objid AND dep.classid = 'pg_namespace'::regclass
LEFT JOIN pg_constraint con ON con.oid = dep.objid AND dep.classid = 'pg_constraint'::regclass
ORDER BY object_type, object_name;
