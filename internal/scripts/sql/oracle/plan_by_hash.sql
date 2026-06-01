-- File Name: plan_by_hash.sql
-- Purpose: Oracle Plan By Hash
-- Created: 20260516  by  huangtingzhong

set serverout on size 1000000
set verify off
SET PAGES 0
set linesize 300
set heading on
col operation format a50
col options format a30
col object_name for a11

ACCEPT hashvalue prompt 'Enter Search Sql Hash Value (i.e. CONTROL) : '
PROMPT
PROMPT

select '| Operation                         | PHV/Object Name                    |  Rows | Bytes|   Cost |'  
as "Optimizer Plan:" from dual
union all
select
    rpad('| '||substr(lpad(' ',1*(depth-1))||operation||
     decode(options, null,'',' '||options), 1, 35), 36, ' ')||'|'||
  rpad(decode(id, 0, '---------------------------------- '
    , substr(decode(substr(object_name, 1, 7), 'SYS_LE_', null, object_name)
       ||' ',1, 35)), 36, ' ')||'|'||
   lpad(decode(cardinality,null,'  ',
      decode(sign(cardinality-1000), -1, cardinality||' ',
      decode(sign(cardinality-1000000), -1, trunc(cardinality/1000)||'K',
      decode(sign(cardinality-1000000000), -1, trunc(cardinality/1000000)||'M',
      trunc(cardinality/1000000000)||'G')))), 7, ' ') || '|' ||
  lpad(decode(bytes,null,' ',
    decode(sign(bytes-1024), -1, bytes||' ',
    decode(sign(bytes-1048576), -1, trunc(bytes/1024)||'K',
       decode(sign(bytes-1073741824), -1, trunc(bytes/1048576)||'M',
         trunc(bytes/1073741824)||'G')))), 6, ' ') || '|' ||
    lpad(decode(cost,null,' ', decode(sign(cost-10000000), -1, cost||' ',
                decode(sign(cost-1000000000), -1, trunc(cost/1000000)||'M',
                       trunc(cost/1000000000)||'G'))), 8, ' ') || '|' as "Explain plan"
from v$sql_plan sp
where sp.hash_value=&hashvalue;
