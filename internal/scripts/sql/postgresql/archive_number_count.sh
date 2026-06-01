ls -l --time-style=long-iso $1 | \
  grep -vE '\.history$|\.partial$' | \
  awk '
  NF >= 6 {
    date=$6
    time=$7
    hour=substr(time,1,2)
    key=date " " hour
    count[key]++
    size[key]+=$5
  }
  END {
    printf "%-12s %-5s %-8s %-10s\n", "Date", "Hour", "Count", "Size(MB)"
    PROCINFO["sorted_in"] = "@ind_str_asc"
    for (k in count) {
      split(k, parts, " ")
      printf "%-12s %-5s %-8d %-10.2f\n", parts[1], parts[2], count[k], size[k]/1024/1024
    }
  }'

