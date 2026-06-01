-- File Name: mysid.sql
-- Purpose: YashanDB Show current session SID and basic info
-- Created: 20260516  by  huangtingzhong

select userenv('sid') from dual;
