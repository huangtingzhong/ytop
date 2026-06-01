-- File Name: awr_miner.sql
-- Purpose: Oracle AWR Miner
-- Created: 20260516  by  huangtingzhong

SET CONCAT ~
col con_name format a30 new_value con_name
col con_id format a30 new_value con_id
set termout off


select case when substr(version, 1,instr(version, '.') - 1) > 11 then
        (SELECT sys_context('USERENV', 'CON_ID') con_id FROM DUAL)
	   else
		(SELECT '0' FROM DUAL)
	   end con_id from v$instance;

select case when substr(version, 1,instr(version, '.') - 1) > 11 then
        (SELECT REGEXP_REPLACE(sys_context('USERENV', 'CON_NAME'),'^(.+?)@.+$','\1') FROM DUAL)
	   else
		(SELECT '' FROM DUAL)
	   end con_name from v$instance;

define SQL_TOP_N = 100
define CAPTURE_HOST_NAMES = 'YES'
define DBV = 'DBA'
-- Last n days of data to capture.
define NUM_DAYS = 30
-- Only change the DATE_BEGIN | END parameters to filter to a certain range.
-- For 99% of the use-cases, just leave these parameters alone. 
-- If DATE_BEGIN is changed, NUM_DAYS is ignored
-- Date Format YYYY-MM-DD
define DATE_BEGIN = '2000-01-01'
define DATE_END   = '2040-01-01'

set define '&'
set concat '~'
set colsep " "
SET UNDERLINE '-'
set pagesize 50000
SET ARRAYSIZE 5000
REPHEADER OFF
REPFOOTER OFF


define AWR_MINER_VER = 5.22.3


set termout off
alter session set optimizer_dynamic_sampling=4;
alter session set workarea_size_policy = manual;
alter session set sort_area_size = 268435456;
alter session set NLS_LENGTH_SEMANTICS=BYTE;
alter session set cursor_sharing = exact;
alter session set NLS_DATE_FORMAT = 'yyyy-mm-dd HH24:mi:ss';
alter session set NLS_TIMESTAMP_FORMAT = 'yyyy-mm-dd HH24:mi:ss';



col dbv format a30 new_value dbv
select decode(&con_id, 0, 'DBA','CDB') DBV from dual;


whenever sqlerror continue

set termout on

set timing off

set serveroutput on
set verify off

column cnt_dbid_1 new_value CNT_DBID noprint
SELECT count(DISTINCT dbid) cnt_dbid_1
	FROM &DBV~_hist_database_instance;


define DBID = ' ' 
column :DBID_1 new_value DBID noprint
variable DBID_1 varchar2(30)

define DB_VERSION = 0
column :DB_VERSION_1 new_value DB_VERSION noprint
variable DB_VERSION_1 number

prompt  ---------------------------------------------------

prompt |              _                                  |

prompt |  /\   |  |  |_)    |\/|  o   _    _   ,_        |

