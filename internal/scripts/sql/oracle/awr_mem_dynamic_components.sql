-- File Name: awr_mem_dynamic_components.sql
-- Purpose: Oracle AWR Mem Dynamic Components
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info.sql

set echo off
store set sqlplusset replace
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000

ACCEPT begin_snap prompt 'Enter Search Begin Snapshot  (i.e. 2) : '
ACCEPT end_snap prompt 'Enter Search End Snapshot  (i.e. 4) : '
ACCEPT instance_number prompt 'Enter Search Instance Number  (i.e. 1(default)) : ' default '1'

variable bid  number;
variable eid  number;
variable inst_num  number;
variable top_n number;

begin
  :bid  :=  &begin_snap ;
  :eid  :=  &end_snap;
  :inst_num:=&instance_number;
end;
/
col component for a30
col begin_size for 9999999999.99 heading "Begin Snap Size (Mb)"
col current_size for 999999999.99 heading "Current Size (Mb)"
col min_size for 9999999999.99 heading "Min Size (Mb)"
col max_size for 9999999999.99 heading "Max Size (Mb)"
col open_count for 99999 heading "Oper Count"
col typmod for a10 heading "Last Op Typ/Mod"
/* Formatted on 2013/2/24 22:44:20 (QP5 v5.215.12089.38647) */
  SELECT e.component,
         b.current_size / (1024 * 1024) begin_size,
         e.current_size / (1024 * 1024) current_size,
         e.min_size / (1024 * 1024) min_size,
         e.max_size / (1024 * 1024) max_size,
         (e.oper_count - NVL (b.oper_count, 0)) oper_count,
            SUBSTR (e.last_oper_type, 1, 3)
         || '/'
         || SUBSTR (e.last_oper_mode, 1, 3)
            typmod
    FROM dba_hist_mem_dynamic_comp b, dba_hist_mem_dynamic_comp e
   WHERE     e.snap_id = :eid
         /*AND e.dbid = :dbid*/
         AND e.instance_number = :inst_num
         AND b.snap_id(+) = :bid
         AND b.dbid(+) = e.dbid
         AND b.instance_number(+) = e.instance_number
         AND b.component(+) = e.component
ORDER BY e.component
 /
 clear    breaks  
@sqlplusset
