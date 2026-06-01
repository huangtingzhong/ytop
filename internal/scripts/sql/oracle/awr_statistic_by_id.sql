-- File Name: awr_statistic_by_id.sql
-- Purpose: Oracle AWR Statistic By Id
-- Created: 20260516  by  huangtingzhong

set lines 1000
set trimspool on
set pages 50000
set feedback off


clear break compute;
repfooter off;
ttitle off;
btitle off;
set timing off veri off space 1 flush on pause off termout on numwidth 10;
set echo off feedback off pagesize 50000 linesize 1000 newpage 1 recsep off;
set trimspool on trimout on;

-- 
-- Request the DB Id and Instance Number, if they are not specified

column instt_num  heading "Inst Num"  format 99999;
column instt_name heading "Instance"  format a12;
column dbb_name   heading "DB Name"   format a12;
column dbbid      heading "DB Id"     format a12 just c;
column host       heading "Host"      format a20;

prompt
prompt 
prompt Instances in this Workload Repository schema
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
select distinct
       (case when cd.dbid = wr.dbid and 
                  cd.name = wr.db_name and
                  ci.instance_number = wr.instance_number and
                  ci.instance_name   = wr.instance_name
             then '* '
             else '  '
        end) || wr.dbid   dbbid
     , wr.instance_number instt_num
     , wr.db_name         dbb_name
     , wr.instance_name   inst_name
     , wr.host_name       host
  from dba_hist_database_instance wr, v$database cd, v$instance ci;

prompt 
prompt Using &&dbid for database Id


-- 
--  Set up the binds for dbid and instance_number

variable dbid       number;
begin
  :dbid      :=  &dbid;
end;
/


--  Error reporting

whenever sqlerror exit;
variable max_snap_time char(10);
declare

  cursor cidnum is
     select 'X'
       from dba_hist_database_instance
      where dbid            = :dbid;

  cursor csnapid is
     select to_char(max(end_interval_time),'dd/mm/yyyy')
       from dba_hist_snapshot
      where dbid            = :dbid;

  vx     char(1);

begin

  -- Check Database Id/Instance Number is a valid pair
  open cidnum;
  fetch cidnum into vx;
  if cidnum%notfound then
    raise_application_error(-20200,
      'Database/Instance ' || :dbid || '/' || 
      ' does not exist in DBA_HIST_DATABASE_INSTANCE');
  end if;
  close cidnum;

  -- Check Snapshots exist for Database Id/Instance Number
  open csnapid;
  fetch csnapid into :max_snap_time;
  if csnapid%notfound then
    raise_application_error(-20200,
      'No snapshots exist for Database/Instance '||:dbid||'/');
  end if;
  close csnapid;

end;
/
whenever sqlerror continue;


-- 
--  Ask how many days of snapshots to display

set termout on;
column instart_fmt noprint;
column inst_name   format a12  heading 'Instance';
column db_name     format a12  heading 'DB Name';
column snap_id     format 99999990 heading 'Snap Id';
column snapdat     format a18  heading 'Snap Started' just c;
column lvl         format 99   heading 'Snap|Level';


prompt
prompt
prompt Specify the number of days of snapshots to choose from
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt Entering the number of days (n) will result in the most recent
prompt (n) days of snapshots being listed.  Pressing <return> without
prompt specifying a number lists all completed snapshots.
prompt
prompt

set heading off;
column num_days new_value num_days noprint;
select    'Listing '
       || decode( nvl('&&num_days', 3.14)
                , 0    , 'no snapshots'
                , 3.14 , 'all Completed Snapshots'
                , 1    , 'the last day''s Completed Snapshots'
                , 'the last &num_days days of Completed Snapshots')
     , nvl('&&num_days', 3.14)  num_days
  from sys.dual;
set heading on;

-- 
-- List available snapshots

break on inst_name on db_name on host on instart_fmt skip 1;

ttitle off;

select to_char(s.startup_time,'dd Mon "at" HH24:mi:ss')  instart_fmt
     , di.instance_name                                  inst_name
     , di.db_name                                        db_name
     , s.snap_id                                         snap_id
     , to_char(s.end_interval_time,'dd Mon YYYY HH24:mi') snapdat
     , s.snap_level                                      lvl
  from dba_hist_snapshot s
     , dba_hist_database_instance di
 where s.dbid              = :dbid
   and di.dbid             = :dbid
   and di.dbid             = s.dbid
   and di.instance_number  = s.instance_number
   and di.startup_time     = s.startup_time
   and s.end_interval_time >= decode( &num_days
                                   , 0   , to_date('31-JAN-9999','DD-MON-YYYY')
                                   , 3.14, s.end_interval_time
                                   , to_date(:max_snap_time,'dd/mm/yyyy') - (&num_days-1))
 order by db_name, instance_name, snap_id;

clear break;
ttitle off;