prompt | /--\  |/\|  | \    |  |  |  | |  (/_  |  5.22.3 |

prompt  ---------------------------------------------------


set feedback off
declare
	version_gte_11_2	varchar2(30);
	l_sql			varchar2(32767);
	l_variables	        varchar2(1000) := ' ';
	l_block_size		number;

	c2   SYS_REFCURSOR;
	type name_con_dbid_rt is record(
		name varchar2(128),
		con_id number,
		dbid number
	);
	type name_con_dbid_aat is table of name_con_dbid_rt 
		index by PLS_INTEGER;
	l_containers 	name_con_dbid_aat;
	
begin

	:DB_VERSION_1 :=  dbms_db_version.version + (dbms_db_version.release / 10);
    dbms_output.put_line('=================================================');
	dbms_output.put_line('Database IDs in this Repository:');
	
	
    if :DB_VERSION_1 <12.1 then	
		for c1 in (select /*+noparallel */ distinct dbid,db_name FROM dba_hist_database_instance order by db_name)
		loop
			dbms_output.put_line(rpad(c1.dbid,35)||c1.db_name);
		end loop; --c1
			
		if to_number(&CNT_DBID) > 1 then
			null  ;
	    else
		
		    SELECT /*+noparallel */ DISTINCT dbid into :DBID_1
					 FROM dba_hist_database_instance
					where rownum = 1;
		end if;
	end if;
	
 
    if :DB_VERSION_1 >=12.1 then	
	    l_sql := 'SELECT NAME, CON_ID, DBID FROM V$CONTAINERS ORDER BY CON_ID';
		open c2 for l_sql;		
		fetch c2 BULK COLLECT into l_containers;
			
		close c2;
			
		for indx in 1..l_containers.COUNT
			loop
				dbms_output.put_line(rpad(l_containers(indx).dbid,35)||l_containers(indx).name||' '||l_containers(indx).con_id);
				if l_containers(indx).con_id=&con_id then
					select l_containers(indx).dbid into :DBID_1 from dual;
				end if;
  		    end loop;
  	end if;
       
	
	--l_variables := l_variables||'ver_gte_11_2:TRUE';
	
	if :DB_VERSION_1  >= 11.2 then
		l_variables := l_variables||'ver_gte_11_2:TRUE';
	else
		l_variables := l_variables||'ver_gte_11_2:FALSE';
	end if;
	
	if :DB_VERSION_1  >= 11.1 then
		l_variables := l_variables||',ver_gte_11_1:TRUE';
	else
		l_variables := l_variables||',ver_gte_11_1:FALSE';
	end if;
	
	--alter session set plsql_ccflags = 'debug_flag:true';
	l_sql := q'[alter session set plsql_ccflags =']'||l_variables||q'[']';
	
	
	
	execute immediate l_sql;
	dbms_output.put_line('=================================================');

end;
/

select :DBID_1 from dual;
select :DB_VERSION_1 from dual;



accept DBID2 CHAR prompt 'Which dbid would you like to use? [&DBID] '

column DBID_2 new_value DBID noprint

select case when length('&DBID2') > 3 then '&DBID2' else '&DBID' end DBID_2 from dual;

column :con_name_1 new_value con_name noprint
variable con_name_1 varchar2(30)

declare
	l_sql			varchar2(32767);
begin
    if :DB_VERSION_1 >=12.1 then	
		execute immediate 'SELECT  name from v$containers where dbid=&DBID' into :con_name_1;
	end if;
end;
/

select :con_name_1 from dual;


whenever sqlerror exit
set serveroutput on
begin
    if length('&DBID') > 4 then
		null;
	else
        dbms_output.put_line('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        dbms_output.put_line('You must choose a database ID.');
        dbms_output.put_line('This script will now exit.');
		dbms_output.put_line('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        execute immediate 'bogus statement to force exit';
    end if;
end;
/

whenever sqlerror continue

prompt
prompt

prompt **************************************************************************
prompt *Do NOT change the file name of the .out file generated by this script!  *
prompt *Do NOT edit the output file in any way!                                 *
prompt *Either type of change will result in failure to parse the output later. * 
prompt **************************************************************************

!sleep 3


REM set heading off

select '&DBID' a from dual;


column db_name1 new_value DBNAME
prompt Will export AWR data for the following Database:

select case when substr(version, 1,instr(version, '.') - 1) > 11 then
       (SELECT decode('&con_name','CDB$ROOT',db_name,'&con_name') db_name1 FROM &DBV~_hist_database_instance where dbid = '&DBID' and rownum = 1)
     else
 		(SELECT db_name FROM dba_hist_database_instance where dbid = '&DBID' and rownum = 1)
 	 end db_name1 from v$instance;


define T_WAITED_MICRO_COL = 'TIME_WAITED_MICRO' 
column :T_WAITED_MICRO_COL_1 new_value T_WAITED_MICRO_COL noprint
variable T_WAITED_MICRO_COL_1 varchar2(30)

begin
	if :DB_VERSION_1  >= 11.1 then
		:T_WAITED_MICRO_COL_1 := 'TIME_WAITED_MICRO_FG';
	else
		:T_WAITED_MICRO_COL_1 := 'TIME_WAITED_MICRO';
	end if;

end;
/

select :T_WAITED_MICRO_COL_1 from dual;

define DB_BLOCK_SIZE = 0
column :DB_BLOCK_SIZE_1 new_value DB_BLOCK_SIZE noprint
variable DB_BLOCK_SIZE_1 number



set feedback off
begin

	:DB_BLOCK_SIZE_1 := 0;

	for c1 in (
		with inst as (
		select min(instance_number) inst_num
		  from &DBV~_hist_snapshot
		  where dbid = &DBID
			)
		SELECT VALUE the_block_size
			FROM &DBV~_HIST_PARAMETER
			WHERE dbid = &DBID
			and PARAMETER_NAME = 'db_block_size'
			AND snap_id = (SELECT MAX(snap_id) FROM &DBV~_hist_osstat WHERE dbid = &DBID AND instance_number = (select inst_num from inst))
		   AND instance_number = (select inst_num from inst))
	loop
		:DB_BLOCK_SIZE_1 := c1.the_block_size;
	end loop; --c1
	
	if :DB_BLOCK_SIZE_1 = 0 then
		:DB_BLOCK_SIZE_1 := 8192;
	end if;


end;
/

select :DB_BLOCK_SIZE_1 from dual;

--column snap_min1 new_value SNAP_ID_MIN noprint
column snap_min1 new_value SNAP_ID_MIN


SELECT min(snap_id) - 1 snap_min1
  FROM &DBV~_hist_snapshot
  WHERE dbid = &DBID 
    and (
			(
			'&DATE_BEGIN' = '2000-01-01'
			and
			begin_interval_time > (
			SELECT max(begin_interval_time) - &NUM_DAYS
			  FROM &DBV~_hist_snapshot 
			  where dbid = &DBID)
			 )
		or
			('&DATE_BEGIN' != '2000-01-01'
			 and
			 begin_interval_time >= trunc(to_date('&DATE_BEGIN','YYYY-MM-DD'))
			)
		)
	 ;
		  
		  
select '&DBV' from dual where '&DATE_BEGIN' = '2000-01-01';

		  
column snap_max1 new_value SNAP_ID_MAX noprint
SELECT max(snap_id) snap_max1
  FROM &DBV~_hist_snapshot
  WHERE dbid = &DBID
  and begin_interval_time < trunc(to_date('&DATE_END','YYYY-MM-DD'))+1 
  and ('&DATE_BEGIN' = '2000-01-01'
	   or
		   (
		   '&DATE_BEGIN' != '2000-01-01'
			 and
			 begin_interval_time >= trunc(to_date('&DATE_BEGIN','YYYY-MM-DD'))
		   )
	   );

prompt
rem prompt &SNAP_ID_MIN
rem prompt &SNAP_ID_MAX
rem prompt &NUM_DAYS

whenever sqlerror exit
set serveroutput on
begin
    if length('&DBID') > 4 then
		null;
	else
        dbms_output.put_line('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        dbms_output.put_line('You must choose a database ID.');
        dbms_output.put_line('This script will now exit.');
		dbms_output.put_line('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        execute immediate 'bogus statement to force exit';
    end if;
end;
/

whenever sqlerror continue


whenever sqlerror exit
set serveroutput on
declare
	l_snapshot_count number := 0;
begin
	for c1 in (SELECT count(*) cnt
				 FROM &DBV~_hist_snapshot
				WHERE dbid = &DBID)
	loop
		l_snapshot_count := c1.cnt;
	end loop; --c1



    if l_snapshot_count > 2 then
		null;
	else
        dbms_output.put_line('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        dbms_output.put_line('There is no AWR data for this DBID');
        dbms_output.put_line('This script will now exit.');
		dbms_output.put_line('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        execute immediate 'bogus statement to force exit';
    end if;
end;
/

whenever sqlerror continue


whenever sqlerror exit
set serveroutput on

begin
	if length(REGEXP_REPLACE('&SNAP_ID_MIN','[[:space:]]','')) > 0 and
	   length(REGEXP_REPLACE('&SNAP_ID_MAX','[[:space:]]','')) > 0 then
		null;
	else
        dbms_output.put_line('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        dbms_output.put_line('The chosen date range doesn''t contain any data.');
        dbms_output.put_line('This script will now exit.');
		dbms_output.put_line('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
        execute immediate 'bogus statement to force exit';
    end if;
end;
/


whenever sqlerror continue


 
column FILE_NAME new_value SPOOL_FILE_NAME noprint
select 'awr-hist-'||'&DBID'||'-'||'&DBNAME'||'-'||ltrim('&SNAP_ID_MIN')||'-'||ltrim('&SNAP_ID_MAX')||'.out' FILE_NAME from dual;


set timing on
TIMING START full_capture_script
spool &SPOOL_FILE_NAME


-- ##############################################################################################
REPHEADER ON
REPFOOTER ON 

set linesize 1000 
set numwidth 10
set wrap off
set heading on
set trimspool on
set feedback off




set serveroutput on
DECLARE
    l_pad_length number :=60;
	l_hosts	varchar2(4000);
	l_dbid	number;
BEGIN


    dbms_output.put_line('~~BEGIN-OS-INFORMATION~~');
    dbms_output.put_line(rpad('STAT_NAME',l_pad_length)||' '||'STAT_VALUE');
    dbms_output.put_line(rpad('-',l_pad_length,'-')||' '||rpad('-',l_pad_length,'-'));
    
    FOR c1 IN (
			with inst as (
		select min(instance_number) inst_num
		  from &DBV~_hist_snapshot
		  where dbid = &DBID
			and snap_id BETWEEN to_number(&SNAP_ID_MIN) and to_number(&SNAP_ID_MAX))
	SELECT 
                      CASE WHEN stat_name = 'PHYSICAL_MEMORY_BYTES' THEN 'PHYSICAL_MEMORY_GB' ELSE stat_name END stat_name,
                      CASE WHEN stat_name IN ('PHYSICAL_MEMORY_BYTES') THEN round(VALUE/1024/1024/1024,2) ELSE VALUE END stat_value
                  FROM &DBV~_hist_osstat 
                 WHERE dbid = &DBID 
                   AND snap_id = (SELECT MAX(snap_id) FROM &DBV~_hist_osstat WHERE dbid = &DBID AND instance_number = (select inst_num from inst))
				   AND instance_number = (select inst_num from inst)
                   AND (stat_name LIKE 'NUM_CPU%'
                   OR stat_name IN ('PHYSICAL_MEMORY_BYTES')))
    loop
        dbms_output.put_line(rpad(c1.stat_name,l_pad_length)||' '||c1.stat_value);
    end loop; --c1
    
	for c1 in (SELECT CPU_COUNT,CPU_CORE_COUNT,CPU_SOCKET_COUNT
				 FROM &DBV~_CPU_USAGE_STATISTICS 
				where dbid = &DBID
				  and TIMESTAMP = (select max(TIMESTAMP) from &DBV~_CPU_USAGE_STATISTICS where dbid = &DBID )
				  AND ROWNUM = 1)
	loop
		dbms_output.put_line(rpad('!CPU_COUNT',l_pad_length)||' '||c1.CPU_COUNT);
		dbms_output.put_line(rpad('!CPU_CORE_COUNT',l_pad_length)||' '||c1.CPU_CORE_COUNT);
		dbms_output.put_line(rpad('!CPU_SOCKET_COUNT',l_pad_length)||' '||c1.CPU_SOCKET_COUNT);
	end loop;
	
	for c1 in (SELECT distinct platform_name FROM sys.GV_$DATABASE 
				where dbid = &DBID
				and rownum = 1)
	loop
		dbms_output.put_line(rpad('!PLATFORM_NAME',l_pad_length)||' '||c1.platform_name);
	end loop;

	
	
	FOR c2 IN (SELECT 
						$IF $$VER_GTE_11_2 $THEN
							REPLACE(platform_name,' ','_') platform_name,
						$ELSE
							'None' platform_name,
						$END
						VERSION,db_name,DBID FROM &DBV~_hist_database_instance 
						WHERE dbid = &DBID  
						and startup_time = (select max(startup_time) from &DBV~_hist_database_instance WHERE dbid = &DBID )
						AND ROWNUM = 1)
    loop
        dbms_output.put_line(rpad('PLATFORM_NAME',l_pad_length)||' '||c2.platform_name);
        dbms_output.put_line(rpad('VERSION',l_pad_length)||' '||c2.VERSION);
		IF substr(c2.VERSION, 1,instr(c2.VERSION, '.') - 1) > 11 THEN
			dbms_output.put_line(rpad('DB_NAME',l_pad_length)||' '||'&con_name');
			dbms_output.put_line(rpad('CDB_NAME',l_pad_length)||' '||c2.db_name);
		ELSE
			dbms_output.put_line(rpad('DB_NAME',l_pad_length)||' '||c2.db_name);
		END IF;
        dbms_output.put_line(rpad('DBID',l_pad_length)||' '||c2.DBID);
    end loop; --c2
    
    FOR c3 IN (SELECT count(distinct s.instance_number) instances
			     FROM &DBV~_hist_database_instance i,&DBV~_hist_snapshot s
				WHERE i.dbid = s.dbid
				  and i.dbid = &DBID
				  AND s.snap_id BETWEEN &SNAP_ID_MIN AND &SNAP_ID_MAX)
    loop
        dbms_output.put_line(rpad('INSTANCES',l_pad_length)||' '||c3.instances);
    end loop; --c3           
	
	
	FOR c4 IN (SELECT distinct regexp_replace(host_name,'^([[:alnum:]]+)\..*$','\1')  host_name 
			     FROM &DBV~_hist_database_instance i,&DBV~_hist_snapshot s
				WHERE i.dbid = s.dbid
				  and i.dbid = &DBID
                  and s.startup_time = i.startup_time
				  AND s.snap_id BETWEEN &SNAP_ID_MIN AND &SNAP_ID_MAX
			    order by 1)
    loop
		if '&CAPTURE_HOST_NAMES' = 'YES' then
			l_hosts := l_hosts || c4.host_name ||',';	
		end if;
	end loop; --c4
	l_hosts := rtrim(l_hosts,',');
	dbms_output.put_line(rpad('HOSTS',l_pad_length)||' '||l_hosts);
	

	FOR c5 IN (SELECT REGEXP_REPLACE(sys_context('USERENV', 'MODULE'),'^(.+?)@.+$','\1') module FROM DUAL)
    loop
        dbms_output.put_line(rpad('MODULE',l_pad_length)||' '||c5.module);
    end loop; --c5  
	
	
	
	dbms_output.put_line(rpad('AWR_MINER_VER',l_pad_length)||' &AWR_MINER_VER');
	dbms_output.put_line('~~END-OS-INFORMATION~~');
END;
/

prompt 
prompt 

-- ##############################################################################################

DECLARE
    l_pad_length number :=60;
	l_hosts	varchar2(4000);
	l_dbid	number;

	l_instance_number number := NULL;

BEGIN

    dbms_output.put_line('~~BEGIN-OS-INFORMATION2~~');
    dbms_output.put_line(rpad('STAT_NAME',l_pad_length)||' '||rpad('INSTANCE',l_pad_length)||' ' ||'STAT_VALUE');
    dbms_output.put_line(rpad('-',l_pad_length,'-')||' '||rpad('-',l_pad_length,'-')||' '||rpad('-',l_pad_length,'-'));

    FOR c1 IN (
	             SELECT
                      CASE WHEN stat_name = 'PHYSICAL_MEMORY_BYTES' THEN 'PHYSICAL_MEMORY_GB' ELSE stat_name END stat_name,
                      CASE WHEN stat_name IN ('PHYSICAL_MEMORY_BYTES') THEN round(VALUE/1024/1024/1024,2) ELSE VALUE END stat_value,
                      instance_number
                  FROM &DBV~_hist_osstat o
                 WHERE dbid = &DBID
                   AND snap_id = (SELECT MAX(snap_id) FROM dba_hist_osstat i WHERE i.dbid = o.dbid AND i.instance_number = o.instance_number)
                   AND (stat_name LIKE 'NUM_CPU%'
                   OR stat_name IN ('PHYSICAL_MEMORY_BYTES'))
              )
    loop
        dbms_output.put_line(rpad(c1.stat_name,l_pad_length)||' '||rpad(c1.instance_number,l_pad_length)||' '||c1.stat_value);
    end loop; --c1

	for c1 in (SELECT CPU_COUNT,CPU_CORE_COUNT,CPU_SOCKET_COUNT
				 FROM &DBV~_CPU_USAGE_STATISTICS
				where dbid = &DBID
				  and TIMESTAMP = (select max(TIMESTAMP) from DBA_CPU_USAGE_STATISTICS where dbid = &DBID )
				  AND ROWNUM = 1)
	loop
		dbms_output.put_line(rpad('!CPU_COUNT',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c1.CPU_COUNT);
		dbms_output.put_line(rpad('!CPU_CORE_COUNT',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c1.CPU_CORE_COUNT);
		dbms_output.put_line(rpad('!CPU_SOCKET_COUNT',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c1.CPU_SOCKET_COUNT);
	end loop;

	for c1 in (SELECT inst_id, platform_name FROM sys.GV_$DATABASE
				where dbid = &DBID
				and rownum = 1)
	loop
		dbms_output.put_line(rpad('!PLATFORM_NAME',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c1.platform_name);
	end loop;


    l_instance_number := NULL;

	FOR c2 IN (SELECT DISTINCT
						$IF $$VER_GTE_11_2 $THEN
							REPLACE(platform_name,' ','_') platform_name,
						$ELSE
							'None' platform_name,
						$END
						VERSION, i.db_name, i.DBID, i.instance_number, i.startup_time
	  		     FROM &DBV~_hist_database_instance i,&DBV~_hist_snapshot s
	  			WHERE i.dbid = s.dbid
	  			  and i.dbid = &DBID
                    and s.startup_time = i.startup_time
		  		  AND s.snap_id BETWEEN &SNAP_ID_MIN AND &SNAP_ID_MAX
		  	    order by i.instance_number, i.startup_time DESC
			  )
    loop
        IF c2.instance_number = l_instance_number THEN
 		  NULL;
        ELSE
			l_instance_number := c2.instance_number;

			dbms_output.put_line(rpad('PLATFORM_NAME',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c2.platform_name);
			dbms_output.put_line(rpad('VERSION',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c2.VERSION);
			dbms_output.put_line(rpad('DB_NAME',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c2.db_name);
			dbms_output.put_line(rpad('DBID',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c2.DBID);
			dbms_output.put_line(rpad('INSTANCE_NUMBER',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c2.INSTANCE_NUMBER);
		END IF;
    end loop; --c2

    if '&CAPTURE_HOST_NAMES' = 'YES' then
      l_instance_number := NULL;

	  FOR c4 IN (
	             SELECT DISTINCT i.instance_number, regexp_replace(i.host_name,'^([[:alnum:]]+)\..*$','\1')  host_name, i.startup_time
	  		     FROM &DBV~_hist_database_instance i,&DBV~_hist_snapshot s
	  			WHERE i.dbid = s.dbid
	  			  and i.dbid = &DBID
                    and s.startup_time = i.startup_time
		  		  AND s.snap_id BETWEEN &SNAP_ID_MIN AND &SNAP_ID_MAX
		  	    order by i.instance_number, host_name, i.startup_time DESC
		  	   )
      loop
          IF c4.instance_number = l_instance_number THEN
 			NULL;
          ELSE
			  l_instance_number := c4.instance_number;

			  dbms_output.put_line(rpad('HOSTS',l_pad_length)||' '||rpad(c4.instance_number,l_pad_length)||' '||c4.host_name);
		  END IF;
	  end loop; --c4
	end if;

	FOR c5 IN (SELECT REGEXP_REPLACE(sys_context('USERENV', 'MODULE'),'^(.+?)@.+$','\1') module FROM DUAL)
    loop
        dbms_output.put_line(rpad('MODULE',l_pad_length)||' '||rpad('0',l_pad_length)||' '||c5.module);
    end loop; --c5



	dbms_output.put_line(rpad('AWR_MINER_VER',l_pad_length)||' '||rpad('0',l_pad_length)||' &AWR_MINER_VER');
	dbms_output.put_line('~END-OS-INFORMATION2~~');

END;
/


prompt 
prompt 



-- ##############################################################################################

REPHEADER PAGE LEFT '~~BEGIN-PATCH-HISTORY~~'
REPFOOTER PAGE LEFT '~~END-PATCH-HISTORY~~'
column ACTION_TIME format a24
column comments format a80
select * from (
  select rownum rnum, h.* from &DBV~_REGISTRY_HISTORY h order by action_time desc)
where rownum <= 10;


prompt 
prompt 

REPHEADER PAGE LEFT '~~BEGIN-MODULE~~'
REPFOOTER PAGE LEFT '~~END-MODULE~~'
SELECT REGEXP_REPLACE(sys_context('USERENV', 'MODULE'),'^(.+?)@.+$','\1') module FROM DUAL;

col PDB_NAME format a30
col &DBV~_NAME format a30

compute sum of total_size_gb on report
break on report
REPHEADER OFF
REPFOOTER OFF

define PDB_QUERY = ' ' 
column :PDB_QUERY_1 new_value PDB_QUERY noprint
variable PDB_QUERY_1 varchar2(1000)


begin
	if :DB_VERSION_1  >= 12.1 then
		:PDB_QUERY_1 := q'!   pdb_name, open_mode, total_size_gb
						from(
						SELECT unique name pdb_name ,open_mode,
						       total_size/1024/1024/1024 total_Size_gb 
							   FROM v$pdbs) !';
	else
		:PDB_QUERY_1 := q'!  'table not in this version' from dual !';
	end if;

end;
/

select :PDB_QUERY_1 from dual;

REPHEADER PAGE LEFT '~~BEGIN-PDBs~~'
REPFOOTER PAGE LEFT '~~END-PDBs~~'
COLUMN PDB_NAME FORMAT A30
select &PDB_QUERY ;


REPHEADER PAGE LEFT '~~BEGIN-SNAP-HISTORY~~'
REPFOOTER PAGE LEFT '~~END-SNAP-HISTORY~~'
SELECT min(snap_id) snap_min, max(snap_id) snap_max,count(*) cnt,count(distinct INSTANCE_NUMBER) inst_count,
       sum(ERROR_COUNT) ERROR_COUNT
  FROM &DBV~_hist_snapshot
  WHERE dbid = &DBID;


-- ##############################################################################################

REPHEADER PAGE LEFT '~~BEGIN-MEMORY~~'
REPFOOTER PAGE LEFT '~~END-MEMORY~~'

SELECT snap_id,
    instance_number,
    MAX (DECODE (stat_name, 'SGA', stat_value, NULL)) "SGA",
    MAX (DECODE (stat_name, 'PGA', stat_value, NULL)) "PGA",
    MAX (DECODE (stat_name, 'SGA', stat_value, NULL)) + MAX (DECODE (stat_name, 'PGA', stat_value,
    NULL)) "TOTAL"
   FROM
    (SELECT snap_id,
        instance_number,
        ROUND (SUM (bytes) / 1024 / 1024 / 1024, 1) stat_value,
        MAX ('SGA') stat_name
       FROM &DBV~_hist_sgastat
      WHERE dbid = &DBID
        AND snap_id BETWEEN &SNAP_ID_MIN AND &SNAP_ID_MAX
   GROUP BY snap_id,
        instance_number
  UNION ALL
     SELECT snap_id,
        instance_number,
        ROUND (value / 1024 / 1024 / 1024, 1) stat_value,
        'PGA' stat_name
       FROM &DBV~_hist_pgastat
      WHERE dbid = &DBID
        AND snap_id BETWEEN &SNAP_ID_MIN AND &SNAP_ID_MAX
        AND NAME = 'total PGA allocated'
    )
GROUP BY snap_id,
    instance_number
ORDER BY snap_id,
    instance_number;

prompt 
prompt 

-- ##############################################################################################


REPHEADER PAGE LEFT '~~BEGIN-MEMORY-SGA-ADVICE~~'
REPFOOTER PAGE LEFT '~~END-MEMORY-SGA-ADVICE~~'

select snap_id,instance_number,sga_target_gb,size_factor,ESTD_PHYSICAL_READS,lead_read_diff
from(
with top_n_dbtime as(
select snap_id from(
select snap_id, sum(average) dbtime_p_s,
  dense_rank() over (order by sum(average) desc nulls last) rnk
 from &DBV~_hist_sysmetric_summary
where dbid = &DBID
 and snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
 and metric_name = 'Database Time Per Sec'
 group by snap_id)
 where rnk <= 10)
SELECT a.SNAP_ID,
  INSTANCE_NUMBER,
  ROUND(sga_size/1024,1) sga_target_gb,
  sga_size_FACTOR size_factor,
  ESTD_PHYSICAL_READS,
  round((ESTD_PHYSICAL_READS - lead(ESTD_PHYSICAL_READS,1,ESTD_PHYSICAL_READS) over (partition by a.snap_id,instance_number order by sga_size_FACTOR asc nulls last)),1) lead_read_diff,
  min(sga_size_FACTOR) over (partition by a.snap_id,instance_number) min_factor,
  max(sga_size_FACTOR) over (partition by a.snap_id,instance_number) max_factor
FROM &DBV~_HIST_SGA_TARGET_ADVICE a,top_n_dbtime tn
WHERE dbid          = &DBID
AND a.snap_id         = tn.snap_id)
where (size_factor = 1
or size_factor = min_factor
or size_factor = max_factor
or lead_read_diff > 1)
order by snap_id asc,instance_number, size_factor asc nulls last;


prompt 
prompt 

-- ##############################################################################################


REPHEADER PAGE LEFT '~~BEGIN-MEMORY-PGA-ADVICE~~'
REPFOOTER PAGE LEFT '~~END-MEMORY-PGA-ADVICE~~'


SELECT  SNAP_ID,
  INSTANCE_NUMBER,
  PGA_TARGET_GB,
  SIZE_FACTOR,
  ESTD_EXTRA_MB_RW,
  LEAD_SIZE_DIFF_MB,
  ESTD_PGA_CACHE_HIT_PERCENTAGE
FROM
  ( WITH top_n_dbtime AS
  (SELECT snap_id
  FROM
    (SELECT  snap_id,
      SUM(average) dbtime_p_s,
      dense_rank() over (order by SUM(average) DESC nulls last) rnk
    FROM &DBV~_hist_sysmetric_summary
      where dbid = &DBID
      and snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
    AND metric_name = 'Database Time Per Sec'
    GROUP BY snap_id
    )
  WHERE rnk <= 10
  )
SELECT a.SNAP_ID,
  INSTANCE_NUMBER,
  ROUND(PGA_TARGET_FOR_ESTIMATE/1024/1024/1024,1) pga_target_gb,
  PGA_TARGET_FACTOR size_factor,
  ROUND(ESTD_EXTRA_BYTES_RW  /1024/1024,1) ESTD_EXTRA_MB_RW,
  ROUND((ESTD_EXTRA_BYTES_RW - lead(ESTD_EXTRA_BYTES_RW,1,ESTD_EXTRA_BYTES_RW) over (partition BY a.snap_id,instance_number order by PGA_TARGET_FACTOR ASC nulls last))/1024/1024,1) lead_size_diff_mb,
  ESTD_PGA_CACHE_HIT_PERCENTAGE,
  MIN(PGA_TARGET_FACTOR) over (partition BY a.snap_id,instance_number) min_factor,
  MAX(PGA_TARGET_FACTOR) over (partition BY a.snap_id,instance_number) max_factor
FROM &DBV~_HIST_PGA_TARGET_ADVICE a,
  top_n_dbtime tn
WHERE dbid = &DBID
AND a.snap_id = tn.snap_id
  )
WHERE (size_factor   = 1
OR size_factor       = min_factor
OR size_factor       = max_factor
OR lead_size_diff_mb > 1)
ORDER BY snap_id ASC,
  instance_number,
  size_factor ASC nulls last;


prompt 
prompt 

-- ##############################################################################################


 
REPHEADER PAGE LEFT '~~BEGIN-SIZE-ON-DISK~~'
REPFOOTER PAGE LEFT '~~END-SIZE-ON-DISK~~'
 WITH ts_info as (
select dbid, ts#, tsname, max(block_size) block_size
from &DBV~_hist_datafile
where dbid = &DBID
group by dbid, ts#, tsname),
-- Get the maximum snaphsot id for each day from &DBV~_hist_snapshot
snap_info as (
select dbid,to_char(trunc(end_interval_time,'DD'),'MM/DD/YY') dd, max(s.snap_id) snap_id
FROM &DBV~_hist_snapshot s
where s.snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
and dbid = &DBID
--where s.end_interval_time > to_date(:start_time,'MMDDYYYY')
--and s.end_interval_time < to_date(:end_time,'MMDDYYYY')
group by dbid,trunc(end_interval_time,'DD'))
-- Sum up the sizes of all the tablespaces for the last snapshot of each day
select s.snap_id, round(sum(tablespace_size*f.block_size)/1024/1024/1024,2) size_gb
from &DBV~_hist_tbspc_space_usage sp,
ts_info f,
snap_info s
WHERE s.dbid = sp.dbid
AND s.dbid = &DBID
 and s.snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
and s.snap_id = sp.snap_id
and sp.dbid = f.dbid
AND sp.tablespace_id = f.ts#
GROUP BY  s.snap_id,s.dd, s.dbid
order by  s.snap_id;

prompt 
prompt 

-- ##############################################################################################

REPHEADER OFF
REPFOOTER OFF
 
define DISK_SIZE_QUERY = ' ' 
column :DISK_SIZE_QUERY_1 new_value DISK_SIZE_QUERY noprint
variable DISK_SIZE_QUERY_1 varchar2(4000)




begin
if :DB_VERSION_1  >= 12.2 then
		:DISK_SIZE_QUERY_1 := q'! *
from 
(WITH snap_info as (
select dbid,to_char(trunc(end_interval_time,'DD'),'MM/DD/YY') dd, max(s.snap_id) snap_id
FROM &DBV~_hist_snapshot s
where s.snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
and dbid = &DBID
group by dbid,trunc(end_interval_time,'DD'))
select s.snap_id, round(sum(tablespace_size*(select &DB_BLOCK_SIZE from dual))/1024/1024/1024,2)  size_gb
from &DBV~_hist_tbspc_space_usage sp,
snap_info s
WHERE s.dbid = sp.dbid
AND s.dbid = &DBID
AND s.snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
AND s.snap_id = sp.snap_id
and not exists(select dbid, ts#, tsname, max(block_size) block_size
from &DBV~_hist_datafile
where dbid = &DBID
group by dbid, ts#, tsname)
GROUP BY  s.snap_id,s.dd, s.dbid
order by  s.snap_id) !';
	else
		:DISK_SIZE_QUERY_1 := q'!  'table not in this version' from dual !';
	end if;

end;
/

select :DISK_SIZE_QUERY_1 from dual;

REPHEADER PAGE LEFT '~~BEGIN-SIZE-ON-DISK2~~'
REPFOOTER PAGE LEFT '~~END-SIZE-ON-DISK2~~'
select &DISK_SIZE_QUERY ;



prompt 
prompt   
-- ##############################################################################################

REPHEADER PAGE LEFT '~~BEGIN-OSSTAT~~'
REPFOOTER PAGE LEFT '~~END-OSSTAT~~'


SELECT snap_id,
  INSTANCE_NUMBER,
  MAX(DECODE(STAT_NAME,'LOAD', round(value,1),NULL)) "load",
  MAX(DECODE(STAT_NAME,'NUM_CPUS', value,NULL)) "cpus",
  MAX(DECODE(STAT_NAME,'NUM_CPU_CORES', value,NULL)) "cores",
  MAX(DECODE(STAT_NAME,'NUM_CPU_SOCKETS', value,NULL)) "sockets",
  MAX(DECODE(STAT_NAME,'PHYSICAL_MEMORY_BYTES', ROUND(value/1024/1024),NULL)) "mem_gb",
  MAX(DECODE(STAT_NAME,'FREE_MEMORY_BYTES', ROUND(value    /1024/1024),NULL)) "mem_free_gb",
  MAX(DECODE(STAT_NAME,'IDLE_TIME', value,NULL)) "idle",
  MAX(DECODE(STAT_NAME,'BUSY_TIME', value,NULL)) "busy",
  MAX(DECODE(STAT_NAME,'USER_TIME', value,NULL)) "user",
  MAX(DECODE(STAT_NAME,'SYS_TIME', value,NULL)) "sys",
  MAX(DECODE(STAT_NAME,'IOWAIT_TIME', value,NULL)) "iowait",
  MAX(DECODE(STAT_NAME,'NICE_TIME', value,NULL)) "nice",
  MAX(DECODE(STAT_NAME,'OS_CPU_WAIT_TIME', value,NULL)) "cpu_wait",
  MAX(DECODE(STAT_NAME,'RSRC_MGR_CPU_WAIT_TIME', value,NULL)) "rsrc_mgr_wait",
  MAX(DECODE(STAT_NAME,'VM_IN_BYTES', value,NULL)) "vm_in",
  MAX(DECODE(STAT_NAME,'VM_OUT_BYTES', value,NULL)) "vm_out",
  MAX(DECODE(STAT_NAME,'cpu_count', value,NULL)) "cpu_count"
FROM
  (SELECT snap_id,
    INSTANCE_NUMBER,
    STAT_NAME,
    value
  FROM &DBV~_HIST_OSSTAT
    where dbid = &DBID
      and snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
  union all
  SELECT SNAP_ID,
  INSTANCE_NUMBER,
  PARAMETER_NAME STAT_NAME,
  to_number(VALUE) value
 FROM &DBV~_HIST_PARAMETER 
where dbid = &DBID
  and snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
  and PARAMETER_NAME = 'cpu_count'
  )
GROUP BY snap_id,
  INSTANCE_NUMBER
ORDER BY snap_id,
  INSTANCE_NUMBER;


prompt 
prompt   
-- ##############################################################################################




REPHEADER PAGE LEFT '~~BEGIN-MAIN-METRICS~~'
REPFOOTER PAGE LEFT '~~END-MAIN-METRICS~~'


 select snap_id "snap",num_interval "dur_m", end_time "end",inst "inst",
  max(decode(metric_name,'Host CPU Utilization (%)',					average,null)) "os_cpu",
  max(decode(metric_name,'Host CPU Utilization (%)',					maxval,null)) "os_cpu_max",
  max(decode(metric_name,'Host CPU Utilization (%)',					STANDARD_DEVIATION,null)) "os_cpu_sd",
  max(decode(metric_name,'Database Wait Time Ratio',                   round(average,1),null)) "db_wait_ratio",
max(decode(metric_name,'Database CPU Time Ratio',                   round(average,1),null)) "db_cpu_ratio",
max(decode(metric_name,'CPU Usage Per Sec',                   round(average/100,3),null)) "cpu_p_sec",
max(decode(metric_name,'CPU Usage Per Sec',                   round(STANDARD_DEVIATION/100,3),null)) "cpu_per_s_sd",
max(decode(metric_name,'Host CPU Usage Per Sec',                   round(average/100,3),null)) "h_cpu_per_s",
max(decode(metric_name,'Host CPU Usage Per Sec',                   round(STANDARD_DEVIATION/100,3),null)) "h_cpu_per_s_sd",
max(decode(metric_name,'Average Active Sessions',                   average,null)) "aas",
max(decode(metric_name,'Average Active Sessions',                   STANDARD_DEVIATION,null)) "aas_sd",
max(decode(metric_name,'Average Active Sessions',                   maxval,null)) "aas_max",
max(decode(metric_name,'Database Time Per Sec',					average,null)) "db_time",
max(decode(metric_name,'Database Time Per Sec',					STANDARD_DEVIATION,null)) "db_time_sd",
max(decode(metric_name,'SQL Service Response Time',                   average,null)) "sql_res_t_cs",
max(decode(metric_name,'Background Time Per Sec',                   average,null)) "bkgd_t_per_s",
max(decode(metric_name,'Logons Per Sec',                            average,null)) "logons_s",
max(decode(metric_name,'Current Logons Count',                      average,null)) "logons_total",
max(decode(metric_name,'Executions Per Sec',                        average,null)) "exec_s",
max(decode(metric_name,'Hard Parse Count Per Sec',                  average,null)) "hard_p_s",
max(decode(metric_name,'Logical Reads Per Sec',                     average,null)) "l_reads_s",
max(decode(metric_name,'User Commits Per Sec',                      average,null)) "commits_s",
max(decode(metric_name,'Physical Read Total Bytes Per Sec',         round((average)/1024/1024,1),null)) "read_mb_s",
max(decode(metric_name,'Physical Read Total Bytes Per Sec',         round((maxval)/1024/1024,1),null)) "read_mb_s_max",
max(decode(metric_name,'Physical Read Total IO Requests Per Sec',   average,null)) "read_iops",
max(decode(metric_name,'Physical Read Total IO Requests Per Sec',   maxval,null)) "read_iops_max",
max(decode(metric_name,'Physical Reads Per Sec',  			average,null)) "read_bks",
max(decode(metric_name,'Physical Reads Direct Per Sec',  			average,null)) "read_bks_direct",
max(decode(metric_name,'Physical Write Total Bytes Per Sec',        round((average)/1024/1024,1),null)) "write_mb_s",
max(decode(metric_name,'Physical Write Total Bytes Per Sec',        round((maxval)/1024/1024,1),null)) "write_mb_s_max",
max(decode(metric_name,'Physical Write Total IO Requests Per Sec',  average,null)) "write_iops",
max(decode(metric_name,'Physical Write Total IO Requests Per Sec',  maxval,null)) "write_iops_max",
max(decode(metric_name,'Physical Writes Per Sec',  			average,null)) "write_bks",
max(decode(metric_name,'Physical Writes Direct Per Sec',  			average,null)) "write_bks_direct",
max(decode(metric_name,'Redo Generated Per Sec',                    round((average)/1024/1024,1),null)) "redo_mb_s",
max(decode(metric_name,'DB Block Gets Per Sec',                     average,null)) "db_block_gets_s",
max(decode(metric_name,'DB Block Changes Per Sec',                   average,null)) "db_block_changes_s",
max(decode(metric_name,'GC CR Block Received Per Second',            average,null)) "gc_cr_rec_s",
max(decode(metric_name,'GC Current Block Received Per Second',       average,null)) "gc_cu_rec_s",
max(decode(metric_name,'Global Cache Average CR Get Time',           average,null)) "gc_cr_get_cs",
max(decode(metric_name,'Global Cache Average Current Get Time',      average,null)) "gc_cu_get_cs",
max(decode(metric_name,'Global Cache Blocks Corrupted',              average,null)) "gc_bk_corrupted",
max(decode(metric_name,'Global Cache Blocks Lost',                   average,null)) "gc_bk_lost",
max(decode(metric_name,'Active Parallel Sessions',                   average,null)) "px_sess",
max(decode(metric_name,'Active Serial Sessions',                     average,null)) "se_sess",
max(decode(metric_name,'Average Synchronous Single-Block Read Latency', average,null)) "s_blk_r_lat",
max(decode(metric_name,'Cell Physical IO Interconnect Bytes',         round((average)/1024/1024,1),null)) "cell_io_int_mb",
max(decode(metric_name,'Cell Physical IO Interconnect Bytes',         round((maxval)/1024/1024,1),null)) "cell_io_int_mb_max"
  from(
  select  snap_id,num_interval,to_char(end_time,'YY/MM/DD HH24:MI') end_time,instance_number inst,metric_name,round(average,1) average,
  round(maxval,1) maxval,round(standard_deviation,1) standard_deviation
 from &DBV~_hist_sysmetric_summary
where dbid = &DBID
 and snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
 --and snap_id = 920
 --and instance_number = 4
 and metric_name in ('Host CPU Utilization (%)','CPU Usage Per Sec','Host CPU Usage Per Sec','Average Active Sessions','Database Time Per Sec',
 'Executions Per Sec','Hard Parse Count Per Sec','Logical Reads Per Sec','Logons Per Sec',
 'Physical Read Total Bytes Per Sec','Physical Read Total IO Requests Per Sec','Physical Reads Per Sec','Physical Write Total Bytes Per Sec',
 'Redo Generated Per Sec','User Commits Per Sec','Current Logons Count','DB Block Gets Per Sec','DB Block Changes Per Sec',
 'Database Wait Time Ratio','Database CPU Time Ratio','SQL Service Response Time','Background Time Per Sec',
 'Physical Write Total IO Requests Per Sec','Physical Writes Per Sec','Physical Writes Direct Per Sec','Physical Writes Direct Lobs Per Sec',
 'Physical Reads Direct Per Sec','Physical Reads Direct Lobs Per Sec',
 'GC CR Block Received Per Second','GC Current Block Received Per Second','Global Cache Average CR Get Time','Global Cache Average Current Get Time',
 'Global Cache Blocks Corrupted','Global Cache Blocks Lost',
 'Active Parallel Sessions','Active Serial Sessions','Average Synchronous Single-Block Read Latency','Cell Physical IO Interconnect Bytes'
    )
 )
 group by snap_id,num_interval, end_time,inst
 order by snap_id, end_time,inst;

prompt 
prompt 
-- ##############################################################################################


REPHEADER OFF
REPFOOTER OFF
 
define PDB_RSRC_QUERY = ' ' 
column :PDB_RSRC_QUERY_1 new_value PDB_RSRC_QUERY noprint
variable PDB_RSRC_QUERY_1 varchar2(4000)



begin
if :DB_VERSION_1  >= 12.2 then
		:PDB_RSRC_QUERY_1 := q'! *
from 
(select snap_id "snap", ABS(to_number(to_char(end_time,'MI')) - to_number(to_char(begin_time,'MI'))) "dur_m", to_char(end_time,'YY/MM/DD HH24:MI') "end", instance_number "inst",
	  AVG_CPU_UTILIZATION "os_cpu",
	  AVG_CPU_UTILIZATION "os_cpu_max",
	  0 "os_cpu_sd",
	  0 "db_wait_ratio",
	  0 "db_cpu_ratio",
	  0 "cpu_p_sec",
	  0 "cpu_per_s_sd",
	  0 "h_cpu_per_s",
	  0 "h_cpu_per_s_sd",
	  AVG_RUNNING_SESSIONS "aas",
	  0 "aas_sd",
	  AVG_RUNNING_SESSIONS "aas_max",
	  0  "db_time",
	  0 "db_time_sd",
	  0 "sql_res_t_cs",
	  0  "bkgd_t_per_s",
	  0  "logons_s",
	  0  "logons_total",
	  0  "exec_s",
	  0  "hard_p_s",
	  0  "l_reads_s",
	  0  "commits_s",
	  IOMBPS "read_mb_s",
  	  IOMBPS "read_mb_s_max",
	  IOPS   "read_iops",
	  IOPS   "read_iops_max",
	  0     "read_bks",
	  0     "read_bks_direct",
	  0     "write_mb_s",
	  0     "write_mb_s_max",
	  0     "write_iops",
	  0     "write_iops_max",
	  0     "write_bks",
	  0     "write_bks_direct",
	  0  "redo_mb_s",
	  0 "db_block_gets_s",
	  0  "db_block_changes_s",
	  0  "gc_cr_rec_s",
	  0  "gc_cu_rec_s",
	  0  "gc_cr_get_cs",
	  0  "gc_cu_get_cs",
	  0  "gc_bk_corrupted",
	  0  "gc_bk_lost",
	  AVG_ACTIVE_PARALLEL_STMTS "px_sess",
	  0  "se_sess",
	  0  "s_blk_r_lat",
	  0  "cell_io_int_mb",
	  0  "cell_io_int_mb_max"
	  from &DBV~_hist_rsrc_pdb_metric
	   where dbid = &DBID
	     and snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
		 and con_id > 2
	  order by snap_id, end_time, instance_number)!';
	else
		:PDB_RSRC_QUERY_1 := q'!  'table not in this version' from dual !';
	end if;

end;
/

select :PDB_RSRC_QUERY_1 from dual;

REPHEADER PAGE LEFT '~~BEGIN-PDB-METRICS~~'
REPFOOTER PAGE LEFT '~~END-PDB-METRICS~~'
COLUMN CPU_PER_S FORMAT A9
select &PDB_RSRC_QUERY ;

 
prompt
prompt
-- ##############################################################################################


REPHEADER PAGE LEFT '~~BEGIN-SQLNET-METRICS~~'
REPFOOTER PAGE LEFT '~~END-SQLNET-METRICS~~'

select snap_id "snap",inst "inst",
  max(decode(stat_name,'Requests to/from client',				 value,null)) "rqsts_to_from_client",
  max(decode(stat_name,'SQL*Net roundtrips to/from client',		 value,null)) "sqlnet_to_from_client",
  max(decode(stat_name,'bytes received via SQL*Net from client', value,null)) "sqlnet_bytes_received",    -- "sqlnet_bytes_received_from_client"
  max(decode(stat_name,'bytes sent via SQL*Net to client',       value,null)) "sqlnet_bytes_sent",        -- "sqlnet_bytes_sent_to_client"
  max(decode(stat_name,'bytes via SQL*Net vector from client',   value,null)) "sqlnet_bytes_vector_fr",   -- "sqlnet_bytes_vector_from_client"
  max(decode(stat_name,'bytes via SQL*Net vector to client',     value,null)) "sqlnet_bytes_vector_to"    -- "sqlnet_bytes_vector_to_client"
  from(
  select  snap_id,instance_number inst
         ,stat_name, value
 from &DBV~_hist_sysstat
where dbid = &DBID
 and snap_id between &SNAP_ID_MIN and &SNAP_ID_MAX
 and stat_name in ('Requests to/from client', 'SQL*Net roundtrips to/from client', 'bytes received via SQL*Net from client', 'bytes sent via SQL*Net to client'
                  ,'bytes via SQL*Net vector from client', 'bytes via SQL*Net vector to client'
    )
 )
 group by snap_id, inst
 order by snap_id, inst;
 
 
prompt 
prompt 
-- ##############################################################################################

column display_value format a50
set wrap off
REPHEADER PAGE LEFT '~~BEGIN-DATABASE-PARAMETERS~~'
REPFOOTER PAGE LEFT '~~END-DATABASE-PARAMETERS~~'
with inst as (
select min(instance_number) inst_num
  from &DBV~_hist_snapshot
  where dbid = &DBID
	and snap_id BETWEEN to_number(&SNAP_ID_MIN) and to_number(&SNAP_ID_MAX))
SELECT PARAMETER_NAME,VALUE
FROM &DBV~_HIST_PARAMETER
WHERE dbid = &DBID
AND snap_id = (SELECT MAX(snap_id) FROM &DBV~_hist_osstat WHERE dbid = &DBID AND instance_number = (select inst_num from inst))
   AND instance_number = (select inst_num from inst)
  and PARAMETER_NAME not in ('local_listener','service_names','remote_listener','db_domain','cluster_interconnects')
ORDER BY 1;

prompt 
prompt 
-- ##############################################################################################
REPHEADER OFF
REPFOOTER OFF


REPHEADER PAGE LEFT '~~BEGIN-DATABASE-PARAMETERS2~~'
REPFOOTER PAGE LEFT '~~END-DATABASE-PARAMETERS2~~'
SELECT O.INSTANCE_NUMBER, O.PARAMETER_NAME, O.VALUE
FROM &DBV~_HIST_PARAMETER O
WHERE dbid = &DBID
AND snap_id = (SELECT MAX(snap_id) FROM &DBV~_hist_osstat WHERE dbid = &DBID AND instance_number = O.INSTANCE_NUMBER)
  and PARAMETER_NAME not in ('local_listener','service_names','remote_listener','db_domain','cluster_interconnects')
ORDER BY 1, 2;
	
prompt 
prompt 
-- ##############################################################################################


REPHEADER PAGE LEFT '~~BEGIN-AVERAGE-ACTIVE-SESSIONS~~'
REPFOOTER PAGE LEFT '~~END-AVERAGE-ACTIVE-SESSIONS~~'
column wait_class format a20

 SELECT snap_id,
    wait_class,
    ROUND (SUM (pSec), 2) avg_sess
   FROM
    (SELECT snap_id,
        wait_class,
        p_tmfg / 1000000 / ela pSec
       FROM
        (SELECT (CAST (s.end_interval_time AS DATE) - CAST (s.begin_interval_time AS DATE)) * 24 *
            3600 ela,
            s.snap_id,
            wait_class,
            e.event_name,
            CASE WHEN s.begin_interval_time = s.startup_time
			-- compare to e.time_waited_micro_fg for 10.2?
                THEN e.&T_WAITED_MICRO_COL
                ELSE e.&T_WAITED_MICRO_COL - lag (e.&T_WAITED_MICRO_COL) over (partition BY
                    event_id, e.dbid, e.instance_number, s.startup_time order by e.snap_id)
            END p_tmfg
           FROM &DBV~_hist_snapshot s,
            &DBV~_hist_system_event e
          WHERE s.dbid = e.dbid
            AND s.dbid = to_number(&DBID)
            AND e.dbid = to_number(&DBID)
            AND s.instance_number = e.instance_number
            AND s.snap_id = e.snap_id
            AND s.snap_id BETWEEN to_number(&SNAP_ID_MIN) and to_number(&SNAP_ID_MAX)
            AND e.snap_id BETWEEN to_number(&SNAP_ID_MIN) and to_number(&SNAP_ID_MAX)
            AND e.wait_class != 'Idle'
      UNION ALL
         SELECT (CAST (s.end_interval_time AS DATE) - CAST (s.begin_interval_time AS DATE)) * 24 *
            3600 ela,
            s.snap_id,
            t.stat_name wait_class,
            t.stat_name event_name,
            CASE WHEN s.begin_interval_time = s.startup_time
                THEN t.value
                ELSE t.value - lag (value) over (partition BY stat_id, t.dbid, t.instance_number,
                    s.startup_time order by t.snap_id)
            END p_tmfg
           FROM &DBV~_hist_snapshot s,
            &DBV~_hist_sys_time_model t
          WHERE s.dbid = t.dbid
            AND s.dbid = to_number(&DBID)
            AND s.instance_number = t.instance_number
            AND s.snap_id = t.snap_id
            AND s.snap_id BETWEEN to_number(&SNAP_ID_MIN) and to_number(&SNAP_ID_MAX)
			AND t.snap_id BETWEEN to_number(&SNAP_ID_MIN) and to_number(&SNAP_ID_MAX)
            AND t.stat_name = 'DB CPU'
        )
		where p_tmfg is not null
    )
GROUP BY snap_id,
    wait_class
ORDER BY snap_id,
    wait_class; 

	
	
prompt 
prompt 
-- ##############################################################################################


REPHEADER OFF
REPFOOTER OFF

define HISTOGRAM_QUERY = ' ' 
column :HISTOGRAM_QUERY_1 new_value HISTOGRAM_QUERY noprint
variable HISTOGRAM_QUERY_1 varchar2(4000)


begin
	if :DB_VERSION_1  >= 11.1 then
		:HISTOGRAM_QUERY_1 := q'!   snap_id,wait_class,event_name,wait_time_milli,sum(wait_count) wait_count
						from(
						SELECT       s.snap_id,
									wait_class,
									h.event_name,
									wait_time_milli,
									CASE WHEN s.begin_interval_time = s.startup_time
										THEN h.wait_count
										ELSE h.wait_count - lag (h.wait_count) over (partition BY
											event_id,wait_time_milli, h.dbid, h.instance_number, s.startup_time order by h.snap_id)
									END wait_count
								   FROM &DBV~_hist_snapshot s,
									&DBV~_HIST_event_histogram h
								  WHERE s.dbid = h.dbid
									AND s.dbid = &DBID
									AND s.instance_number = h.instance_number
									AND s.snap_id = h.snap_id
									AND s.snap_id BETWEEN &SNAP_ID_MIN and &SNAP_ID_MAX
									and event_name in ('cell single block physical read','cell list of blocks physical read','cell multiblock physical read',
													   'db file sequential read','db file scattered read',
													   'log file parallel write','log file sync','free buffer wait')
										  )
							  where wait_count > 0
						group by snap_id,wait_class,event_name,wait_time_milli
							  order by snap_id,event_name,wait_time_milli !';
	else
		:HISTOGRAM_QUERY_1 := q'!  'table not in this version' from dual !';
	end if;

end;
/

select :HISTOGRAM_QUERY_1 from dual;

REPHEADER PAGE LEFT '~~BEGIN-IO-WAIT-HISTOGRAM~~'
REPFOOTER PAGE LEFT '~~END-IO-WAIT-HISTOGRAM~~'
COLUMN EVENT_NAME FORMAT A37
select &HISTOGRAM_QUERY ;
	  
	  
	  
prompt 
prompt 
-- ##############################################################################################


REPHEADER PAGE LEFT '~~BEGIN-IO-OBJECT-TYPE~~'
REPFOOTER PAGE LEFT '~~END-IO-OBJECT-TYPE~~'
COLUMN OBJECT_TYPE FORMAT A15


SELECT s.snap_id,regexp_replace(o.OBJECT_TYPE,'^(TABLE|INDEX).*','\1') OBJECT_TYPE,
       ROUND((sum(s.LOGICAL_READS_DELTA)* &DB_BLOCK_SIZE)/1024/1024/1024,1) logical_read_gb,
	   ROUND((sum(s.PHYSICAL_READS_DELTA)* &DB_BLOCK_SIZE)/1024/1024/1024,1) physical_read_gb,
	   ROUND((sum(s.PHYSICAL_WRITES_DELTA)* &DB_BLOCK_SIZE)/1024/1024/1024,1) physical_write_gb,
	   ROUND((sum(s.SPACE_ALLOCATED_DELTA)/1024/1024/1024),1) GB_ADDED
FROM
  &DBV~_HIST_SEG_STAT_OBJ o,
  &DBV~_HIST_SEG_STAT s
where o.dbid = s.dbid
  and o.ts# = s.ts#
  and o.obj# = s.obj#
  and o.dataobj# = s.dataobj#
  and o.dbid = &DBID
				  AND s.snap_id BETWEEN &SNAP_ID_MIN and &SNAP_ID_MAX
          AND OBJECT_TYPE != 'UNDEFINED'
  group by s.snap_id,regexp_replace(o.OBJECT_TYPE,'^(TABLE|INDEX).*','\1')
  order by snap_id,object_type;
  
  
  
prompt 
prompt 
-- ##############################################################################################



REPHEADER OFF
REPFOOTER OFF

define IOSTAT_FN_QUERY = ' ' 
column :IOSTAT_FN_QUERY_1 new_value IOSTAT_FN_QUERY noprint
variable IOSTAT_FN_QUERY_1 varchar2(4000)


begin
	if :DB_VERSION_1  >= 11.1 then
		:IOSTAT_FN_QUERY_1 := q'!  snap_id,
              function_name,
              SUM(sm_r_reqs) sm_r_reqs,
              SUM(sm_w_reqs) sm_w_reqs,
              SUM(lg_r_reqs) lg_r_reqs,
              SUM(lg_w_reqs) lg_w_reqs
            FROM
              (SELECT s.snap_id ,
                s.instance_number ,
                s.dbid ,
                FUNCTION_NAME,
                CASE
                  WHEN s.begin_interval_time = s.startup_time
                  THEN NVL(fn.SMALL_READ_REQS,0)
                  ELSE NVL(fn.SMALL_READ_REQS,0) - lag(NVL(fn.SMALL_READ_REQS,0),1) over (partition BY fn.FUNCTION_NAME , fn.instance_number , fn.dbid , s.startup_time order by fn.snap_id)
                END sm_r_reqs,
                CASE
                  WHEN s.begin_interval_time = s.startup_time
                  THEN NVL(fn.SMALL_WRITE_REQS,0)
                  ELSE NVL(fn.SMALL_WRITE_REQS,0) - lag(NVL(fn.SMALL_WRITE_REQS,0),1) over (partition BY fn.FUNCTION_NAME , fn.instance_number , fn.dbid , s.startup_time order by fn.snap_id)
                END sm_w_reqs,
                CASE
                  WHEN s.begin_interval_time = s.startup_time
                  THEN NVL(fn.LARGE_READ_REQS,0)
                  ELSE NVL(fn.LARGE_READ_REQS,0) - lag(NVL(fn.LARGE_READ_REQS,0),1) over (partition BY fn.FUNCTION_NAME , fn.instance_number , fn.dbid , s.startup_time order by fn.snap_id)
                END lg_r_reqs,
                CASE
                  WHEN s.begin_interval_time = s.startup_time
                  THEN NVL(fn.LARGE_WRITE_REQS,0)
                  ELSE NVL(fn.LARGE_WRITE_REQS,0) - lag(NVL(fn.LARGE_WRITE_REQS,0),1) over (partition BY fn.FUNCTION_NAME , fn.instance_number , fn.dbid , s.startup_time order by fn.snap_id)
                END lg_w_reqs
              FROM &DBV~_hist_snapshot s ,
                &DBV~_HIST_IOSTAT_FUNCTION fn
              WHERE s.dbid = fn.dbid
              AND s.dbid   = &DBID
              AND s.snap_id BETWEEN &SNAP_ID_MIN and &SNAP_ID_MAX
              AND s.instance_number = fn.instance_number
              AND s.snap_id     = fn.snap_id
              )
            GROUP BY snap_id,
              function_name
              having SUM(sm_r_reqs) is not null 
            order by snap_id !';
    else
		:IOSTAT_FN_QUERY_1 := q'!  'table not in this version' from dual !';
	end if;

end;
/



select :IOSTAT_FN_QUERY_1 from dual;

REPHEADER PAGE LEFT '~~BEGIN-IOSTAT-BY-FUNCTION~~'
REPFOOTER PAGE LEFT '~~END-IOSTAT-BY-FUNCTION~~'
COLUMN FUNCTION_NAME FORMAT A22
select &IOSTAT_FN_QUERY ;
	  
	  
	  
prompt 
prompt 
-- ##############################################################################################


column EVENT_NAME format a60
REPHEADER PAGE LEFT '~~BEGIN-TOP-N-TIMED-EVENTS~~'
REPFOOTER PAGE LEFT '~~END-TOP-N-TIMED-EVENTS~~'


SELECT snap_id,
  wait_class,
  event_name,
  pctdbt,
  total_time_s
FROM
  (SELECT a.snap_id,
    wait_class,
    event_name,
    b.dbt,
    ROUND(SUM(a.ttm) /b.dbt*100,2) pctdbt,
    SUM(a.ttm) total_time_s,
    dense_rank() over (partition BY a.snap_id order by SUM(a.ttm)/b.dbt*100 DESC nulls last) rnk
  FROM
    (SELECT snap_id,
      wait_class,
      event_name,
      ttm
    FROM
      (SELECT
        /*+ qb_name(systemevents) */
        (CAST (s.end_interval_time AS DATE) - CAST (s.begin_interval_time AS DATE)) * 24 * 3600 ela,
        s.snap_id,
        wait_class,
        e.event_name,
        CASE
          WHEN s.begin_interval_time = s.startup_time
          THEN e.time_waited_micro
          ELSE e.time_waited_micro - lag (e.time_waited_micro ) over (partition BY e.instance_number,e.event_name order by e.snap_id)
        END ttm
      FROM &DBV~_hist_snapshot s,
        &DBV~_hist_system_event e
      WHERE s.dbid          = e.dbid
      AND s.dbid            = &DBID
      AND s.instance_number = e.instance_number
      AND s.snap_id         = e.snap_id
      AND s.snap_id BETWEEN &SNAP_ID_MIN and &SNAP_ID_MAX
      AND e.wait_class != 'Idle'
      UNION ALL
      SELECT
        /*+ qb_name(dbcpu) */
        (CAST (s.end_interval_time AS DATE) - CAST (s.begin_interval_time AS DATE)) * 24 * 3600 ela,
        s.snap_id,
        t.stat_name wait_class,
        t.stat_name event_name,
        CASE
          WHEN s.begin_interval_time = s.startup_time
          THEN t.value
          ELSE t.value - lag (t.value ) over (partition BY s.instance_number order by s.snap_id)
        END ttm
      FROM &DBV~_hist_snapshot s,
        &DBV~_hist_sys_time_model t
      WHERE s.dbid          = t.dbid
      AND s.dbid            = &DBID
      AND s.instance_number = t.instance_number
      AND s.snap_id         = t.snap_id
      AND s.snap_id BETWEEN &SNAP_ID_MIN and &SNAP_ID_MAX
      AND t.stat_name = 'DB CPU'
      )
    ) a,
    (SELECT snap_id,
      SUM(dbt) dbt
    FROM
      (SELECT
        /*+ qb_name(dbtime) */
        s.snap_id,
        t.instance_number,
        t.stat_name nm,
        CASE
          WHEN s.begin_interval_time = s.startup_time
          THEN t.value
          ELSE t.value - lag (t.value ) over (partition BY s.instance_number order by s.snap_id)
        END dbt
      FROM &DBV~_hist_snapshot s,
        &DBV~_hist_sys_time_model t
      WHERE s.dbid          = t.dbid
      AND s.dbid            = &DBID
      AND s.instance_number = t.instance_number
      AND s.snap_id         = t.snap_id
      AND s.snap_id BETWEEN &SNAP_ID_MIN and &SNAP_ID_MAX
      AND t.stat_name = 'DB time'
      ORDER BY s.snap_id,
        s.instance_number
      )
    GROUP BY snap_id
    HAVING SUM(dbt) > 0
    ) b
  WHERE a.snap_id = b.snap_id
  GROUP BY a.snap_id,
    a.wait_class,
    a.event_name,
    b.dbt
  )
WHERE pctdbt > 0
AND rnk     <= 5
ORDER BY snap_id,
  pctdbt DESC; 



REPHEADER OFF
REPFOOTER OFF


prompt 
prompt 
-- ##############################################################################################


REPHEADER PAGE LEFT '~~BEGIN-SYSSTAT~~'
REPFOOTER PAGE LEFT '~~END-SYSSTAT~~'
SELECT SNAP_ID,
  MAX(DECODE(event_name,'cell flash cache read hits', event_val_diff,NULL)) "cell_flash_hits",
  MAX(DECODE(event_name,'physical read total IO requests', event_val_diff,NULL)) "read_iops",
  ROUND(MAX(DECODE(event_name,'physical read total bytes', event_val_diff,NULL))                                 /1024/1024,1) "read_mb",
  ROUND(MAX(DECODE(event_name,'physical read total bytes optimized', event_val_diff,NULL))                       /1024/1024,1) "read_mb_opt",
  ROUND(MAX(DECODE(event_name,'cell physical IO interconnect bytes', event_val_diff,NULL))                       /1024/1024,1) "cell_int_mb",
  ROUND(MAX(DECODE(event_name,'cell physical IO interconnect bytes returned by smart scan', event_val_diff,NULL))/1024/1024,1) "cell_int_ss_mb",
  MAX(DECODE(event_name,'EHCC Conventional DMLs', event_val_diff,NULL)) "ehcc_con_dmls"
FROM
  (SELECT snap_id,
    event_name,
    ROUND(SUM(val_per_s),1) event_val_diff
  FROM
    (SELECT snap_id,
      instance_number,
      event_name,
      event_val_diff,
      (event_val_diff/ela) val_per_s
    FROM
      (SELECT (CAST (s.end_interval_time AS DATE) - CAST (s.begin_interval_time AS DATE)) * 24 * 3600 ela,
        s.snap_id,
        s.instance_number,
        t.stat_name wait_class,
        t.stat_name event_name,
        CASE
          WHEN s.begin_interval_time = s.startup_time
          THEN t.value
          ELSE t.value - lag (value) over (partition BY stat_id, t.dbid, t.instance_number, s.startup_time order by t.snap_id)
        END event_val_diff
      FROM &DBV~_hist_snapshot s,
        &DBV~_hist_sysstat t
      WHERE s.dbid = t.dbid
      AND s.dbid   = &DBID
      AND s.instance_number = t.instance_number
      AND s.snap_id         = t.snap_id
      AND s.snap_id BETWEEN &SNAP_ID_MIN AND &SNAP_ID_MAX
      AND t.snap_id BETWEEN &SNAP_ID_MIN AND &SNAP_ID_MAX
      AND t.stat_name IN ('cell flash cache read hits','physical read total IO requests', 'cell physical IO bytes saved by storage index',
      'EHCC Conventional DMLs', 'cell physical IO interconnect bytes','cell physical IO interconnect bytes returned by smart scan', 
      'physical read total bytes','physical read total bytes optimized' )
      )
    WHERE event_val_diff IS NOT NULL
    )
  GROUP BY snap_id,
    event_name
  )
GROUP BY snap_id
ORDER BY SNAP_ID ASC;


prompt
prompt
-- ##############################################################################################

REPHEADER PAGE LEFT '~~BEGIN-SEGMENT-IO~~'
REPFOOTER PAGE LEFT '~~END-SEGMENT-IO~~'

define seg_io_schema_exclusion_list = "'SYS','SYSTEM','SYSMAN','OUTLN','DBSNMP','DIP','EXFSYS','MDSYS','ORACLE_OCM','ORDPLUGINS','ORDSYS','WMSYS','XDB'"

WITH
     v_uptime as
       (
        SELECT COUNT(1)                                                           AS inst_cnt
              ,TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'UTC', 'YYYY/MON/DD HH24:MI:SS') AS report_time_utc
              ,TO_CHAR(MIN(i.startup_time),             'YYYY/MON/DD HH24:MI:SS') AS startup_time
              ,TRUNC(MIN(SYSDATE - i.startup_time) * 24 * 60 *60)                 AS uptime_sec
        FROM   gv$instance i, gv$database d
        WHERE  i.inst_id = d.inst_id
       )
    ,v_segstats AS
       (
        SELECT vss.*
               ,ROUND(    segs.bytes /1024 /1024 /1024, 4)                                                                      AS partition_size_gb
               ,ROUND(SUM(segs.bytes /1024 /1024 /1024) OVER(PARTITION BY segs.owner, segs.segment_type, segs.segment_name), 3) AS seg_size_gb
               ,    CASE WHEN segs.segment_name IS NOT NULL THEN physical_reads         ELSE 0 END                              AS seg_physical_reads
               ,    CASE WHEN segs.segment_name IS NOT NULL THEN physical_writes        ELSE 0 END                              AS seg_physical_writes
               ,    CASE WHEN segs.segment_name IS NOT NULL THEN physical_reads_direct  ELSE 0 END                              AS seg_physical_reads_direct
               ,    CASE WHEN segs.segment_name IS NOT NULL THEN physical_writes_direct ELSE 0 END                              AS seg_physical_writes_direct
               ,SUM(CASE WHEN segs.segment_name IS NOT NULL THEN physical_reads         ELSE 0 END) OVER ()                     AS seg_physical_reads_tot
               ,SUM(CASE WHEN segs.segment_name IS NOT NULL THEN physical_writes        ELSE 0 END) OVER ()                     AS seg_physical_writes_tot
               ,SUM(physical_reads)  OVER ()                                                                                    AS physical_reads_tot
               ,SUM(physical_writes) OVER ()                                                                                    AS physical_writes_tot
               ,CASE WHEN segs.segment_name IS NOT NULL THEN 1 ELSE 0 END                                                       AS segment_present_flg
        FROM  (
               SELECT stats.owner, stats.object_type, stats.object_name, stats.tablespace_name, stats.subobject_name,
                      stats.statistic_name, stats.value
               FROM   &DBV~_tablespaces       ts
                     ,gv$segment_statistics stats
               WHERE  stats.owner      NOT IN (&seg_io_schema_exclusion_list)
               AND    stats.tablespace_name  = ts.tablespace_name
               AND    ts.contents           <> 'TEMPORARY'
              )
        PIVOT (
               SUM(value) FOR statistic_name IN (
                                                 'physical reads'         AS "PHYSICAL_READS",
                                                 'physical reads direct'  AS "PHYSICAL_READS_DIRECT",
                                                 'physical writes'        AS "PHYSICAL_WRITES",
                                                 'physical writes direct' AS "PHYSICAL_WRITES_DIRECT"
                                                )
              ) vss
             ,&DBV~_segments segs
       WHERE  vss.subobject_name  = segs.partition_name  (+)
       AND    vss.tablespace_name = segs.tablespace_name (+)
       AND    vss.object_type     = segs.segment_type    (+)
       AND    vss.object_name     = segs.segment_name    (+)
       AND    vss.owner           = segs.owner           (+)
       )
    ,v_dbsize AS
       (
        SELECT ROUND(SUM(bytes / 1024 /1024 /1024), 3)  AS db_size_gb
        FROM   &DBV~_segments
       )
    ,v_diskdfalloc AS
       (
        SELECT ROUND(SUM(bytes) / 1024 / 1024 /1024, 3) AS db_disk_space_alloc_gb
        FROM   &DBV~_data_files
       )
    ,v_disktempalloc AS
       (
        SELECT ROUND(SUM(bytes) /1024 /1024 /1024, 3)  AS db_temp_space_alloc_gb
        FROM   &DBV~_temp_files
       )
SELECT v.*
      ,DECODE (v.seg_physical_io_tot, 0, 0, ROUND((v.seg_physical_io_running / (v.seg_physical_io_tot)) * 100, 5)) AS seg_phy_io_pct
      ,DECODE (v.physical_io_tot, 0, 0, ROUND((v.physical_io_running     / (v.physical_io_tot))     * 100, 5)) AS phy_io_pct
      ,COUNT(1) OVER() AS rows_tot
FROM  (
       SELECT stats.owner AS owner
             ,stats.object_name AS object_name
             ,stats.object_type AS object_type
             ,stats.subobject_name AS subobject_name
             ,stats.tablespace_name AS tablespace_name
             ,SUM(stats.partition_size_gb) OVER
             (ORDER BY stats.physical_reads + stats.physical_writes DESC, ROWNUM) AS partition_size_gb_running
             ,stats.partition_size_gb
             ,stats.seg_size_gb
             ,db_size_gb
             ,db_disk_space_alloc_gb
             ,db_temp_space_alloc_gb
             ,stats.seg_physical_reads, stats.seg_physical_writes
             ,stats.seg_physical_reads + stats.seg_physical_writes                         AS seg_physical_io
             ,SUM(      stats.seg_physical_reads + stats.seg_physical_writes) OVER
              (ORDER BY stats.seg_physical_reads + stats.seg_physical_writes DESC, ROWNUM) AS seg_physical_io_running
             ,stats.seg_physical_reads_tot + stats.seg_physical_writes_tot                 AS seg_physical_io_tot
             ,stats.physical_reads, stats.physical_writes
             ,stats.physical_reads + stats.physical_writes                                 AS physical_io
             ,SUM(      stats.physical_reads + stats.physical_writes) OVER
              (ORDER BY stats.physical_reads + stats.physical_writes DESC, ROWNUM)         AS physical_io_running
             ,stats.physical_reads_tot + stats.physical_writes_tot                         AS physical_io_tot
             ,stats.physical_reads_direct,     stats.physical_writes_direct
             ,stats.seg_physical_reads_direct, stats.seg_physical_writes_direct
             ,inst_cnt, startup_time, report_time_utc, uptime_sec, stats.segment_present_flg
       FROM   v_uptime
             ,v_dbsize
             ,v_diskdfalloc
             ,v_disktempalloc
             ,v_segstats       stats
) v
WHERE ROWNUM <= 1 
OR (v.seg_physical_io_tot > 0 AND ROUND((v.seg_physical_io_running / (v.seg_physical_io_tot)) * 100, 3) < 101)
ORDER BY seg_physical_io DESC;


prompt 
prompt 

-- ##############################################################################################




REPHEADER PAGE LEFT '~~BEGIN-TOP-SQL-SUMMARY~~'
REPFOOTER PAGE LEFT '~~END-TOP-SQL-SUMMARY~~'	

SELECT * FROM(
SELECT substr(REGEXP_REPLACE(s.module,'^(.+?)@.+$','\1'),1,30) module,s.action,s.sql_id,
decode(t.command_type,11,'ALTERINDEX',15,'ALTERTABLE',170,'CALLMETHOD',9,'CREATEINDEX',1,'CREATETABLE',
7,'DELETE',50,'EXPLAIN',2,'INSERT',26,'LOCKTABLE',47,'PL/SQLEXECUTE',
3,'SELECT',6,'UPDATE',189,'UPSERT') command_name,
PARSING_SCHEMA_NAME,
DENSE_RANK() OVER
      (ORDER BY sum(EXECUTIONS_DELTA) DESC ) exec_rank,
DENSE_RANK() OVER
      (ORDER BY sum(ELAPSED_TIME_DELTA) DESC ) elap_rank,
DENSE_RANK() OVER
      (ORDER BY sum(BUFFER_GETS_DELTA) DESC ) log_reads_rank,
DENSE_RANK() OVER
      (ORDER BY sum(disk_reads_delta) DESC ) phys_reads_rank,
	  sum(EXECUTIONS_DELTA) execs,
sum(ELAPSED_TIME_DELTA) elap,
sum(BUFFER_GETS_DELTA) log_reads,
round(sum(disk_reads_delta * &DB_BLOCK_SIZE)/1024/1024/1024) phy_read_gb,
      count(distinct plan_hash_value) plan_count,
	  sum(px_servers_execs_delta) px_servers_execs
 FROM &DBV~_hist_sqlstat s,&DBV~_hist_sqltext t
 WHERE s.dbid = &DBID  
  AND s.snap_id BETWEEN &SNAP_ID_MIN and &SNAP_ID_MAX
   AND s.dbid = t.dbid
  AND s.sql_id = t.sql_id
  AND PARSING_SCHEMA_NAME NOT IN ('SYS','DBSNMP','SYSMAN')
  GROUP BY s.module,s.action,s.sql_id,t.command_type,PARSING_SCHEMA_NAME)
WHERE elap_rank <= &SQL_TOP_N
 OR phys_reads_rank <= &SQL_TOP_N
 or log_reads_rank <= &SQL_TOP_N
 or exec_rank <= &SQL_TOP_N
 order by elap_rank asc nulls last;

 
 
 
 
column PARSING_SCHEMA_NAME format a32
REPHEADER PAGE LEFT '~~BEGIN-TOP-SQL-BY-SNAPID~~'
REPFOOTER PAGE LEFT '~~END-TOP-SQL-BY-SNAPID~~'	
column module format a33
column action format a33

select * from(
SELECT s.snap_id,PARSING_SCHEMA_NAME,PLAN_HASH_VALUE plan_hash,substr(REGEXP_REPLACE(s.module,'^(.+?)@.+$','\1'),1,30) module,
substr(s.action,1,30) action, 
s.sql_id,
decode(t.command_type,11,'ALTERINDEX',15,'ALTERTABLE',170,'CALLMETHOD',9,'CREATEINDEX',1,'CREATETABLE',
7,'DELETE',50,'EXPLAIN',2,'INSERT',26,'LOCKTABLE',47,'PL/SQLEXECUTE',
3,'SELECT',6,'UPDATE',189,'UPSERT') command_name,sum(EXECUTIONS_DELTA) execs,sum(BUFFER_GETS_DELTA) buffer_gets,sum(ROWS_PROCESSED_DELTA) rows_proc,
round(sum(CPU_TIME_DELTA)/1000000,1) cpu_t_s,round(sum(ELAPSED_TIME_DELTA)/1000000,1) elap_s,
round(sum(disk_reads_delta * &DB_BLOCK_SIZE)/1024/1024,1) read_mb,round(sum(IOWAIT_DELTA)/1000000,1) io_wait,
DENSE_RANK() OVER (PARTITION BY s.snap_id ORDER BY sum(ELAPSED_TIME_DELTA) DESC ) elap_rank,
      CASE WHEN MAX(PLAN_HASH_VALUE) = LAG(MAX(PLAN_HASH_VALUE), 1, 0) OVER (PARTITION BY s.sql_id ORDER BY s.snap_id ASC) 
      OR LAG(MAX(PLAN_HASH_VALUE), 1, 0) OVER (PARTITION BY s.sql_id ORDER BY s.snap_id ASC) = 0 THEN 0
      when count(distinct PLAN_HASH_VALUE) > 1 then 1 else 1 end plan_change,
      count(distinct PLAN_HASH_VALUE) OVER       (PARTITION BY s.snap_id,s.sql_id ) plans,
      round(sum(disk_reads_delta * &DB_BLOCK_SIZE)/1024/1024/1024) phy_read_gb,
      sum(s.px_servers_execs_delta) px_servers_execs,
      round(sum(DIRECT_WRITES_DELTA * &DB_BLOCK_SIZE)/1024/1024/1024) direct_w_gb,
      sum(IOWAIT_DELTA) as iowait_time,
      sum(DISK_READS_DELTA) as PIO
  FROM &DBV~_hist_sqlstat s,&DBV~_hist_sqltext t
  WHERE s.dbid = &DBID  
  AND s.dbid = t.dbid
  AND s.sql_id = t.sql_id
  AND s.snap_id BETWEEN &SNAP_ID_MIN and &SNAP_ID_MAX
  AND PARSING_SCHEMA_NAME NOT IN ('SYS','DBSNMP','SYSMAN') 
  GROUP BY s.snap_id, PLAN_HASH_VALUE,t.command_type,PARSING_SCHEMA_NAME,s.module,s.action, s.sql_id)
  WHERE elap_rank <= &SQL_TOP_N --#
  --and sql_id = '2a22s56r25y6d'
  order by snap_id,elap_rank asc nulls last;


  
  
REPHEADER OFF
REPFOOTER OFF
TIMING STOP 
spool off

ALTER SESSION SET WORKAREA_SIZE_POLICY = AUTO;
