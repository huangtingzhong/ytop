-- File Name: awr_segment_gc_buffer_busy.sql
-- Purpose: Oracle AWR Segment Gc Buffer Busy
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info.sql
set echo off
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
col logical_reads for 9999999999999999 heading 'Logical Reads'
col ratio for 99999.99 heading '% of Capture'

SELECT owner,
       tablespace_name,
       object_name,
       subobject_name,
       object_type,
       GC_BUFFER_BUSY,
       ratio
  FROM (  SELECT n.owner,
                 n.tablespace_name,
                 n.object_name,
                 n.subobject_name,
                 n.object_type,
                 r.GC_BUFFER_BUSY,
                 ROUND (r.ratio * 100, 2) ratio
            FROM dba_hist_seg_stat_obj n,
                 (  SELECT dataobj#,
                           obj#,
                           dbid,
                           SUM (GC_BUFFER_BUSY_delta) GC_BUFFER_BUSY,
                           ratio_to_report (SUM (GC_BUFFER_BUSY_delta)) OVER () ratio
                      FROM dba_hist_seg_stat
                     WHERE     :bid < snap_id
                           AND snap_id <= :eid            /*AND dbid = :dbid*/
                           AND instance_number = :inst_num
                  GROUP BY dataobj#, obj#, dbid) r
           WHERE     n.dataobj# = r.dataobj#
                 AND n.obj# = r.obj#
                 AND n.dbid = r.dbid
                 AND r.GC_BUFFER_BUSY > 0
        ORDER BY r.GC_BUFFER_BUSY DESC,
                 object_name,
                 owner,
                 subobject_name)
 WHERE ROWNUM <= :top_n
/