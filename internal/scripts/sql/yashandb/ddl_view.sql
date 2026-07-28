-- File Name: ddl_view.sql
-- Purpose: Get VIEW DDL via DBMS_METADATA.GET_DDL
-- Created: 20260728  by  huangtingzhong
--
-- Usage: ytop -f ddl_view.sql
-- Example: owner=YSZX viewname=SANBZJST2026

SET VERIFY OFF
SET FEEDBACK OFF

UNDEFINE owner
UNDEFINE viewname

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | Get VIEW DDL (DBMS_METADATA.GET_DDL)                                   |
PROMPT +------------------------------------------------------------------------+
PROMPT

ACCEPT owner PROMPT 'Enter owner (schema username): '
ACCEPT viewname PROMPT 'Enter viewname (view name): '

SELECT DBMS_METADATA.GET_DDL('VIEW', UPPER(TRIM('&&viewname')), UPPER(TRIM('&&owner')))
  FROM dual
/
