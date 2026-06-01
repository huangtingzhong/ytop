pg_waldump $1 2>/dev/null | \
awk '
{
    # 提取 WAL 大小
    if ($0 ~ /len \(rec\/tot\):/) {
        match($0, /len \(rec\/tot\): *([0-9]+)/, size_arr)
        size = size_arr[1]
    }

    # 提取操作类型
    if ($0 ~ /desc: /) {
        match($0, /desc: *([A-Z_]+)/, op_arr)
        op = op_arr[1]
    }

    # 提取 relfilenode 信息
    if ($0 ~ /blkref #[0-9]+: rel/) {
        match($0, /rel ([0-9]+\/[0-9]+\/[0-9]+)/, rel_arr)
        rel = rel_arr[1]
    }

    # 如果都提取到了，开始统计
    if (size != "" && op != "" && rel != "") {
        key = op "|" rel
        count[key]++
        total_size[key] += size

        # 重置
        size = ""
        op = ""
        rel = ""
    }
}
END {
    printf "%-15s %-25s %-10s %-15s\n", "Operation", "RelFileNode", "Count", "Total_Bytes"
    for (k in count) {
        split(k, a, "|")
        printf "%-15s %-25s %-10d %-15d\n", a[1], a[2], count[k], total_size[k]
    }
}'
