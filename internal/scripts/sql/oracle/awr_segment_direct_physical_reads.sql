-- File Name: awr_segment_direct_physical_reads.sql
-- Purpose: Oracle AWR Segment Direct Physical Reads
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
col physical_reads for 9999999999999999 heading 'Direct Physical Reads'
col ratio for 99999.99 heading '% of Capture'
/* Formatted on 2013/2/24 22:22:21 (QP5 v5.215.12089.38647) */
SELECT owner,
       tablespace_name,
       object_name,
       subobject_name,
       object_type,
       physical_reads,
       ratio
  FROM (  SELECT n.owner,
                 n.tablespace_name,
                 n.object_name,
                 n.subobject_name,
                 n.object_type,
                 r.physical_reads,
                 DECODE (d.phyrdir,
                         0, TO_NUMBER (NULL),
                         100 * r.physical_reads / d.phyrdir)
                    ratio
            FROM dba_hist_seg_stat_obj n,
                 (  SELECT dataobj#,
                           obj#,
                           dbid,
                           SUM (physical_reads_direct_delta) physical_reads
                      FROM dba_hist_seg_stat
                     WHERE     :bid < snap_id
                           AND snap_id <= :eid            /*AND dbid = :dbid*/
                           AND instance_number = :inst_num
                  GROUP BY dataobj#, obj#, dbid) r,
                 (SELECT SUM (physical_reads_direct_delta) phyrdir
                    FROM dba_hist_seg_stat
                   WHERE     :bid < snap_id
                         AND snap_id <= :eid              /*AND dbid = :dbid*/
                         AND instance_number = :inst_num) d
           WHERE     n.dataobj# = r.dataobj#
                 AND n.obj# = r.obj#
                 AND n.dbid = r.dbid
                 AND r.physical_reads > 0
        ORDER BY r.physical_reads DESC,
                 object_name,
                 owner,
                 subobject_name)
 WHERE ROWNUM <= :top_n
 /
 clear    breaks  
@sqlplusset
