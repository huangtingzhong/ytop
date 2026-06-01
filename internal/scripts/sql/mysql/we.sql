-- File Name: we.sql
-- Purpose: MySQL Session wait and SQL overview
-- Created: 20260418  by  huangtingzhong

SELECT
    CAST(p.ID AS CHAR) AS SID,
    SUBSTR(IFNULL(p.STATE, ''), 1, 30) AS EVENT,
    p.USER AS USERNAME,
    SUBSTR(IFNULL(p.INFO, ''), 1, 18) AS SQL_TEXT,
    CASE
        WHEN p.TIME < 1 THEN CONCAT(ROUND(p.TIME * 1000, 0), 'MS')
        WHEN p.TIME < 1000 THEN CONCAT(p.TIME, 'S')
        ELSE CONCAT(ROUND(p.TIME / 1000.0, 2), 'KS')
    END AS EXEC_TIME,
    SUBSTR(IFNULL(p.HOST, ''), 1, 30) AS CLIENT
FROM information_schema.PROCESSLIST p
WHERE p.COMMAND <> 'Sleep'
  AND p.USER <> 'system user'
ORDER BY p.TIME DESC;

-- Sessions with same SQL (potential contention)
SELECT
    SUBSTR(IFNULL(INFO, ''), 1, 60) AS SQL_TEXT,
    STATE AS WAIT_EVENT,
    COUNT(*) AS HCOUNT
FROM information_schema.PROCESSLIST
WHERE COMMAND <> 'Sleep'
  AND USER <> 'system user'
  AND INFO IS NOT NULL
GROUP BY INFO, STATE
HAVING COUNT(*) > 1
ORDER BY HCOUNT DESC;
