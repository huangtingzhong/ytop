-- File Name: plugins.sql
-- Purpose: MySQL Show plugins and plugin status
-- Created: 20260603  by  huangtingzhong

SELECT
    PLUGIN_NAME,
    PLUGIN_VERSION,
    PLUGIN_STATUS,
    PLUGIN_TYPE,
    PLUGIN_LIBRARY,
    LOAD_OPTION,
    PLUGIN_AUTHOR,
    PLUGIN_DESCRIPTION
FROM information_schema.PLUGINS
ORDER BY PLUGIN_TYPE, PLUGIN_NAME;
