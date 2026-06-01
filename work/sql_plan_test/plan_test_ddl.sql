-- File Name: plan_test_ddl.sql
-- Purpose: Five tables for execution-plan tests (subquery/outer join/filter)
-- Created: 20260516

-- Drop child-first (no PL/SQL block; yasql @file friendly)
DROP TABLE pt_plan_t5_sales;
DROP TABLE pt_plan_t4_assign;
DROP TABLE pt_plan_t3_proj;
DROP TABLE pt_plan_t2_emp;
DROP TABLE pt_plan_t1_dept;

CREATE TABLE pt_plan_t1_dept (
    dept_id   NUMBER        PRIMARY KEY,
    dept_name VARCHAR2(40)  NOT NULL,
    region    VARCHAR2(20)
);

CREATE TABLE pt_plan_t2_emp (
    emp_id    NUMBER        PRIMARY KEY,
    emp_name  VARCHAR2(40)  NOT NULL,
    dept_id   NUMBER,
    salary    NUMBER(10, 2),
    hired     DATE,
    CONSTRAINT pt_emp_dept_fk FOREIGN KEY (dept_id) REFERENCES pt_plan_t1_dept (dept_id)
);

CREATE INDEX pt_emp_dept_ix ON pt_plan_t2_emp (dept_id);
CREATE INDEX pt_emp_sal_ix ON pt_plan_t2_emp (salary);

CREATE TABLE pt_plan_t3_proj (
    proj_id   NUMBER        PRIMARY KEY,
    proj_name VARCHAR2(40)  NOT NULL,
    budget    NUMBER(12, 2)
);

CREATE TABLE pt_plan_t4_assign (
    emp_id    NUMBER NOT NULL,
    proj_id   NUMBER NOT NULL,
    pct_time  NUMBER(3) DEFAULT 100,
    PRIMARY KEY (emp_id, proj_id),
    CONSTRAINT pt_asg_emp_fk FOREIGN KEY (emp_id) REFERENCES pt_plan_t2_emp (emp_id),
    CONSTRAINT pt_asg_proj_fk FOREIGN KEY (proj_id) REFERENCES pt_plan_t3_proj (proj_id)
);

CREATE INDEX pt_asg_proj_ix ON pt_plan_t4_assign (proj_id);

CREATE TABLE pt_plan_t5_sales (
    sale_id   NUMBER        PRIMARY KEY,
    emp_id    NUMBER,
    sale_dt   DATE,
    amount    NUMBER(12, 2),
    status    VARCHAR2(10),
    CONSTRAINT pt_sale_emp_fk FOREIGN KEY (emp_id) REFERENCES pt_plan_t2_emp (emp_id)
);

CREATE INDEX pt_sale_emp_ix ON pt_plan_t5_sales (emp_id);
CREATE INDEX pt_sale_dt_ix ON pt_plan_t5_sales (sale_dt);

INSERT INTO pt_plan_t1_dept VALUES (10, 'R&D', 'EAST');
INSERT INTO pt_plan_t1_dept VALUES (20, 'Sales', 'WEST');
INSERT INTO pt_plan_t1_dept VALUES (30, 'HR', 'EAST');
INSERT INTO pt_plan_t1_dept VALUES (40, 'Ops', 'WEST');

INSERT INTO pt_plan_t2_emp VALUES (1001, 'Alice', 10, 12000, DATE '2020-01-15');
INSERT INTO pt_plan_t2_emp VALUES (1002, 'Bob', 10, 9500, DATE '2021-03-20');
INSERT INTO pt_plan_t2_emp VALUES (1003, 'Carol', 20, 11000, DATE '2019-11-01');
INSERT INTO pt_plan_t2_emp VALUES (1004, 'Dave', 20, 8000, DATE '2022-06-10');
INSERT INTO pt_plan_t2_emp VALUES (1005, 'Eve', 30, 7000, DATE '2023-02-28');
INSERT INTO pt_plan_t2_emp VALUES (1006, 'Frank', NULL, 6500, DATE '2024-08-05');

INSERT INTO pt_plan_t3_proj VALUES (200, 'Alpha', 500000);
INSERT INTO pt_plan_t3_proj VALUES (201, 'Beta', 300000);
INSERT INTO pt_plan_t3_proj VALUES (202, 'Gamma', 150000);

INSERT INTO pt_plan_t4_assign VALUES (1001, 200, 50);
INSERT INTO pt_plan_t4_assign VALUES (1001, 201, 50);
INSERT INTO pt_plan_t4_assign VALUES (1002, 200, 100);
INSERT INTO pt_plan_t4_assign VALUES (1003, 201, 80);
INSERT INTO pt_plan_t4_assign VALUES (1004, 202, 100);

INSERT INTO pt_plan_t5_sales VALUES (9001, 1001, DATE '2025-01-10', 1200, 'DONE');
INSERT INTO pt_plan_t5_sales VALUES (9002, 1001, DATE '2025-02-11', 800, 'DONE');
INSERT INTO pt_plan_t5_sales VALUES (9003, 1003, DATE '2025-01-20', 2500, 'DONE');
INSERT INTO pt_plan_t5_sales VALUES (9004, 1004, DATE '2025-03-05', 400, 'OPEN');
INSERT INTO pt_plan_t5_sales VALUES (9005, 1006, DATE '2025-03-06', 150, 'OPEN');
INSERT INTO pt_plan_t5_sales VALUES (9006, NULL, DATE '2025-03-07', 99, 'OPEN');

COMMIT;

SELECT 'PT_PLAN_TABLES_READY' AS tag FROM DUAL;
