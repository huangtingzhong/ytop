-- File Name: plan_test_queries.sql
-- Purpose: Five SQL patterns for plan tests (subquery/outer join/filter)
-- Created: 20260516
-- Prerequisite: plan_test_ddl.sql

SET SERVEROUTPUT ON;

-- Q1: scalar subquery + FILTER (predicate on fact table)
SELECT /* PT_PLAN_Q1_FILTER_SUBQ */
       e.emp_id,
       e.emp_name,
       e.salary,
       (SELECT AVG(s2.salary)
          FROM pt_plan_t2_emp s2
         WHERE s2.dept_id = e.dept_id) AS dept_avg_sal
  FROM pt_plan_t2_emp e
 WHERE e.salary > (SELECT AVG(s3.salary) FROM pt_plan_t2_emp s3)
   AND e.dept_id IN (SELECT d.dept_id FROM pt_plan_t1_dept d WHERE d.region = 'EAST')
 ORDER BY e.emp_id;

-- Q2: LEFT OUTER JOIN (preserve driving row without match)
SELECT /* PT_PLAN_Q2_LEFT_JOIN */
       d.dept_name,
       e.emp_name,
       s.amount
  FROM pt_plan_t1_dept d
  LEFT JOIN pt_plan_t2_emp e ON e.dept_id = d.dept_id
  LEFT JOIN pt_plan_t5_sales s ON s.emp_id = e.emp_id AND s.status = 'DONE'
 WHERE d.region IN ('EAST', 'WEST')
 ORDER BY d.dept_id, e.emp_id;

-- Q3: RIGHT OUTER JOIN + aggregation
SELECT /* PT_PLAN_Q3_RIGHT_JOIN */
       p.proj_name,
       COUNT(a.emp_id) AS emp_cnt,
       SUM(a.pct_time) AS pct_sum
  FROM pt_plan_t4_assign a
 RIGHT JOIN pt_plan_t3_proj p ON p.proj_id = a.proj_id
 GROUP BY p.proj_id, p.proj_name
HAVING SUM(NVL(a.pct_time, 0)) >= 50
 ORDER BY p.proj_id;

-- Q4: FROM subquery + WHERE EXISTS (semi-join / subquery)
SELECT /* PT_PLAN_Q4_EXISTS_SUBQ */
       x.emp_id,
       x.emp_name,
       x.cnt_sale
  FROM (
        SELECT e.emp_id,
               e.emp_name,
               COUNT(s.sale_id) AS cnt_sale
          FROM pt_plan_t2_emp e
          JOIN pt_plan_t5_sales s ON s.emp_id = e.emp_id
         WHERE s.sale_dt >= DATE '2025-01-01'
         GROUP BY e.emp_id, e.emp_name
       ) x
 WHERE EXISTS (
           SELECT 1
             FROM pt_plan_t4_assign a
            WHERE a.emp_id = x.emp_id
              AND a.pct_time >= 50
       )
   AND x.cnt_sale >= 1
 ORDER BY x.cnt_sale DESC;

-- Q5: FULL OUTER JOIN + inline view + multi FILTER
SELECT /* PT_PLAN_Q5_FULL_FILTER */
       NVL(e.emp_name, '(no emp)') AS emp_name,
       NVL(p.proj_name, '(no proj)') AS proj_name,
       a.pct_time,
       s.amount
  FROM pt_plan_t2_emp e
  FULL OUTER JOIN pt_plan_t4_assign a ON a.emp_id = e.emp_id
  FULL OUTER JOIN pt_plan_t3_proj p ON p.proj_id = a.proj_id
  LEFT JOIN pt_plan_t5_sales s
    ON s.emp_id = e.emp_id
   AND s.amount > NVL(
         (SELECT MIN(s2.amount) FROM pt_plan_t5_sales s2 WHERE s2.status = 'DONE'),
         0)
 WHERE (e.salary IS NULL OR e.salary >= 7000)
   AND (p.budget IS NULL OR p.budget < 600000)
 ORDER BY e.emp_id, p.proj_id;
