-- File Name: yashandb_prompt_11_optional_filter.sql
-- Purpose: Test empty filter means ALL pattern with PROMPT
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_11_optional_filter.sql
-- Expect: PROMPT for login; empty Enter -> ALL in resolved_login
-- Input : <Enter> for login (empty), or APP for filter

SET VERIFY OFF

PROMPT Enter username filter (empty=ALL):

SELECT CASE
         WHEN TRIM('&login') IS NULL OR TRIM('&login') = '' THEN 'ALL'
         ELSE UPPER(TRIM('&login'))
       END AS resolved_login
  FROM DUAL;
