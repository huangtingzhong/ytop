-- File Name: sim_long.sql
-- Purpose: Continuous PL/SQL local TYPE/collection keep-alive (no schema table)
-- Created: 20260728 by huangtingzhong
--
-- Notes:
--   Session-local RECORD + associative array only; no CREATE TABLE / ALTER SYSTEM.
--   Collection is periodically cleared to avoid unbounded PGA growth.
--   Stop with Ctrl+C or KILL SESSION.

SET SERVEROUTPUT ON

DECLARE
  -- local RECORD (session only, not a schema object)
  TYPE t_item IS RECORD (
    id   NUMBER,
    note VARCHAR2(64),
    ts   TIMESTAMP
  );

  -- local associative array (defined inside the block body)
  TYPE t_item_tab IS TABLE OF t_item INDEX BY PLS_INTEGER;

  g_buf t_item_tab;
  g_seq NUMBER := 0;
  g_cnt NUMBER := 0;
  g_round NUMBER := 0;

  -- nested procedure: simulate light "business write" into PGA
  PROCEDURE do_work(p_batch_size IN PLS_INTEGER DEFAULT 100) IS
    v_rec t_item;
  BEGIN
    FOR i IN 1 .. p_batch_size LOOP
      g_seq := g_seq + 1;
      v_rec.id   := g_seq;
      v_rec.note := 'keep-alive-' || g_seq;
      v_rec.ts   := SYSTIMESTAMP;
      g_buf(g_seq) := v_rec;
    END LOOP;

    -- prevent unbounded collection growth
    IF g_buf.COUNT > 10000 THEN
      g_buf.DELETE;
    END IF;
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== PLSQL TYPE KEEP-ALIVE START ===');
  DBMS_OUTPUT.PUT_LINE('MODE=local RECORD + INDEX BY table + nested PROCEDURE');
  DBMS_OUTPUT.PUT_LINE('SCHEMA_OBJECT=none');
  DBMS_OUTPUT.PUT_LINE('HINT=watch session PGA / application pool; no HTZ table');

  LOOP
    g_round := g_round + 1;
    do_work(50);
    -- light SQL so the session stays active with statement activity
    SELECT COUNT(*) INTO g_cnt FROM dual;
    IF MOD(g_round, 10000) = 0 THEN
      DBMS_OUTPUT.PUT_LINE('round=' || g_round ||
                           ' g_seq=' || g_seq ||
                           ' buf_count=' || g_buf.COUNT);
    END IF;
  END LOOP;
END;
/
