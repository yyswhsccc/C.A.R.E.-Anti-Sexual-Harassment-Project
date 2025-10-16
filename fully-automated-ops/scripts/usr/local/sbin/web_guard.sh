#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/moodle; mkdir -p "$LOGDIR"
LOG=$LOGDIR/web_guard.log; touch "$LOG"; chown www-data:www-data "$LOG" || true
log(){ printf "[%s] %s\n" "$(date -Is)" "$*" | tee -a "$LOG"; }
ok(){ curl -fsS --max-time 5 http://127.0.0.1/ >/dev/null; }

log "web_guard tick: probe localhost:80"
if ok; then
  log "✅ local web OK"
  exit 0
fi

log "⚠️ local web FAIL -> restart apache/php + resolved"
systemctl restart apache2 || true
systemctl restart "php*-fpm" 2>/dev/null || true
systemctl restart systemd-resolved || true
sleep 3

if ok; then
  log "✅ recovered after restarts"
  exit 0
fi

log "❌ still failing after restarts (manual check needed)"
exit 1
