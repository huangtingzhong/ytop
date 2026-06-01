-- File Name: awr_namespace_use.sql
-- Purpose: Oracle AWR Namespace Use
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

/* Formatted on 2012-11-23 14:33:27 (QP5 v5.185.11230.41888) */
SELECT namespace "Namespace",
       gets "Get Requests",
       ROUND (getm, 2) "Pct Miss",
       pins "Pin Requests",
       ROUND (pinm, 2) "Pct Miss",
       reloads "Reloads",
       inv "Invali- dations"
  FROM (  SELECT b.namespace,
                 e.gets - b.gets gets,
                 TO_NUMBER (
                    DECODE (
                       e.gets,
                       b.gets, NULL,
                       100 - (e.gethits - b.gethits) * 100 / (e.gets - b.gets)))
                    getm,
                 e.pins - b.pins pins,
                 TO_NUMBER (
                    DECODE (
                       e.pins,
                       b.pins, NULL,
                       100 - (e.pinhits - b.pinhits) * 100 / (e.pins - b.pins)))
                    pinm,
                 e.reloads - b.reloads reloads,
                 e.invalidations - b.invalidations inv
            FROM dba_hist_librarycache b, dba_hist_librarycache e
           WHERE     b.snap_id = &num_begin
                 AND e.snap_id = &num_end
                 AND b.dbid = (SELECT dbid FROM v$database)
                 AND e.dbid = (SELECT dbid FROM v$database)
                 AND b.instance_number =
                        (SELECT instance_number FROM v$instance)
                 AND e.instance_number =
                        (SELECT instance_number FROM v$instance)
                 AND b.namespace = e.namespace
                 AND (e.gets - b.gets > 0 OR e.pins - b.pins > 0)
        ORDER BY b.namespace)
/
