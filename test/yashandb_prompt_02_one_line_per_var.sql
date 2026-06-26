-- File Name: yashandb_prompt_02_one_line_per_var.sql
-- Purpose: Test one PROMPT line per variable FIFO binding
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_02_one_line_per_var.sql
-- Expect: show "Enter begin_snap:" then "Enter end_snap:"
-- Input : e.g. 100 <Enter> 200 <Enter>
-- Result: begin_snap=100, end_snap=200

SET VERIFY OFF

PROMPT Enter begin_snap:
PROMPT Enter end_snap:

SELECT '&begin_snap' AS begin_snap, '&end_snap' AS end_snap FROM DUAL;
