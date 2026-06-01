-- File Name: log_archive_10.sql
-- Purpose: Oracle Log Archive 10
-- Created: 20260516  by  huangtingzhong

--blog:  www.rescureora.com
--weixin: rescureora
--quick log switch helper
declare
   icount  number:=0;
begin
   while icount<10 loop
     execute immediate 'alter system switch logfile';
     icount:=icount+1;
   end loop;
end;
/