-- File Name: awr_dictionary_cache.sql
-- Purpose: Oracle AWR Dictionary Cache
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 30

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | DISPLAY NAMESPACE IN SHARED_POOL  GET AND PIN                                     |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
@@awr_snapshot_info.sql
set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 30
col namespace for a15

ACCEPT num_begin prompt 'Enter Search Snapshot Number (i.e. 123) : '
ACCEPT num_end prompt 'Enter Search Snapshot Number (i.e. 123) : '

variable num_begin number;
variable num_end number;
begin
   :num_begin          := &num_begin;
   :num_end            := &num_end;
end;
/

/* Formatted on 2012-11-23 15:16:30 (QP5 v5.185.11230.41888) */
SELECT param "Cache",
       gets "Get Requests",
       ROUND (getm, 2) "Pct Miss",
       scans "Scan Reqs",
       scanm "Pct Miss",
       mods "Mod Reqs",
       usage "Final Usage"
  FROM (  SELECT LOWER (b.parameter) param,
                 e.gets - b.gets gets,
                 TO_NUMBER (
                    DECODE (
                       e.gets,
                       b.gets, NULL,
                       (e.getmisses - b.getmisses) * 100 / (e.gets - b.gets)))
                    getm,
                 e.scans - b.scans scans,
                 TO_NUMBER (
                    DECODE (
                       e.scans,
                       b.scans, NULL,
                         (e.scanmisses - b.scanmisses)
                       * 100
                       / (e.scans - b.scans)))
                    scanm,
                 e.modifications - b.modifications mods,
                 e.usage usage
            FROM dba_hist_rowcache_summary b, dba_hist_rowcache_summary e
           WHERE     b.snap_id = &num_begin
                 AND e.snap_id = &num_end
                 AND b.dbid = (SELECT dbid FROM v$database)
                 AND e.dbid = (SELECT dbid FROM v$database)
                 AND b.instance_number =
                        (SELECT instance_number FROM v$instance)
                 AND e.instance_number =
                        (SELECT instance_number FROM v$instance)
                 AND e.parameter = b.parameter
                 AND e.gets - b.gets > 0 
        ORDER BY param)
/
