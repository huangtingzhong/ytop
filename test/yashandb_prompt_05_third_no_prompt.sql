-- File Name: yashandb_prompt_05_third_no_prompt.sql
-- Purpose: Test 3rd var without PROMPT uses default input
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_05_third_no_prompt.sql
-- Expect: banner for begin/end_snap only; inst_id shows
--         "Enter value for &inst_id:" with no extra PROMPT line
-- Input : e.g. 10 <Enter> 20 <Enter> 3 <Enter>

SET VERIFY OFF

PROMPT Enter &begin_snap and &end_snap:

SELECT '&begin_snap' AS begin_snap,
       '&end_snap'   AS end_snap,
       '&inst_id'    AS inst_id
  FROM DUAL;
