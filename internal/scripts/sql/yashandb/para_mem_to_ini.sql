-- File Name: para_mem_to_ini.sql
-- Purpose: Apply non-default params to SPFILE dryrun or execute
-- Created: 20260623  by  huangtingzhong
--
-- Usage: ytop -f para_mem_to_ini.sql
-- Variables: &dryrun (Enter=1 print only, 0=execute)

SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT dryrun (Enter=1 print only, 0=execute):

DECLARE
  c_scope CONSTANT VARCHAR2(32) := 'SCOPE=SPFILE';

  l_dryrun NUMBER := NVL(TO_NUMBER(NULLIF(TRIM('&dryrun'), '')), 1);
  l_sql    VARCHAR2(4000);
  l_val    VARCHAR2(4000);
  l_node   VARCHAR2(4000);

  FUNCTION fmt_param_value (p_value IN VARCHAR2) RETURN VARCHAR2
  IS
    v VARCHAR2(4000) := TRIM(p_value);
  BEGIN
    IF v IS NULL THEN
      RETURN 'NULL';
    END IF;

    IF SUBSTR(v, 1, 1) = '''' THEN
      RETURN v;
    END IF;

    IF REGEXP_LIKE(v, '^(TRUE|FALSE)$', 'i') THEN
      RETURN UPPER(v);
    END IF;

    IF REGEXP_LIKE(v, '^[+-]?[0-9]+(\.[0-9]+)?$') THEN
      RETURN v;
    END IF;

    IF REGEXP_LIKE(v, '^[A-Za-z_][A-Za-z0-9_]*$') THEN
      RETURN v;
    END IF;

    RETURN '''' || REPLACE(v, '''', '''''') || '''';
  END fmt_param_value;

  PROCEDURE print_om_manual_hint (p_name IN VARCHAR2, p_value IN VARCHAR2)
  IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('[NOTICE] ' || p_name
      || ' is not writable to yasdb.ini via ALTER SYSTEM.');
    DBMS_OUTPUT.PUT_LINE('[ACTION] Query from OM (ytop -f para_om_to_ini.py),'
      || ' then add manually to yasdb.ini:');
    DBMS_OUTPUT.PUT_LINE('         ' || p_name || '=' || TRIM(p_value));
  END print_om_manual_hint;

  PROCEDURE print_ini_manual_hint (p_name IN VARCHAR2, p_value IN VARCHAR2)
  IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('[ACTION] Add manually to yasdb.ini'
      || ' ($YASDB_DATA/config/yasdb.ini):');
    DBMS_OUTPUT.PUT_LINE('         ' || p_name || '=' || TRIM(p_value));
  END print_ini_manual_hint;

  PROCEDURE emit_node_id_hint
  IS
  BEGIN
    l_node := NULL;
    BEGIN
      SELECT value INTO l_node
        FROM v$parameter
       WHERE UPPER(name) = 'NODE_ID'
         AND ROWNUM = 1;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        BEGIN
          SELECT value INTO l_node
            FROM x$parameter
           WHERE UPPER(name) = 'NODE_ID'
             AND ROWNUM = 1;
        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            l_node := NULL;
        END;
    END;

    IF l_node IS NULL THEN
      RETURN;
    END IF;

    l_val := fmt_param_value(l_node);
    l_sql := 'ALTER SYSTEM SET NODE_ID=' || l_val || ' ' || c_scope;
    DBMS_OUTPUT.PUT_LINE(l_sql || ';');
    print_om_manual_hint('NODE_ID', l_node);
  END emit_node_id_hint;

BEGIN
  DBMS_OUTPUT.ENABLE(1000000);

  emit_node_id_hint;

  FOR rec IN (
    SELECT param_name,
           param_value
      FROM (
        SELECT name AS param_name,
               value AS param_value,
               default_value AS param_default
          FROM v$parameter
        UNION
        SELECT name AS param_name,
               value AS param_value,
               default_value AS param_default
          FROM x$parameter
      )
     WHERE UPPER(param_name) <> 'NODE_ID'
       AND CASE
             WHEN param_value IS NULL AND param_default IS NULL THEN 0
             WHEN param_value = param_default THEN 0
             WHEN REGEXP_LIKE(TRIM(param_value), '^[+-]?[0-9]+(\.[0-9]+)?$')
              AND REGEXP_LIKE(TRIM(param_default), '^[+-]?[0-9]+(\.[0-9]+)?$')
              AND TO_NUMBER(TRIM(param_value)) = TO_NUMBER(TRIM(param_default)) THEN 0
             ELSE 1
           END = 1
     ORDER BY param_name
  ) LOOP
    l_val := fmt_param_value(rec.param_value);
    l_sql := 'ALTER SYSTEM SET '
          || rec.param_name || '=' || l_val
          || ' ' || c_scope;

    DBMS_OUTPUT.PUT_LINE(l_sql || ';');

    IF NVL(l_dryrun, 1) = 0 THEN
      BEGIN
        EXECUTE IMMEDIATE l_sql;
      EXCEPTION
        WHEN OTHERS THEN
          DBMS_OUTPUT.PUT_LINE('[ERROR] ' || rec.param_name || ': ' || SQLERRM);
          print_ini_manual_hint(rec.param_name, rec.param_value);
      END;
    END IF;
  END LOOP;
END;
/
