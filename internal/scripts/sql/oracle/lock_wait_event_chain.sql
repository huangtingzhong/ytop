-- File Name: lock_wait_event_chain.sql
-- Purpose: Oracle Lock Wait Event Chain
-- Created: 20260516  by  huangtingzhong

set pages 1000
set lines 250
set heading on
col OSPID         for  a10
col BLOCKER_PROC  for a10
col waiters       for  9999
col FBLOCKER_PROC for a10
col WAIT_EVENT    for a20
col PN            for a25
col WAIT_SECS     for a10
col CHAIN_SIGNATURE for a100
SELECT *
FROM (SELECT osid||':'||instance OSPID,decode(blocker_osid,null,'<none>',blocker_osid)||':'||blocker_instance BLOCKER_PROC,
 decode(p.spid,null,'<none>',p.spid)||':'||s.final_blocking_instance FBLOCKER_PROC,
 substr(wait_event_text,1,20) wait_event, wc.p1||':'||wc.p2||':'||wc.p3 pn,
 in_wait_secs||':'||time_since_last_wait_secs WAIT_SECS,
 chain_id ||': '||chain_signature chain_signature
FROM v$wait_chains wc,
 gv$session s,
 gv$session bs,
 gv$instance i,
 gv$process p
WHERE wc.instance = i.instance_number (+)
 AND (wc.instance = s.inst_id (+) and wc.sid = s.sid (+)
 and wc.sess_serial# = s.serial# (+))
 AND (s.final_blocking_instance = bs.inst_id (+) and s.final_blocking_session = bs.sid (+))
 AND (bs.inst_id = p.inst_id (+) and bs.paddr = p.addr (+))
 AND ( num_waiters > 0
 OR ( blocker_osid IS NOT NULL
 AND in_wait_secs > 10 ) )
ORDER BY chain_id,
 num_waiters DESC)
WHERE ROWNUM < 101;

