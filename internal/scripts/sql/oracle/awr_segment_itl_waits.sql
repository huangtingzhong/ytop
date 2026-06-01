-- File Name: awr_segment_itl_waits.sql
-- Purpose: Oracle AWR Segment Itl Waits
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
ACCEPT top_n prompt 'Enter Search Top_n (i.e. 1|10(default)) :'  default '10'

variable bid  number;
variable eid  number;
variable inst_num  number;
variable top_n number;

begin
  :bid  :=  &begin_snap ;
  :eid  :=  &end_snap;
  :top_n:=&top_n;
  :inst_num:=&instance_number;
end;
/

set lines 170
col owner for a15
col tablespace_name for a20
col object_name for a30
col subobject_name for a30
col object_type for a20 heading 'Obj. Type'
col itl_waits for 9999999999999999 heading 'ITL Waits'
col ratio for 99999.99 heading '% of Capture'
/* Formatted on 2013/2/24 22:37:17 (QP5 v5.215.12089.38647) */
SELECT owner,
       tablespace_name,
       object_name,
       subobject_name,
       object_type,
       itl_waits,
       ratio
  FROM (  SELECT n.owner,
                 n.tablespace_name,
                 n.object_name,
                 n.subobject_name,
                 n.object_type,
                 r.itl_waits,
                 ROUND (r.ratio * 100, 2) ratio
            FROM dba_hist_seg_stat_obj n,
                 (  SELECT dataobj#,
                           obj#,
                           dbid,
                           SUM (itl_waits_delta) itl_waits,
                           ratio_to_report (SUM (itl_waits_delta)) OVER () ratio
                      FROM dba_hist_seg_stat
                     WHERE :bid < snap_id AND snap_id <= :eid /*AND dbid = :dbid*/
                           AND instance_number = :inst_num
                  GROUP BY dataobj#, obj#, dbid) r
           WHERE     n.dataobj# = r.dataobj#
                 AND n.obj# = r.obj#
                 AND n.dbid = r.dbid
                 AND r.itl_waits > 0
        ORDER BY r.itl_waits DESC,
                 object_name,
                 owner,
                 subobject_name)
 WHERE ROWNUM <= :top_n
 /
 clear    breaks  
@sqlplusset
