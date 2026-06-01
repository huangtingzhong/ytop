set serveroutput on;
prompt PLAN from v$sql_plan
prompt ****************************************************************************************

DECLARE
    v_sql_id          VARCHAR2(13) := '4r45cmukz9dgs';
    v_plan_count      NUMBER := 0;
    v_ord_seq         NUMBER := 0;
    v_indent          VARCHAR2(100);
    v_operation       VARCHAR2(4000);
    v_object_info     VARCHAR2(200);
    v_id_str          VARCHAR2(10);
    v_pid_str         VARCHAR2(10);
    v_display_pid     NUMBER;
    v_ord_str         VARCHAR2(10);
    v_operation_str   VARCHAR2(40);
    v_name_str        VARCHAR2(30);
    v_rows_str        VARCHAR2(12);
    v_cost_str        VARCHAR2(10);
    v_time_str        VARCHAR2(10);

    TYPE t_ord_map IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    TYPE t_plan_rec IS RECORD (
        id          NUMBER,
        parent_id   NUMBER,
        position    NUMBER,
        operation   VARCHAR2(4000),
        options     VARCHAR2(4000)
    );
    TYPE t_plan_tab IS TABLE OF t_plan_rec;
    TYPE t_child_tab IS TABLE OF NUMBER;

    g_ord         t_ord_map;
    g_disp_parent t_ord_map;
    g_plan_rows   t_plan_tab;

    CURSOR c_plans IS
        SELECT ph
          FROM (
                SELECT DISTINCT plan_hash_value AS ph
                  FROM v$sql_plan
                 WHERE sql_id = v_sql_id
                 ORDER BY plan_hash_value
               );

    FUNCTION get_indent(p_depth INTEGER) RETURN VARCHAR2 IS
    BEGIN
        RETURN LPAD(' ', (p_depth * 2), ' ');
    END;

    -- YashanDB: INDEX 常与 TABLE ACCESS BY INDEX ROWID 并列挂在 JOIN 下；
    -- 展示/执行序树需把 INDEX 挂到 TABLE ACCESS 下，与 Oracle XPLAN 一致。
    FUNCTION find_tab_access_parent(p_id NUMBER, p_parent_id NUMBER) RETURN NUMBER IS
        v_tab_id NUMBER := NULL;
    BEGIN
        FOR i IN 1 .. g_plan_rows.COUNT LOOP
            IF g_plan_rows(i).parent_id = p_parent_id
               AND g_plan_rows(i).id < p_id
               AND (
                     g_plan_rows(i).operation LIKE '%BY INDEX ROWID%'
                     OR NVL(g_plan_rows(i).options, ' ') LIKE '%INDEX ROWID%'
                   ) THEN
                IF v_tab_id IS NULL OR g_plan_rows(i).id > v_tab_id THEN
                    v_tab_id := g_plan_rows(i).id;
                END IF;
            END IF;
        END LOOP;
        RETURN v_tab_id;
    END find_tab_access_parent;

    PROCEDURE load_plan_rows(p_ph NUMBER) IS
    BEGIN
        SELECT id, parent_id, position, operation, options
          BULK COLLECT INTO g_plan_rows
          FROM v$sql_plan
         WHERE sql_id = v_sql_id
           AND plan_hash_value = p_ph
           AND id IS NOT NULL
           AND operation IS NOT NULL;
    END load_plan_rows;

    PROCEDURE build_display_parent IS
    BEGIN
        g_disp_parent.DELETE;
        FOR i IN 1 .. g_plan_rows.COUNT LOOP
            IF g_plan_rows(i).parent_id IS NULL
               OR g_plan_rows(i).operation NOT LIKE 'INDEX%' THEN
                g_disp_parent(g_plan_rows(i).id) := g_plan_rows(i).parent_id;
            ELSE
                v_display_pid := find_tab_access_parent(
                    g_plan_rows(i).id, g_plan_rows(i).parent_id
                );
                IF v_display_pid IS NOT NULL THEN
                    g_disp_parent(g_plan_rows(i).id) := v_display_pid;
                ELSE
                    g_disp_parent(g_plan_rows(i).id) := g_plan_rows(i).parent_id;
                END IF;
            END IF;
        END LOOP;
    END build_display_parent;

    FUNCTION plan_position(p_id NUMBER) RETURN NUMBER IS
    BEGIN
        FOR i IN 1 .. g_plan_rows.COUNT LOOP
            IF g_plan_rows(i).id = p_id THEN
                RETURN NVL(g_plan_rows(i).position, 0);
            END IF;
        END LOOP;
        RETURN 0;
    END plan_position;

    FUNCTION list_display_children(p_parent_id NUMBER) RETURN t_child_tab IS
        v_children t_child_tab := t_child_tab();
        v_swap     NUMBER;
        v_pos_i    NUMBER;
        v_pos_j    NUMBER;
    BEGIN
        FOR i IN 1 .. g_plan_rows.COUNT LOOP
            IF NVL(g_disp_parent(g_plan_rows(i).id), -1) = NVL(p_parent_id, -1) THEN
                v_children.EXTEND;
                v_children(v_children.COUNT) := g_plan_rows(i).id;
            END IF;
        END LOOP;
        -- Oracle 执行序：同级先上后下、先左后右 → position/id 升序，再后序编号
        IF v_children.COUNT > 1 THEN
            FOR i IN 1 .. v_children.COUNT - 1 LOOP
                FOR j IN i + 1 .. v_children.COUNT LOOP
                    v_pos_i := plan_position(v_children(i));
                    v_pos_j := plan_position(v_children(j));
                    IF v_pos_j < v_pos_i
                       OR (v_pos_j = v_pos_i AND v_children(j) < v_children(i)) THEN
                        v_swap := v_children(i);
                        v_children(i) := v_children(j);
                        v_children(j) := v_swap;
                    END IF;
                END LOOP;
            END LOOP;
        END IF;
        RETURN v_children;
    END list_display_children;

    -- 展示父节点树 + 兄弟 position/id 升序 + 后序遍历 = Ord（1=最先执行）
    PROCEDURE walk_plan_ord(p_parent_id NUMBER, io_ord IN OUT NUMBER) IS
        v_children t_child_tab;
    BEGIN
        v_children := list_display_children(p_parent_id);
        FOR i IN 1 .. v_children.COUNT LOOP
            walk_plan_ord(v_children(i), io_ord);
            io_ord := io_ord + 1;
            g_ord(v_children(i)) := io_ord;
        END LOOP;
    END walk_plan_ord;

