-- File Name: yashandb_prompt_03_banner_user.sql
-- Purpose: Test banner PROMPT containing &username in text
-- Created: 20260626  by  huangtingzhong
--
-- Usage: ytop -t <host> -f test/yashandb_prompt_03_banner_user.sql
-- Expect: show banner "| User status (username = &username) |"
-- Input : e.g. SYS <Enter>
-- Result: username=SYS (or row from dba_users if exists)

SET VERIFY OFF

PROMPT | User status (username = &username) |

SELECT username, account_status
  FROM dba_users
 WHERE username = UPPER(TRIM('&username'))
   AND ROWNUM = 1;
