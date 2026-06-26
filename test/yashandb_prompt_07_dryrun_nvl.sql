-- File Name: yashandb_prompt_07_dryrun_nvl.sql
-- Purpose: Test PROMPT-only var with NVL default in SQL
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_07_dryrun_nvl.sql
-- Expect: PROMPT line shown; Enter on dryrun -> resolved value 1
-- Input : <Enter> (empty dryrun)

SET VERIFY OFF

PROMPT dryrun (Enter=1 print only, 0=execute):

SELECT NVL(NULLIF(TRIM('&dryrun'), ''), '1') AS dryrun_resolved FROM DUAL;
