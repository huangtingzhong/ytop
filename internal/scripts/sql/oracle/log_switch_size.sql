-- File Name: log_switch_size.sql
-- Purpose: Oracle Log Switch Size
-- Created: 20260516  by  huangtingzhong

set echo off
set pages 2000 lines 400
col Day for a12
col Date for a12
col h0 for  a5 
col h1 for  a5 
col h2 for  a5 
col h3 for  a5 
col h4 for  a5 
col h5 for  a5 
col h6 for  a5 
col h7 for  a5 
col h8 for  a5 
col h9 for  a5 
col h10 for a5 
col h11 for a5 
col h12 for a5 
col h13 for a5 
col h14 for a5 
col h15 for a5 
col h16 for a5 
col h17 for a5 
col h18 for a5 
col h19 for a5 
col h20 for a5 
col h21 for a5 
col h22 for a5 
col h23 for a5 
 SELECT TRUNC (a.first_time) "Date",
         TO_CHAR (a.first_time, 'Dy') "Day",
         COUNT (1) "Total",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '00', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'00',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h0",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '01', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'01',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h1",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '02', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'02',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h2",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '03', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'03',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h3",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '04', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'04',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h4",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '05', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'05',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h5",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '06', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'06',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h6",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '07', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'07',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h7",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '08', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'08',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h8",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '09', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'09',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h9",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '10', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'10',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h10",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '11', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'11',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h11",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '12', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'12',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h12",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '13', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'13',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h13",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '14', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'14',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h14",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '15', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'15',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h15",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '16', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'16',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h16",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '17', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'17',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h17",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '18', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'18',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h18",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '19', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'19',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h19",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '20', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'20',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h20",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '21', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'21',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h21",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '22', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'22',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h22",
         SUM (DECODE (TO_CHAR (a.first_time, 'hh24'), '23', 1, 0))||':'||trunc(SUM (DECODE (TO_CHAR (a.first_time, 'hh24'),'23',  BLOCKS*BLOCK_size, 0))/1024/1024/1024) "h23",
         ROUND (COUNT (1) / 24, 2) "Avg"
    FROM V$log_history a,v$archived_log b where dest_id=1 and a.THREAD#=b.THREAD# and a.SEQUENCE#=b.SEQUENCE#
GROUP BY TRUNC (a.first_time), TO_CHAR (a.first_time, 'Dy')
ORDER BY 1
/
