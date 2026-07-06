-- File Name: pdb.sql
-- Purpose: List CDB and PDB container status from GV$CONTAINERS
-- Supported: 23.5
-- Created: 20260704  by  huangtingzhong

SET FEEDBACK OFF
SET VERIFY OFF

col i                for a2
col c                for a3
col name             for a16
col inst_name        for a16
col container_type   for a8
col status           for a10
col compat_mode      for a8
col home             for a64

SELECT TO_CHAR(c.inst_id)  AS i,
       TO_CHAR(c.con_id)   AS c,
       c.name,
       i.instance_name     AS inst_name,
       c.type              AS container_type,
       c.status,
       c.compat_mode,
       c.home
  FROM gv$containers c,
       v$instance i
 WHERE i.instance_number = c.inst_id
 ORDER BY c.con_id, c.inst_id;
