-- File Name: mytid.sql
-- Purpose: PostgreSQL Mytid
-- Created: 20260516  by  huangtingzhong

select txid_current(),
 pg_current_wal_lsn(),
 pg_walfile_name(pg_current_wal_lsn()),
 pg_walfile_name_offset(pg_current_wal_lsn());
