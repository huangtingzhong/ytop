-- File Name: log_add_logfile.sql
-- Purpose: Oracle Log Add Logfile
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 200 pages 1000 verify off serveroutput on
DECLARE
   i_logsize           NUMBER;
   i_thread            NUMBER;
   i_group             NUMBER;
   i_number            NUMBER;
   i_number_inactive   NUMBER;
   i_sql               VARCHAR2 (1000);
   i_dgname            VARCHAR2 (100);
   i_group_count       NUMBER;
   i_groupcount        NUMBER;
   i_count             NUMBER;
BEGIN
   i_dgname := '&diskgroupname';
   i_logsize := '&logfilesize_m';
   i_groupcount := '&groupcount';

   FOR i_loggroup IN (  SELECT thread# thread1, COUNT (*) i_group_count
                          FROM v$log
                      GROUP BY thread#)
   LOOP
      i_count := i_loggroup.i_group_count;

      WHILE i_count < i_groupcount
      LOOP
         i_sql :=
               'alter database add logfile thread '
            || i_loggroup.thread1
            || ' ''+'
            || i_dgname
            || ''' size '
            || i_logsize
            || 'm';
         DBMS_OUTPUT.put_line (i_sql);

         EXECUTE IMMEDIATE i_sql;

         i_count := i_count + 1;
      END LOOP;
   END LOOP;

   SELECT COUNT (*)
     INTO i_number_inactive
     FROM v$log a
    WHERE a.BYTES < i_logsize * 1024 * 1024;

   WHILE i_number_inactive > 0
   LOOP
      FOR i_logfile IN (SELECT thread# thread, group# group1, status
                          FROM v$log a
                         WHERE a.BYTES < i_logsize * 1024 * 1024)
      LOOP
         IF i_logfile.status = 'INACTIVE'
         THEN
            i_sql := 'alter database drop logfile group ' || i_logfile.group1;
            DBMS_OUTPUT.put_line (i_sql);

            EXECUTE IMMEDIATE i_sql;

            i_sql :=
                  'alter database add logfile thread '
               || i_logfile.thread
               || ' group '
               || i_logfile.group1
               || ' '
               || '''+'
               || i_dgname
               || ''' size '
               || i_logsize
               || 'm';
            DBMS_OUTPUT.put_line (i_sql);

            EXECUTE IMMEDIATE i_sql;

            i_number_inactive := i_number_inactive - 1;
         ELSE
            i_sql := 'alter system archive log current';
            DBMS_OUTPUT.put_line (i_sql);

            EXECUTE IMMEDIATE i_sql;
         END IF;
      END LOOP;
   END LOOP;
END;
/