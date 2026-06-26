-- File Name: yashandb_prompt_08_no_prompt.sql
-- Purpose: Test variable with no PROMPT or ACCEPT at all
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_08_no_prompt.sql
-- Expect: only "Enter value for &sid:" (no PROMPT banner)
-- Input : e.g. 100 <Enter>

SET VERIFY OFF

SELECT '&sid' AS sid FROM DUAL;
