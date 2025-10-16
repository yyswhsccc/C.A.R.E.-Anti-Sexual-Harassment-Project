#!/usr/bin/env bash
set -euo pipefail
OK=()
BAD=()

check_py() {
  local f="$1"
  if python3 -m py_compile "$f" 2>/tmp/ci.err; then
    OK+=("[PY OK] $f")
  else
    BAD+=("[PY ERR] $f -> $(tr -d "\n" </tmp/ci.err)")
  fi
}

check_sh() {
  local f="$1"
  if bash -n "$f" 2>/tmp/ci.err; then
    OK+=("[SH OK] $f")
  else
    BAD+=("[SH ERR] $f -> $(tr -d "\n" </tmp/ci.err)")
  fi
}

# 你的候选清单（来自 migrate 脚本）
FILES=(
/etc/cron.d/disk_alert
/etc/systemd/system/daily_audit.service
/etc/default/daily_audit
/etc/default/moodle-guard
/home/ubuntu/run_mysqlcheck.sh
/home/ubuntu/mysqltuner_report.sh
/home/ubuntu/moodledata_snapshot_backup.sh
/home/ubuntu/restore_from_s3.sh
/home/ubuntu/moodle-backup-to-s3.sh
/home/ubuntu/moodle_server_health_reporter.py
/home/ubuntu/cleanup_old_backups.sh
/home/ubuntu/disk_alert.py
/home/ubuntu/auto_reboot_healthcheck.sh
/home/ubuntu/moodle_cron_monitor.py
/usr/local/sbin/perf_guard.sh
/home/ubuntu/ls-copy-auto-to-manual.sh
/home/ubuntu/moodle_monitor.py
/home/ubuntu/postboot_healthcheck.sh
/usr/local/sbin/sendmail_guard.py
/usr/local/sbin/daily_audit.sh
/usr/local/sbin/moodle_prepare_minor_update.sh
/usr/local/sbin/moodle_free_inodes.sh
/usr/local/sbin/perf_guard.sh
)

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { BAD+=("[MISS] $f"); continue; }
  # 简单判断类型：扩展名 .py -> Python；其它按 Shell 检查
  case "$f" in
    *.py) check_py "$f" ;;
    *)    check_sh "$f" ;;
  esac
done

echo "==== CHECK RESULT ===="
printf "%s\n" "${OK[@]}"
printf "%s\n" "${BAD[@]}" >&2
[[ ${#BAD[@]} -eq 0 ]] || exit 1