BEGIN
    FOR rec_plan IN c_plans LOOP
        v_plan_count := v_plan_count + 1;

        g_ord.DELETE;
        load_plan_rows(rec_plan.ph);
        build_display_parent;
        v_ord_seq := 0;
        walk_plan_ord(0, v_ord_seq);
        v_ord_seq := v_ord_seq + 1;
        g_ord(0) := v_ord_seq;

        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('============================================================================');
        DBMS_OUTPUT.PUT_LINE('Plan Hash Value: ' || rec_plan.ph);
        DBMS_OUTPUT.PUT_LINE('============================================================================');
        DBMS_OUTPUT.PUT_LINE('');

        DBMS_OUTPUT.PUT_LINE('|' ||
                            LPAD('Id', 4) || '|' ||
                            LPAD('Pid', 4) || '|' ||
                            LPAD('Ord', 4) || '|' ||
                            RPAD('Operation', 39) || '|' ||
                            RPAD('Name', 29) || '|' ||
                            RPAD('Rows', 11) || '|' ||
                            RPAD('Cost', 9) || '|' ||
                            RPAD('Time', 9) || '|');

        DBMS_OUTPUT.PUT_LINE('|' ||
                            LPAD('-', 4, '-') || '|' ||
                            LPAD('-', 4, '-') || '|' ||
                            LPAD('-', 4, '-') || '|' ||
                            RPAD('-', 39, '-') || '|' ||
                            RPAD('-', 29, '-') || '|' ||
                            LPAD('-', 11, '-') || '|' ||
                            LPAD('-', 9, '-') || '|' ||
                            LPAD('-', 9, '-') || '|');

        FOR rec_detail IN (
            SELECT id,
                   parent_id,
                   depth,
                   position,
                   operation,
                   options,
                   object_owner,
                   object_name,
                   object_type,
                   optimizer,
                   cost,
                   cardinality,
                   bytes,
                   cpu_cost,
                   io_cost,
                   access_predicates,
                   filter_predicates,
                   partition_start,
                   partition_stop,
                   other_tag,
                   other,
                   time AS plan_time
              FROM v$sql_plan
             WHERE sql_id = v_sql_id
               AND plan_hash_value = rec_plan.ph
               AND id IS NOT NULL
               AND operation IS NOT NULL
             ORDER BY id
        ) LOOP
            v_indent := get_indent(rec_detail.depth);
            v_operation := v_indent || rec_detail.operation;
            IF rec_detail.options IS NOT NULL THEN
                v_operation := v_operation || ' ' || rec_detail.options;
            END IF;

            IF rec_detail.object_name IS NOT NULL THEN
                v_object_info := rec_detail.object_owner || '.' || rec_detail.object_name;
                IF rec_detail.object_type IS NOT NULL THEN
                    v_object_info := v_object_info || ' [' || rec_detail.object_type || ']';
                END IF;
            ELSE
                v_object_info := '';
            END IF;

            v_id_str := LPAD(TO_CHAR(rec_detail.id), 4);
            v_display_pid := g_disp_parent(rec_detail.id);
            IF v_display_pid IS NULL THEN
                v_pid_str := LPAD(' ', 4);
            ELSE
                v_pid_str := LPAD(TO_CHAR(v_display_pid), 4);
            END IF;
            v_ord_str := LPAD(TO_CHAR(g_ord(rec_detail.id)), 4);
            v_operation_str := RPAD(SUBSTR(NVL(v_operation, ' '), 1, 39), 39);
            v_name_str := RPAD(SUBSTR(NVL(v_object_info, ' '), 1, 29), 29);
            v_rows_str := RPAD(NVL(TO_CHAR(rec_detail.cardinality), ' '), 11);
            v_cost_str := RPAD(NVL(TO_CHAR(rec_detail.cost), ' '), 9);
            v_time_str := RPAD(NVL(TO_CHAR(rec_detail.plan_time), ' '), 9);

            DBMS_OUTPUT.PUT_LINE(
                '|' || v_id_str || '|' ||
                v_pid_str || '|' ||
                v_ord_str || '|' ||
                v_operation_str || '|' ||
                v_name_str || '|' ||
                v_rows_str || '|' ||
                v_cost_str || '|' ||
                v_time_str || '|'
            );

            IF LENGTH(TRIM(NVL(rec_detail.access_predicates, ''))) > 0 THEN
                DBMS_OUTPUT.PUT_LINE(
                    '|' || LPAD(' ', 4) || '|' ||
                    LPAD(' ', 4) || '|' ||
                    LPAD(' ', 4) || '|' ||
                    RPAD('  -> Access: ' || SUBSTR(rec_detail.access_predicates, 1, 26), 39) || '|' ||
                    RPAD(' ', 29) || '|' ||
                    RPAD(' ', 11) || '|' ||
                    RPAD(' ', 9) || '|' ||
                    RPAD(' ', 9) || '|'
                );
            END IF;

            IF LENGTH(TRIM(NVL(rec_detail.filter_predicates, ''))) > 0 THEN
                DBMS_OUTPUT.PUT_LINE(
                    '|' || LPAD(' ', 4) || '|' ||
                    LPAD(' ', 4) || '|' ||
                    LPAD(' ', 4) || '|' ||
                    RPAD('  -> Filter: ' || SUBSTR(rec_detail.filter_predicates, 1, 26), 39) || '|' ||
                    RPAD(' ', 29) || '|' ||
                    RPAD(' ', 11) || '|' ||
                    RPAD(' ', 9) || '|' ||
                    RPAD(' ', 9) || '|'
                );
            END IF;

            IF NVL(rec_detail.partition_start, 0) <> 0
               OR NVL(rec_detail.partition_stop, 0) <> 0 THEN
                DBMS_OUTPUT.PUT_LINE(
                    '|' || LPAD(' ', 4) || '|' ||
                    LPAD(' ', 4) || '|' ||
                    LPAD(' ', 4) || '|' ||
                    RPAD('  -> Partition: ' ||
                         NVL(TO_CHAR(rec_detail.partition_start), '?') || '..' ||
                         NVL(TO_CHAR(rec_detail.partition_stop), '?'), 39) || '|' ||
                    RPAD(' ', 29) || '|' ||
                    RPAD(' ', 11) || '|' ||
                    RPAD(' ', 9) || '|' ||
                    RPAD(' ', 9) || '|'
                );
            END IF;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('============================================================================');
    END LOOP;

    IF v_plan_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('No plan found in V$SQL_PLAN for sql_id=' || v_sql_id);
    END IF;
END;
/
