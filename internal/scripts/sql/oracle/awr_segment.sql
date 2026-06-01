-- File Name: awr_segment.sql
-- Purpose: Oracle AWR Segment
-- Created: 20260516  by  huangtingzhong

@@awr_snapshot_info.sql

set echo off
store set sqlplusset replace
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000

ACCEPT begin_snap prompt 'Enter Search Begin Snapshot  (i.e. 2) : ';
ACCEPT end_snap prompt 'Enter Search End Snapshot  (i.e. 4) : ';
ACCEPT top_n prompt 'Enter Search Top_n (i.e. 1|40(default)) :'  default '40';

PROMPT ------------------------------------------------|
PROMPT |LOGICAL_READS_DELTA                            |
PROMPT |BUFFER_BUSY_WAITS_DELTA                        |
PROMPT |DB_BLOCK_CHANGES_DELTA                         |
PROMPT |PHYSICAL_READS_DELTA                           |
PROMPT |PHYSICAL_WRITES_DELTA                          |
PROMPT |PHYSICAL_READS_DIRECT_DELTA                    |
PROMPT |PHYSICAL_WRITES_DIRECT_DELTA                   |
PROMPT |ITL_WAITS_DELTA                                |
PROMPT |ROW_LOCK_WAITS_DELTA                           |
PROMPT |GC_CR_BLOCKS_SERVED_DELTA                      |
PROMPT |GC_CU_BLOCKS_SERVED_DELTA                      |
PROMPT |GC_BUFFER_BUSY_DELTA                           |
PROMPT |GC_CR_BLOCKS_RECEIVED_DELTA                    |
PROMPT |GC_CU_BLOCKS_RECEIVED_DELTA                    |
PROMPT |SPACE_USED_DELTA                               |
PROMPT |SPACE_ALLOCATED_DELTA                          |
PROMPT |TABLE_SCANS_DELTA                              |  
PROMPT |LOGICAL_READS_DELTA                            |  
PROMPT -------------------------------------------------

ACCEPT stat_name prompt 'Enter Search Top_n (i.e. LOGICAL_READS_DELTA)) :'  default 'LOGICAL_READS_DELTA';
variable bid  number;
variable eid  number;
variable inst_num  number;
variable top_n number;
variable stat_name varchar2(100);

begin
  :bid  :=  &begin_snap ;
  :eid  :=  &end_snap;
  :top_n:=  &top_n;
  :stat_name:= '&stat_name';
end;
/

col object format a100
col i format 99
/* Formatted on 2013/2/28 15:23:40 (QP5 v5.215.12089.38647) */
SELECT *
  FROM (  SELECT    o.owner
                 || '.'
                 || o.object_name
                 || DECODE (o.subobject_name, NULL, '', '.')
                 || o.subobject_name
                 || ' ['
                 || o.object_type
                 || ']'
                    object,
                 instance_number i,
                 stat
            FROM (  SELECT obj# || '.' || dataobj# obj#,
                           instance_number,
                           SUM (&stat_name) stat
                      FROM dba_hist_seg_stat
                     WHERE     (snap_id BETWEEN :bid AND :eid)
                           AND (instance_number BETWEEN 1 AND 6)
                  GROUP BY ROLLUP (obj# || '.' || dataobj#, instance_number)
                    HAVING obj# || '.' || dataobj# IS NOT NULL) s,
                 dba_hist_seg_stat_obj o
           WHERE o.dataobj# || '.' || o.obj# = s.obj#
        ORDER BY MAX (stat) OVER (PARTITION BY s.obj#) DESC,
                 o.owner || o.object_name || o.subobject_name,
                 NVL (instance_number, 0))
 WHERE ROWNUM <= :top_n
 /
set lines 170
col owner for a15
col tablespace_name for a20
col object_name for a30
col subobject_name for a30
col object_type for a20 heading 'Obj. Type'
col db_block_changes for 9999999999999999 heading 'DB Blocks Changes'
col ratio for 99999.99 heading '% of Capture'

 clear    breaks  
@sqlplusset
