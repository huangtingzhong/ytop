-- File Name: sess_killed.sql
-- Purpose: Oracle session Killed
-- Created: 20260516  by  huangtingzhong

    set pages 40 
    set lines 300
    select distinct spid, program 
      from (select a.spid, a.program 
              from v$process a 
             where a.BACKGROUND is null 
            MINUS 
            select a.spid, a.PROGRAM 
              from v$process a, v$session b 
             where a.addr = b.paddr) c 
     where c.program not like '%(%' 
       and c.spid is not null 
    / 
    select count(*) from v$session where status='KILLED' 
    / 
    set pages 0
    select 'kill -9 ' || spid 
      from (select distinct c.spid 
              from (select a.spid, a.program 
                      from v$process a 
                     where BACKGROUND is null 
                    MINUS 
                    select a.spid, a.PROGRAM 
                      from v$process a, v$session b 
                     where a.addr = b.paddr) c 
             where c.program not like '%(%' 
               and c.spid is not null) 
     /
   set pages 40