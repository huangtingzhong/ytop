#!/bin/bash

ARCHIVE_DIR="$1"
WAL_FILE_NAME="$2"
WAL_FILE_PATH="$3"

ARCHIVE_FILE_PATH="${ARCHIVE_DIR}/${WAL_FILE_NAME}"

# 检查归档文件是否已存在
if [ -f "$ARCHIVE_FILE_PATH" ]; then
  # 比对 MD5 值
  SRC_MD5=$(md5sum "$WAL_FILE_PATH" | awk '{print $1}')
  DST_MD5=$(md5sum "$ARCHIVE_FILE_PATH" | awk '{print $1}')

  if [ "$SRC_MD5" = "$DST_MD5" ]; then
    echo "WAL file $WAL_FILE_NAME already archived with matching MD5. Skipping."
    exit 0
  else
    echo "WAL file $WAL_FILE_NAME exists but MD5 mismatch. Replacing."
    cp -f "$WAL_FILE_PATH" "$ARCHIVE_FILE_PATH"
    exit $?
  fi
else
  echo "WAL file $WAL_FILE_NAME not archived yet. Archiving now."
  cp "$WAL_FILE_PATH" "$ARCHIVE_FILE_PATH"
  exit $?
fi
