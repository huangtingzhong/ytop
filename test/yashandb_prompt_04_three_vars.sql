-- File Name: yashandb_prompt_04_three_vars.sql
-- Purpose: Test banner with 2 vars plus dedicated 3rd PROMPT
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_04_three_vars.sql
-- Expect: banner for begin/end_snap, then "Enter inst_id:"
-- Input : e.g. 1 <Enter> 2 <Enter> 1 <Enter>
-- Result: three columns echoed from DUAL

SET VERIFY OFF

PROMPT Enter &begin_snap and &end_snap:
PROMPT Enter inst_id:

SELECT '&begin_snap' AS begin_snap,
       '&end_snap'   AS end_snap,
       '&inst_id'    AS inst_id
  FROM DUAL;
