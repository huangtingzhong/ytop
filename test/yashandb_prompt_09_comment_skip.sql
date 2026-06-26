-- File Name: yashandb_prompt_09_comment_skip.sql
-- Purpose: Test comment line &var is not substituted
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_09_comment_skip.sql
-- Expect: only one prompt for andsecret; comment line unchanged in script
-- Input : e.g. hello <Enter>
-- Note  : if output shows &secret in SQL result only, comment was skipped

SET VERIFY OFF

-- Variables: &secret (documentation only, must NOT trigger substitution)
-- This comment mentions &decoy which is also ignored

PROMPT Enter secret value:

SELECT '&secret' AS secret_value FROM DUAL;
