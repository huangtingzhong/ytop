-- File Name: test_yashandb_prompt_accept.sql
-- Purpose: Test ytop PROMPT and ACCEPT on YashanDB
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -f test/test_yashandb_prompt_accept.sql
-- Variables: &top_n (ACCEPT default 10), &name (PROMPT hint)

SET SERVEROUTPUT ON
SET VERIFY OFF

PROMPT Enter filter name (empty=ALL):

ACCEPT top_n prompt 'Enter top_n count: ' default '10'

SELECT '&top_n' AS top_n, '&name' AS filter_name FROM DUAL;
