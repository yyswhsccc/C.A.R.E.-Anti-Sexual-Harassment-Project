#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/moodle; mkdir -p "$LOGDIR"
LOG=$LOGDIR/panic_guard.log; touch "$LOG"; chown www-data:www-data "$LOG" || true
STATEDIR=/var/lib/moodle-guard; mkdir -p "$STATEDIR"
STATE=$STATEDIR/panic.state
COOLDOWN=$STATEDIR/panic.cooldown
log(){ printf "[%s] %s\n" "$(date -Is)" "$*" | tee -a "$LOG"; }
check_web(){ curl -sSf --max-time 5 http://127.0.0.1/ >/dev/null 2>&1; }
check_dns(){ getent hosts s3.ca-central-1.amazonaws.com >/dev/null 2>&1; }

WINDOW=600      # 10 分钟窗口
NEEDED=3        # 连续失败阈值
COOL=21600      # 6 小时冷却（秒）

count=0; last=0
[[ -f "$STATE" ]] && read count last < "$STATE" || true
now=$(date +%s)
(( now - last > WINDOW )) && count=0

if check_web && check_dns; then
  echo "0 $now" > "$STATE"
  log "OK: web & DNS good"
  exit 0
fi

count=$((count+1)); echo "$count $now" > "$STATE"
log "WARN: probe failed (count=$count)"

# 尝试已存在的自愈
/usr/local/sbin/web_guard.sh || true
/usr/local/sbin/net_guard.sh || true
sleep 5
if check_web && check_dns; then
  echo "0 $(date +%s)" > "$STATE"
  log "RECOVERED: after guards"
  exit 0
fi

# 冷却期内不重启
if [[ -f "$COOLDOWN" ]] && (( now - $(cat "$COOLDOWN") < COOL )); then
  log "Cooldown active; skip reboot"
  exit 1
fi

if (( count >= NEEDED )); then
  log "PANIC: $NEEDED consecutive failures -> rebooting"
  date +%s > "$COOLDOWN"
  /sbin/reboot
fi
