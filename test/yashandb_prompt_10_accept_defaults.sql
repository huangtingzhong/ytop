-- File Name: yashandb_prompt_10_accept_defaults.sql
-- Purpose: Test ACCEPT quoted and bare numeric defaults
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_10_accept_defaults.sql
-- Expect: two ACCEPT hints; defaults 10 and 24 on Enter
-- Input : <Enter> <Enter>

SET VERIFY OFF

ACCEPT top_n prompt 'Enter top_n count: ' default '10'
ACCEPT hours prompt 'Enter hours (bare default): ' default 24

SELECT '&top_n' AS top_n, '&hours' AS hours FROM DUAL;
