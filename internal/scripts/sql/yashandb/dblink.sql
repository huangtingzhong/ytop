-- File Name: dblink.sql
-- Purpose: YashanDB List database links and connection status
-- Created: 20260516  by  huangtingzhong

-- Params: &link_owner, &link_name (empty means no filter; unset vars mean no filter).

SELECT A.OWNER,
       A.DB_LINK,
       C.STATUS,
       A.USERNAME,
       A.CREATED,
       DECODE(B.FLAG, 0, 'NO', 1, 'YES') AS "DEC",
       B.AUTHUSER AS AUTHUSR,
       A.HOST
  FROM DBA_DB_LINKS A
  JOIN SYS.USER$ U ON A.OWNER = U.NAME
  JOIN SYS.LINK$ B ON A.DB_LINK = B.NAME AND B.OWNER# = U.USER#
  JOIN DBA_OBJECTS C ON A.DB_LINK = C.OBJECT_NAME AND A.OWNER = C.OWNER AND C.OBJECT_TYPE = 'DATABASE LINK'
 WHERE A.OWNER = NVL('&link_owner',A.OWNER)
   AND A.DB_LINK = NVL('&link_name',A.DB_LINK)
 ORDER BY 1, 2, 3;
