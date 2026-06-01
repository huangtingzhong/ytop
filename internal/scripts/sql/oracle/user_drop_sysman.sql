-- File Name: user_drop_sysman.sql
-- Purpose: Oracle User Drop Sysman
-- Created: 20260516  by  huangtingzhong

drop user sysman cascade;
drop role MGMT_USER;
drop user MGMT_VIEW cascade;
drop public synonym Mgmt_Target_Blackouts;
drop public synonym setemviewusercontext;
