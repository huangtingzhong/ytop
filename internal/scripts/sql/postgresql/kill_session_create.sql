-- File Name: kill_session_create.sql
-- Purpose: PostgreSQL Create function to kill PG sessions
-- Created: 20260516  by  huangtingzhong

CREATE OR REPLACE FUNCTION pg_kill_sessions(
    filter TEXT,         -- filter e.g. pid=123, user=john, active
    debug_level INT DEFAULT 1  -- 1=debug print only, 0=execute kill
) RETURNS void AS $$
DECLARE
    v_sql TEXT;
    v_pid INTEGER;
    v_filter_condition TEXT;
    v_filter_value TEXT;
    v_exec_result BOOLEAN;
    cur_session RECORD;
    v_kill_count INTEGER := 0;  -- killed session counter
BEGIN
    -- 1) validate parameters
    IF filter IS NULL OR TRIM(filter) = '' THEN
        RAISE NOTICE 'Error: Filter condition is empty. Function terminated.';
        RETURN;
    END IF;

    -- 2) build filter expression
    CASE
        WHEN TRIM(LOWER(filter)) LIKE 'pid=%' THEN
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 's.pid IN (' || v_filter_value || ')';
        WHEN TRIM(LOWER(filter)) LIKE 'user=%' THEN
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 'LOWER(s.usename) LIKE ''' || v_filter_value || '''';
        WHEN TRIM(LOWER(filter)) LIKE 'username=%' THEN
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 'LOWER(s.usename) LIKE ''' || v_filter_value || '''';
        WHEN TRIM(LOWER(filter)) LIKE 'application=%' THEN
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 'LOWER(s.application_name) LIKE ''' || v_filter_value || '''';
        WHEN TRIM(LOWER(filter)) LIKE 'client=%' THEN
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 'LOWER(s.client_addr::text) LIKE ''' || v_filter_value || '''';
        WHEN TRIM(LOWER(filter)) LIKE 'database=%' THEN
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 'LOWER(s.datname) LIKE ''' || v_filter_value || '''';
        WHEN TRIM(LOWER(filter)) LIKE 'state=%' THEN
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 'LOWER(s.state) LIKE ''' || v_filter_value || '''';
        WHEN TRIM(LOWER(filter)) LIKE 'query=%' THEN
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 'LOWER(s.query) LIKE ''' || v_filter_value || '''';
        WHEN TRIM(LOWER(filter)) LIKE 'all%' THEN
            v_filter_condition := 's.state != ''idle''';
        WHEN TRIM(LOWER(filter)) LIKE 'active%' THEN
            v_filter_condition := 's.state = ''active''';
        WHEN TRIM(LOWER(filter)) LIKE 'idle%' THEN
            v_filter_condition := 's.state = ''idle''';
        WHEN TRIM(LOWER(filter)) LIKE 'idle_in_transaction%' THEN
            v_filter_condition := 's.state = ''idle in transaction''';
        WHEN TRIM(LOWER(filter)) LIKE 'idle_in_transaction_aborted%' THEN
            v_filter_condition := 's.state = ''idle in transaction (aborted)''';
        WHEN TRIM(LOWER(filter)) LIKE 'fastpath%' THEN
            v_filter_condition := 's.state = ''fastpath function call''';
        WHEN TRIM(LOWER(filter)) LIKE 'disabled%' THEN
            v_filter_condition := 's.state = ''disabled''';
        WHEN TRIM(LOWER(filter)) LIKE '(%' THEN
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 's.pid IN (' || v_filter_value || ')';
        WHEN TRIM(LOWER(filter)) LIKE 'select%' OR TRIM(LOWER(filter)) LIKE 'with%' THEN
            v_filter_condition := 's.pid IN (' || filter || ')';
        ELSE
            v_filter_value := LOWER(TRIM(SUBSTRING(filter FROM POSITION('=' IN filter) + 1)));
            v_filter_condition := 's.pid IN (' || v_filter_value || ')';
    END CASE;

    -- 3) debug: show filter
    IF debug_level = 1 THEN
        RAISE NOTICE 'Filter condition: %', v_filter_condition;
    END IF;

    -- 4) query target sessions
    v_sql := 'SELECT s.pid, s.usename, s.datname, s.application_name, s.client_addr, s.state, s.query ' ||
             'FROM pg_stat_activity s ' ||
             'WHERE s.pid != pg_backend_pid() ' ||
             'AND (' || v_filter_condition || ')';

    FOR cur_session IN EXECUTE v_sql
    LOOP
        BEGIN
            v_pid := cur_session.pid;
            v_sql := 'SELECT pg_terminate_backend(' || v_pid || ')';

            IF debug_level = 1 THEN
                RAISE NOTICE 'DEBUG: PID=%, User=%, App=%, State=%, SQL=%', 
                    cur_session.pid, 
                    COALESCE(cur_session.usename, 'unknown'),
                    COALESCE(cur_session.application_name, 'unknown'),
                    cur_session.state,
                    v_sql;
            ELSE
                EXECUTE v_sql INTO v_exec_result;
                IF v_exec_result THEN
                    v_kill_count := v_kill_count + 1;
                    RAISE NOTICE 'SUCCESS: Terminated PID % (User=%, State=%)', 
                        cur_session.pid, cur_session.usename, cur_session.state;
                ELSE
                    RAISE NOTICE 'FAILED: Could not terminate PID % (User=%, State=%)', 
                        cur_session.pid, cur_session.usename, cur_session.state;
                END IF;
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'ERROR: Failed to terminate PID %: %', cur_session.pid, SQLERRM;
        END;
    END LOOP;

    -- 5) print final stats
    IF debug_level = 0 THEN
        IF v_kill_count > 0 THEN
            RAISE NOTICE 'SUMMARY: Successfully terminated % session(s)', v_kill_count;
        ELSE
            RAISE NOTICE 'SUMMARY: No sessions were terminated';
        END IF;
    END IF;

END;
$$ LANGUAGE plpgsql; 
