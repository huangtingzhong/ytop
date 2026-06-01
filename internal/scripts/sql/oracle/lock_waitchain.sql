-- File Name: lock_waitchain.sql
-- Purpose: Oracle Lock Waitchain
-- Created: 20260516  by  huangtingzhong

SET LINE 200
col sid          for    a20
col blocker_sid  for    a20
col FBLOCKER_SID for    a20
col wait_event   for    a30
    SELECT wc.chain_id,
           i.inst_id || ':' || wc.sid || ':' || wc.sess_serial# sid,
              DECODE (blocker_sid, NULL, '', blocker_sid)
           || ':'
           || DECODE (BLOCKER_SESS_SERIAL#, NULL, '', BLOCKER_SESS_SERIAL#)
           || ':'
           || blocker_instance
               blocker_sid,
               DECODE (s.final_blocking_instance,
                      NULL, '<>',
                      s.final_blocking_instance)
              ||':'
           || DECODE (s.final_blocking_session,
                      NULL, '<>',
                      s.final_blocking_session) FBLOCKER_SID,
           wait_event_text                                  wait_event,
           in_wait_secs                                     Seconds
      FROM v$wait_chains wc,
           gv$session s,
           gv$session bs,
           gv$instance i,
           gv$process p
     WHERE     wc.instance = i.instance_number(+)
           AND (    wc.instance = s.inst_id(+)
                AND wc.sid = s.sid(+)
                AND wc.sess_serial# = s.serial#(+))
           AND (    s.final_blocking_instance = bs.inst_id(+)
                AND s.final_blocking_session = bs.sid(+))
           AND (bs.inst_id = p.inst_id(+) AND bs.paddr = p.addr(+))
           AND (   num_waiters > 0
                OR (blocker_osid IS NOT NULL AND in_wait_secs > 10))
CONNECT BY     PRIOR wc.sid = blocker_sid
           AND PRIOR wc.sess_serial# = blocker_sess_serial#
           AND PRIOR i.inst_id = blocker_instance
START WITH blocker_is_valid = 'FALSE';
