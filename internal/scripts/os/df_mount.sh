#!/usr/bin/env bash
# File Name: df_mount.sh
# Purpose: Filesystem and inode capacity snapshot for DB host troubleshooting
# Created: 20260616  by  huangtingzhong
#
# Usage: df_mount.sh
# Value: OS disk full / arch or data on wrong mount / inode exhaustion (§5.3.7)

set -euo pipefail

echo "=== SNAP $(date '+%F %T') ==="
echo "=== DF capacity (POSIX -h -P -T) ==="
if df -hPT 2>/dev/null; then
  :
else
  df -hP
fi

echo ""
echo "=== DF inode (POSIX -h -P -T) ==="
if df -hiPT 2>/dev/null; then
  :
else
  df -hiP
fi

echo ""
echo "=== Mounts (yashan|data|arch|redo|undo|temp|xfs|ext4) ==="
if mount 2>/dev/null | grep -iE 'yashan|/data/|arch|redo|undo|temp|xfs|ext4' | head -40; then
  :
else
  mount 2>/dev/null | head -25
fi

echo ""
echo "=== Full >= 90% (capacity or inode) ==="
df -hP 2>/dev/null | awk 'NR==1 || ($5+0 >= 90 && $5 ~ /%/) {print}'
df -hiP 2>/dev/null | awk 'NR==1 || ($5+0 >= 90 && $5 ~ /%/) {print}'
