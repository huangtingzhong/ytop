-- File Name: mysql_insert_test_data.sql
-- Purpose: MySQL Insert sample rows for MySQL testing
-- Created: 20260516  by  huangtingzhong

drop table if exists huang.htz_test;
create table huang.htz_test( id bigint(20) unsigned not null auto_increment ,htz_name varchar(255),htz_password varchar(255),primary key(id));
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
insert into huang.htz_test (htz_name,htz_password) select md5(rand(1000)),md5(rand()) from huang.htz_test limit 100000;
