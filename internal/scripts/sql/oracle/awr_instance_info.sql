-- File Name: awr_instance_info.sql
-- Purpose: Oracle AWR Instance Info
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
column instt_num  heading "Inst Num"  format 99999;
column instt_name heading "Instance"  format a12;
column dbb_name   heading "DB Name"   format a12;
column dbbid      heading "DB Id"     format a12 just c;
column host       heading "Host"      format a12;


PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | Instances in this Workload Repository schema                           |
PROMPT +------------------------------------------------------------------------+ 
PROMPT

select distinct
       (case when cd.dbid = wr.dbid and
                  cd.name = wr.db_name and
                  ci.instance_number = wr.instance_number and
                  ci.instance_name   = wr.instance_name   and
                  ci.host_name       = wr.host_name
             then '* '
             else '  '
        end) || wr.dbid   dbbid
     , wr.instance_number instt_num
     , wr.db_name         dbb_name
     , wr.instance_name   instt_name
     , wr.host_name       host
  from dba_hist_database_instance wr, v$database cd, v$instance ci;
