-- File Name: awr_segment_row_lock_waits.sql
-- Purpose: Oracle AWR Segment Row Lock Waits
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
ACCEPT top_n prompt 'Enter Search Top_n (i.e. 1|10(default)) :'  default '10'

variable begin_snap  number;
variable end_snap  number;
variable instance_number  number;

begin
  :begin_snap  :=  &begin_snap ;
  :end_snap  :=  &end_snap;
  :top_n:=&top_n;
end;
/

set lines 170
col owner for a15
col tablespace_name for a20
col object_name for a30
col subobject_name for a30
col object_type for a20 heading 'Obj. Type'
col row_lock_waits for 9999999999999999 heading 'Row Lock Waits'
col ratio for 99999.99 heading '% of Capture'

/* Formatted on 2013/2/24 20:55:39 (QP5 v5.215.12089.38647) */
SELECT owner,
       tablespace_name,
       object_name,
       subobject_name,
       object_type,
       row_lock_waits,
       ratio
  FROM (  SELECT n.owner,
                 n.tablespace_name,
                 n.object_name,
                 n.subobject_name,
                 n.object_type,
                 r.row_lock_waits,
                 ROUND (r.ratio * 100, 2) ratio
            FROM dba_hist_seg_stat_obj n,
                 (  SELECT dataobj#,
                           obj#,
                           dbid,
                           SUM (row_lock_waits_delta) row_lock_waits,
                           ratio_to_report (SUM (row_lock_waits_delta)) OVER ()
                              ratio
                      FROM dba_hist_seg_stat
                     WHERE :bid < snap_id AND snap_id <= :eid /*AND dbid = :dbid*/
                           AND instance_number = :inst_num
                  GROUP BY dataobj#, obj#, dbid) r
           WHERE     n.dataobj# = r.dataobj#
                 AND n.obj# = r.obj#
                 AND n.dbid = r.dbid
                 AND r.row_lock_waits > 0
        ORDER BY r.row_lock_waits DESC,
                 object_name,
                 owner,
                 subobject_name)
 WHERE ROWNUM <= :top_n
 /
 clear    breaks  
@sqlplusset
