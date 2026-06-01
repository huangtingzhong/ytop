-- File Name: awr_sysstat_interval.sql
-- Purpose: Oracle AWR Sysstat Interval
-- Created: 20260516  by  huangtingzhong

@awr_snapshot_info
set serveroutput on
set lines 200
set echo off
ACCEPT bid prompt 'Enter Search Begin Snap Id (i.e. 2)) : ' 
ACCEPT eid prompt 'Enter Search End Snap Id (i.e. 4)) : ' 
ACCEPT interval  prompt 'Enter Search Interval Number (i.e. 1)) : '  default '1'
ACCEPT stat_name prompt 'Enter Search Login (i.e. 4)) : ' 
DECLARE
   -- Adjust before use.
   l_snap_start        NUMBER := &bid;
   l_snap_end          NUMBER := &eid;
   l_last_snap         NUMBER := NULL;
   interval            number := &interval;
   l_dbid              v$database.dbid%TYPE;
   l_instance_number   v$instance.instance_number%TYPE;
BEGIN
   SELECT dbid INTO l_dbid FROM v$database;
   SELECT instance_number INTO l_instance_number FROM v$instance;
   SELECT l_snap_start + interval INTO l_last_snap FROM DUAL;
   DBMS_OUTPUT.put_line (
         RPAD ('DBID', 15)
      || RPAD ('INST_NUM', 15)
      || RPAD ('SNAP_ID', 15)
      || RPAD ('SNAP_END_TIME', 25)
      || RPAD ('STAT_NAME', 50)
      || RPAD ('VALUE', 30));

   WHILE l_last_snap <= l_snap_end
   LOOP
      FOR cur_rep
         IN (  SELECT DISTINCT
                      b.dbid,
                      b.instance_number,
                      e.snap_id,
                      TO_CHAR (C.END_INTERVAL_TIME, 'yyyy-mm-dd hh24:mi:ss')
                         end_time,
                      b.stat_name,
                      e.VALUE - b.VALUE VALUE
                 FROM dba_hist_sysstat b,
                      dba_hist_sysstat e,
                      DBA_HIST_SNAPSHOT C
                WHERE     b.dbid = e.dbid
                      AND b.instance_number = e.instance_number
                      AND b.instance_number = l_instance_number
                      AND b.snap_id = l_snap_start
                      AND e.snap_id = l_last_snap
                      AND b.stat_name = e.stat_name
                      AND e.snap_id = c.snap_id
                      AND b.stat_name LIKE '&stat_name'
             ORDER BY 3)
      LOOP
         DBMS_OUTPUT.put_line (
               RPAD (cur_rep.DBID, 15)
            || RPAD (cur_rep.instance_number, 15)
            || RPAD (cur_rep.snap_id, 15)
            || RPAD (cur_rep.end_time, 25)
            || RPAD (cur_rep.stat_name, 50)
            || RPAD (cur_rep.VALUE, 30));
      END LOOP;
      l_snap_start := l_last_snap;
      l_last_snap := l_last_snap + interval;
   END LOOP;
END;
/