-- File Name: awr_generate_report_html.sql
-- Purpose: Oracle AWR Generate Report Html
-- Created: 20260516  by  huangtingzhong

ACCEPT directory prompt 'Enter Search Directory (i.e. /tmp(default)) : ' default '/tmp'
CREATE OR REPLACE DIRECTORY awr_reports_dir AS '&directory';
grant read,write on directory awr_reports_dir to sys;
@awr_snapshot_info
ACCEPT bid prompt 'Enter Search Begin Snap Id (i.e. 2)) : ' 
ACCEPT eid prompt 'Enter Search End Snap Id (i.e. 4)) : ' 
DECLARE
  -- Adjust before use.
  l_snap_start       NUMBER := &bid;
  l_snap_end         NUMBER := &eid;
  l_dir              VARCHAR2(50) := 'AWR_REPORTS_DIR';
  
  l_last_snap        NUMBER := NULL;
  l_dbid             v$database.dbid%TYPE;
  l_instance_number  v$instance.instance_number%TYPE;
  l_file             UTL_FILE.file_type;
  l_file_name        VARCHAR(50);

BEGIN
  SELECT dbid
  INTO   l_dbid
  FROM   v$database;

  SELECT instance_number
  INTO   l_instance_number
  FROM   v$instance;
    
  FOR cur_snap IN (SELECT snap_id,to_char(end_interval_time,'yyyymmddhh24') time
                   FROM   dba_hist_snapshot
                   WHERE  instance_number = l_instance_number
                   AND    snap_id BETWEEN l_snap_start AND l_snap_end
                   ORDER BY snap_id)
  LOOP
    IF l_last_snap IS NOT NULL THEN
      l_file := UTL_FILE.fopen(l_dir, 'awr_' || l_last_snap || '_' || cur_snap.time|| '.htm', 'w', 32767);
      
      FOR cur_rep IN (SELECT output
                      FROM   TABLE(DBMS_WORKLOAD_REPOSITORY.awr_report_html(l_dbid, l_instance_number, l_last_snap, cur_snap.snap_id)))
      LOOP
        UTL_FILE.put_line(l_file, cur_rep.output);
      END LOOP;
      UTL_FILE.fclose(l_file);
    END IF;
    l_last_snap := cur_snap.snap_id;
  END LOOP;
  
EXCEPTION
  WHEN OTHERS THEN
    IF UTL_FILE.is_open(l_file) THEN
      UTL_FILE.fclose(l_file);
    END IF;
    RAISE; 
END;
/
drop DIRECTORY awr_reports_dir;
