-- File Name: yashandb_prompt_06_orphan_accept.sql
-- Purpose: Test orphan PROMPT not bound after ACCEPT var
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_06_orphan_accept.sql
-- Expect: orphan line NOT shown for &b; ACCEPT hint for &a;
--         "Hint for b:" for &b; default 1 for &a on Enter
-- Input : <Enter> for a (default 1), then 99 for b

SET VERIFY OFF

PROMPT Orphan prompt should not bind to any variable:
ACCEPT a prompt 'Hint for a: ' default '1'
PROMPT Hint for b:

SELECT '&a' AS col_a, '&b' AS col_b FROM DUAL;
