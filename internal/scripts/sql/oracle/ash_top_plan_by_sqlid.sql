-- File Name: ash_top_plan_by_sqlid.sql
-- Purpose: Oracle ASH Top Plan By Sqlid
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 2000 pages 1000 heading on verify off
col sql_id                   for a15
col sql_plan_hash_value      for 999999999999      heading 'PLAN_HASH_VALUE'
col sql_plan_line_id         for 999               heading 'ID'
col sql_plan_operation       for a20               heading 'OPERATION'
col sql_plan_options         for a20               heading 'OPTIONS'
col wait_class               for a10               heading 'WAIT_CLASS'
col event                    for a30               heading 'EVENT'
col sql_exec_id              for 9999999999        heading 'EXEC_ID'
col exec_count               for 9999999           heading 'EXEC_COUNT'
col id_event                 for 9999999           heading 'EVENT_BY_ID'
col plan_event               for 9999999           heading 'EVENT_BY_PLAN'
undefine sqlid;

--select *
--  from (select c.sql_id,
--               c.sql_plan_hash_value,
--               c.sql_plan_line_id,
--               --   c.sql_plan_operation,
--               --   c.sql_plan_options,
--               c.wait_class,
--               c.event,
--               c.sql_exec_id,
--               c.exec_count,
--               c.id_event,
--               c.plan_event,
--               row_number() over(order by id_event desc) id_event_order,
--               row_number() over(order by id_wait_class desc) id_wait_order,
--               row_number() over(order by plan_class desc) class_order,
--               row_number() over(order by exec_count desc) exec_count_order,
--               row_number() over(order by plan_event desc) exec_plan_order
--          from (select distinct b.sql_id,
--                                b.sql_plan_hash_value,
--                                b.SQL_PLAN_LINE_ID,
--                                --   b.sql_plan_operation,
--                                --   b.sql_plan_options,
--                                count(*) over(partition by b.sql_id, b.sql_plan_hash_value, b.sql_plan_line_id, event) id_event,
--                                b.event,
--                                count(*) over(partition by b.sql_id, b.sql_plan_hash_value, b.sql_plan_line_id, WAIT_CLASS) id_wait_class,
--                                WAIT_CLASS,
--                                count(*) over(partition by b.sql_id, b.sql_plan_hash_value, WAIT_CLASS) plan_class,
--                                count(*) over(partition by b.sql_id, b.sql_plan_hash_value, event) plan_event
--                ,b.sql_exec_id,
--               count(*) over(partition by b.sql_id, b.sql_exec_id) exec_count
--                  from (select a.sql_id,
--                               a.SQL_PLAN_HASH_VALUE,
--                               a.SQL_PLAN_LINE_ID,
--                               a.SQL_PLAN_OPERATION,
--                               a.SQL_PLAN_OPTIONS,
--                               a.sql_exec_id,
--                               a.program,
--                               DECODE(SESSION_STATE,
--                                      'ON CPU',
--                                      DECODE(SESSION_TYPE,
--                                             'BACKGROUND',
--                                             'BCPU',
--                                             'CPU'),
--                                      EVENT) EVENT,
--                               REPLACE(TRANSLATE(DECODE(SESSION_STATE,
--                                                        'ON CPU',
--                                                        DECODE(SESSION_TYPE,
--                                                               'BACKGROUND',
--                                                               'BCPU',
--                                                               'CPU'),
--                                                        WAIT_CLASS),
--                                                 ' $',
--                                                 '____'),
--                                       '/') WAIT_CLASS
--                          from v$active_session_history a
--                         where a.sql_id = 'dza1uz8j3xj4b'
--                           and a.sql_plan_line_id > 0) b) c)
-- where id_event_order < 2
--    or id_wait_order < 2
--    or class_order < 2
--    or exec_count_order < 2
--    or exec_plan_order < 2
--/
select sql_id,
       sql_plan_hash_value,
       sql_plan_line_id,
       sql_plan_operation,
       sql_plan_options,
       wait_class,
       substr(event,1,30) event,
       sql_exec_id,
       exec_count,
       id_event,
       plan_event
  from (select c.sql_id,
               c.sql_plan_hash_value,
               c.sql_plan_line_id,
               c.sql_plan_operation,
               c.sql_plan_options,
               c.wait_class,
               c.event,
               c.sql_exec_id,
               c.exec_count,
               c.id_event,
               c.plan_event,
               row_number() over(order by id_event desc) id_event_order,
               row_number() over(order by id_wait_class desc) id_wait_order,
               row_number() over(order by plan_class desc) class_order,
               row_number() over(order by exec_count desc) exec_count_order,
               row_number() over(order by plan_event desc) exec_plan_order
          from (select distinct b.sql_id,
                                b.sql_plan_hash_value,
                                b.SQL_PLAN_LINE_ID,
                                b.sql_plan_operation,
                                b.sql_plan_options,
                                count(*) over(partition by b.sql_id, b.sql_plan_hash_value, b.sql_plan_line_id, event) id_event,
                                b.event,
                                count(*) over(partition by b.sql_id, b.sql_plan_hash_value, b.sql_plan_line_id, WAIT_CLASS) id_wait_class,
                                WAIT_CLASS,
                                count(*) over(partition by b.sql_id, b.sql_plan_hash_value, WAIT_CLASS) plan_class,
                                count(*) over(partition by b.sql_id, b.sql_plan_hash_value, event) plan_event,
                                b.sql_exec_id,
                                count(*) over(partition by b.sql_id, b.sql_exec_id) exec_count
                  from (select a.sql_id,
                               a.SQL_PLAN_HASH_VALUE,
                               a.SQL_PLAN_LINE_ID,
                               a.SQL_PLAN_OPERATION,
                               a.SQL_PLAN_OPTIONS,
                               a.sql_exec_id,
                               a.program,
                               DECODE(SESSION_STATE,
                                      'ON CPU',
                                      DECODE(SESSION_TYPE,
                                             'BACKGROUND',
                                             'BCPU',
                                             'CPU'),
                                      EVENT) EVENT,
                               REPLACE(TRANSLATE(DECODE(SESSION_STATE,
                                                        'ON CPU',
                                                        DECODE(SESSION_TYPE,
                                                               'BACKGROUND',
                                                               'BCPU',
                                                               'CPU'),
                                                        WAIT_CLASS),
                                                 ' $',
                                                 '____'),
                                       '/') WAIT_CLASS
                          from v$active_session_history a
                         where a.sql_id = '&sqlid'
                           and a.sql_plan_line_id > 0) b) c)
 where id_event_order < 2
    or id_wait_order < 2
    or class_order < 2
    or exec_count_order < 2
    or exec_plan_order < 2
/
undefine sqlid;