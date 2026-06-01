-- File Name: awr_segment_logical_reads.sql
-- Purpose: Oracle AWR Segment Logical Reads
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
col logical_reads for 9999999999999999 heading 'Logical Reads'
col ratio for 99999.99 heading '% of Capture'
/* Formatted on 2013/2/24 21:54:47 (QP5 v5.215.12089.38647) */
/* Formatted on 2013/2/24 22:02:00 (QP5 v5.215.12089.38647) */
SELECT owner,
       tablespace_name,
       object_name,
       subobject_name,
       object_type,
       logical_reads,
       ratio
  FROM (  SELECT n.owner,
                 n.tablespace_name,
                 n.object_name,
                 n.subobject_name,
                 n.object_type,
                 r.logical_reads,
                 DECODE (d.logical_reads,
                         0, TO_NUMBER (NULL),
                         100 * r.logical_reads / d.logical_reads)
                    ratio
            FROM dba_hist_seg_stat_obj n,
                 (  SELECT dataobj#,
                           obj#,
                           dbid,
                           SUM (logical_reads_delta) logical_reads
                      FROM dba_hist_seg_stat
                     WHERE     :bid < snap_id
                           AND snap_id <= :eid
                           /*AND dbid = :dbid*/
                           AND instance_number = :inst_num
                  GROUP BY dataobj#, obj#, dbid) r,
                 (SELECT SUM (logical_reads_delta) logical_reads
                    FROM dba_hist_seg_stat
                   WHERE     :bid < snap_id
                         AND snap_id <= :eid
                         /*AND dbid = :dbid*/
                         AND instance_number = :inst_num) d
           WHERE     n.dataobj# = r.dataobj#
                 AND n.obj# = r.obj#
                 AND n.dbid = r.dbid
                 AND r.logical_reads > 0
        ORDER BY r.logical_reads DESC,
                 object_name,
                 owner,
                 subobject_name)
 WHERE ROWNUM <= :top_n
 /
 clear    breaks  
@sqlplusset
