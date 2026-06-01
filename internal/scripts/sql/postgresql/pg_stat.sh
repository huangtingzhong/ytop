INTERVAL=1  # 秒级间隔

# 获取统计数据
get_stats() {
  psql -At -c "
    SELECT datname, xact_commit, xact_rollback, blks_read, blks_hit, tup_returned
    FROM pg_stat_database
    WHERE datname NOT IN ('template0', 'template1');
  "
}

# 表头
printf "%-20s %-20s %10s %10s %12s %12s %16s\n" \
  "timestamp" "database" "commits/s" "rollbacks/s" "blks_read/s" "blks_hit/s" "tup_returned/s"

# 旧值存储
declare -A STATS_BEFORE

# 初始统计
while IFS='|' read -r db commit rollback read hit returned; do
  STATS_BEFORE["$db"]="$commit|$rollback|$read|$hit|$returned"
done < <(get_stats)

# 主循环
while true; do
  sleep "$INTERVAL"
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

  while IFS='|' read -r db commit rollback read hit returned; do
    OLD="${STATS_BEFORE[$db]}"
    IFS='|' read -r o_commit o_rollback o_read o_hit o_returned <<< "$OLD"

    # 计算每秒增量（单位时间是1秒）
    d_commit=$(( commit - o_commit ))
    d_rollback=$(( rollback - o_rollback ))
    d_read=$(( read - o_read ))
    d_hit=$(( hit - o_hit ))
    d_returned=$(( returned - o_returned ))

    printf "%-20s %-20s %10d %10d %12d %12d %16d\n" \
      "$TIMESTAMP" "$db" "$d_commit" "$d_rollback" "$d_read" "$d_hit" "$d_returned"

    STATS_BEFORE["$db"]="$commit|$rollback|$read|$hit|$returned"
  done < <(get_stats)
done
