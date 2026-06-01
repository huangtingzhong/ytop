-- File Name: sql_by_sqlid.sql
-- Purpose: YashanDB Show SQL details by sql_id
-- Created: 20260516  by  huangtingzhong

select sql_fulltext from v$sql where sql_id='&sqlid';
