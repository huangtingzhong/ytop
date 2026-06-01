-- File Name: sess_dead.sql
-- Purpose: Oracle session Dead
-- Created: 20260516  by  huangtingzhong

select distinct KTUXECFL, count(*) from x$ktuxe group by KTUXECFL;


select ADDR, KTUXEUSN, KTUXESLT, KTUXESQN, KTUXESIZ
  from x$ktuxe
 where KTUXECFL = 'DEAD';

ACCEPT b_hour prompt 'DO YOU COMPUTE RECOVERY TIME :DO ENTER ,NOT CTRL+C: '

ACCEPT usn prompt 'Enter Search Usn (i.e. 3) : '
ACCEPT slt prompt 'Enter Search Slt (i.e. 4) : '
variable  l_usn   number;
variable  l_slt   number;
begin
  :l_usn:=&usn;
  :l_slt:=&slt;
end;
/
set serveroutput on
declare
  l_start number;
  l_end   number;
begin
  select ktuxesiz
    into l_start
    from x$ktuxe
   where KTUXEUSN = :l_usn
     and KTUXESLT = :l_slt;
  dbms_lock.sleep(60);
  select ktuxesiz
    into l_end
    from x$ktuxe
   where KTUXEUSN = :l_usn
     and KTUXESLT = :l_slt;
  dbms_output.put_line('time cost Hours:' ||
                       round(l_end / (l_start - l_end) / 60, 2));
end;
/
