-- File Name: ash_info.sql
-- Purpose: YashanDB ASH buffer statistics (GV$ASH_INFO, cluster)
-- Created: 20260613  by  huangtingzhong
-- Oracle ref: (none)

col inst               for a3
col sampling_interval  for a8
col sample_count       for a12
col dropped            for a8
col oldest             for a19
col latest             for a19
col total_size         for a12
col sampled_bytes      for a12
col awr_flush          for a6



SELECT TO_CHAR(inst_id) AS inst,
       TO_CHAR(sampling_interval) AS sampling_interval,
       TO_CHAR(sample_count) AS sample_count,
       TO_CHAR(dropped_sample_count) AS dropped,
       TO_CHAR(oldest_sample_time, 'YYYY-MM-DD HH24:MI:SS') AS oldest,
       TO_CHAR(latest_sample_time, 'YYYY-MM-DD HH24:MI:SS') AS latest,
       TO_CHAR(total_size) AS total_size,
       TO_CHAR(sampled_bytes) AS sampled_bytes,
       TO_CHAR(awr_flush_count) AS awr_flush
  FROM gv$ash_info
 ORDER BY inst_id;
