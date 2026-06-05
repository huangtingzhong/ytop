-- File Name: user_unlock.sql
-- Purpose: YashanDB Unlock user account; show status before and after
-- Created: 20260524  by  huangtingzhong

COLUMN username   FORMAT A30
COLUMN status     FORMAT A10
COLUMN tablespace FORMAT A20
COLUMN temp_tablespace FORMAT A15
COLUMN Profile    FORMAT A20
COLUMN CRTIME     FORMAT A12
COLUMN locktime   FORMAT A12
COLUMN expiretime FORMAT A12

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | User status BEFORE unlock (username = &username)                        |
PROMPT +------------------------------------------------------------------------+
PROMPT

SELECT a.username,
       a.account_status status,
       b.lcount failed,
       a.default_tablespace tablespace,
       a.temporary_tablespace temp_tablespace,
       a.Profile,
       TO_CHAR (a.Created, 'MM-DD hh24') CRTIME,
       TO_CHAR (a.lock_date, 'mm-dd hh24') locktime,
       TO_CHAR (a.expiry_date, 'mm-dd hh24') expiretime
  FROM dba_users a, sys.user$ b
 WHERE a.username = UPPER ('&username')
   AND a.username = b.name
/

ALTER USER &username ACCOUNT UNLOCK
/

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | User status AFTER unlock (username = &username)                         |
PROMPT +------------------------------------------------------------------------+
PROMPT

SELECT a.username,
       a.account_status status,
       b.lcount failed,
       a.default_tablespace tablespace,
       a.temporary_tablespace temp_tablespace,
       a.Profile,
       TO_CHAR (a.Created, 'MM-DD hh24') CRTIME,
       TO_CHAR (a.lock_date, 'mm-dd hh24') locktime,
       TO_CHAR (a.expiry_date, 'mm-dd hh24') expiretime
  FROM dba_users a, sys.user$ b
 WHERE a.username = UPPER ('&username')
   AND a.username = b.name
/
