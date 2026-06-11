COL i                FORMAT A2
COL inst_name        FORMAT A16
COL host             FORMAT A16
COL status           FORMAT A12
COL inst_role        FORMAT A16
COL db_status        FORMAT A16
COL parallel         FORMAT A8
COL in_reform        FORMAT A10
COL start_time       FORMAT A19
COL data_home        FORMAT A40
SELECT
    instance_number  || '' AS i,
    instance_name    AS inst_name,
    host_name        AS host,
    status,
    instance_role    AS inst_role,
    database_status  AS db_status,
    parallel,
    in_reform,
    startup_time     AS start_time,
    data_home
FROM v$instance
ORDER BY i, instance_number;