-- 
--  Ask for the snapshots Id's which are to be compared

prompt
prompt
prompt Specify the Begin and End Snapshot Ids
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt Begin Snapshot Id specified: &&begin_snap
prompt
prompt End   Snapshot Id specified: &&end_snap
prompt


-- 
--  Set up the snapshot-related binds

variable bid        number;
variable eid        number;
begin
  :bid       :=  &begin_snap;
  :eid       :=  &end_snap;
end;
/

prompt

column STAT_ID    heading "Statistic ID"    format 9999999999999;
column NAME       heading "Statistic Name"  format a64;
column CLASS_NAME heading "Statistic Name"  format a10;

select STAT_ID
     , ( CASE WHEN CLASS = 1   THEN 'USER' 
              WHEN CLASS = 2   THEN 'REDO'
              WHEN CLASS = 4   THEN 'ENQUEUE'  
              WHEN CLASS = 8   THEN 'CACHE'
              WHEN CLASS = 16  THEN 'OS'
              WHEN CLASS = 32  THEN 'RAC'
              WHEN CLASS = 40  THEN 'RAC-CACHE'
              WHEN CLASS = 64  THEN 'SQL'
              WHEN CLASS = 72  THEN 'SQL-CACHE'
              WHEN CLASS = 128 THEN 'DEBUG'
              ELSE TO_CHAR(CLASS)
         END 
       ) CLASS_NAME
     , NAME
  from V$SYSSTAT
 order by CLASS, NAME
/

-- 
--  Ask for the statistics

prompt
prompt
prompt Specify the Statistics
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt Begin Statistics Id specified: &&stat_id
prompt

variable stat_id number;

begin
  :stat_id := &stat_id;
end;
/


column END_INTERVAL_TIME     heading 'Snap Started' format a18 just c;
column DBID                  heading 'DB Id'  format a12 just c;
column INSTANCE_NUMBER       heading 'Inst Num'  format 99999;
column ELAPSED               heading 'Elapsed' format 999999;
column STAT_VALUE            heading 'Stat Value' format 999999999999

SELECT SNAP_ID 
     , TO_CHAR(DBID) DBID
     , INSTANCE_NUMBER 
     , ELAPSED 
     , to_char(END_INTERVAL_TIME,'dd Mon YYYY HH24:mi')   END_INTERVAL_TIME
     , (CASE WHEN STAT_VALUE > 0 THEN STAT_VALUE ELSE 0 END ) STAT_VALUE
  FROM (
  SELECT SNAP_ID 
       , DBID 
       , INSTANCE_NUMBER 
       , ELAPSED 
       , END_INTERVAL_TIME 
       , ( STAT_VALUE
           -  LAG ( STAT_VALUE , 1 , STAT_VALUE) 
             OVER (PARTITION BY DBID, INSTANCE_NUMBER ORDER BY SNAP_ID)
         ) AS STAT_VALUE
  FROM ( 
    SELECT SNAP_ID              
         , DBID                 
         , INSTANCE_NUMBER      
         , ELAPSED              
         , END_INTERVAL_TIME    
         , SUM(STAT_VALUE) AS STAT_VALUE
    FROM (  SELECT  X.SNAP_ID                                              
                  ,  X.DBID                                                 
                  ,  X.INSTANCE_NUMBER                                      
                  ,  TRUNC(SN.END_INTERVAL_TIME,'mi') END_INTERVAL_TIME   
                  ,  trunc((
                            cast(SN.END_INTERVAL_TIME as date) 
                           - 
                            cast(SN.BEGIN_INTERVAL_TIME as date)
                           )*86400) ELAPSED 
                  , (CASE WHEN X.STAT_ID = :stat_id
                          THEN X.VALUE ELSE 0 END) AS STAT_VALUE
               FROM DBA_HIST_SYSSTAT X 
                  , DBA_HIST_SNAPSHOT SN 
                  , (SELECT INSTANCE_NUMBER, MIN(STARTUP_TIME) STARTUP_TIME 
                       FROM DBA_HIST_SNAPSHOT 
                      WHERE SNAP_ID BETWEEN :bid AND :eid
                      GROUP BY INSTANCE_NUMBER
                    ) MS 
              WHERE X.snap_id = sn.snap_id 
                AND X.dbid = sn.dbid 
                and x.dbid = :dbid
                AND x.snap_id between :bid and :eid
                AND SN.startup_time = MS.startup_time 
                AND SN.instance_number = MS.instance_number 
                AND X.instance_number = sn.instance_number 
                AND X.stat_id = :stat_id
         ) 
   GROUP BY SNAP_ID,           
            DBID,              
            INSTANCE_NUMBER,   
            ELAPSED,           
            END_INTERVAL_TIME  
       )
     )
/



undefine dbid       
undefine num_days
undefine begin_snap
undefine end_snap
undefine stat_id 