-- File Name: mypid.sql
-- Purpose: PostgreSQL Mypid
-- Created: 20260516  by  huangtingzhong

 SELECT
  session_user login_user,
  current_user username,
  current_schema,
  current_database() database,
  pg_backend_pid(),
  inet_client_addr(),
  inet_client_port(),
  inet_server_addr(),
  inet_server_port()
  -- ,version()
  ;
