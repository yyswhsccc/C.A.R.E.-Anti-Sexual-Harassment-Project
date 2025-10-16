#!/usr/bin/env bash
set -euo pipefail
LOG="/home/ubuntu/cleanup_txt.cron.log"
TS(){ date -u +%F_%T; }

echo "$(TS) start" >> "$LOG"
# 仅删除 7 天前的备份/清理/报告类 .txt
find /home/ubuntu -maxdepth 1 -type f -regextype posix-extended \
  -regex '/home/ubuntu/(backup_.*|cleanup_.*|.*_report_.*|mysqlcheck.*)\.txt' \
  -mtime +7 -print -delete >> "$LOG" 2>&1 || true
echo "$(TS) done" >> "$LOG"
