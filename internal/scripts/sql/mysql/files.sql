-- File Name: files.sql
-- Purpose: MySQL Show InnoDB tablespace file usage
-- Created: 20260516  by  huangtingzhong

select file_type,tablespace_name,file_name,engine,round(total_extents*EXTENT_SIZE/1024/1024) as 'TOTAL_SIZE(M)',round(FREE_EXTENTS*EXTENT_SIZE/1024/1024) as 'FREE_SIZE(M)' ,round(data_free/1024/1024) as 'DATA_FREE' from information_schema.files order by 5;