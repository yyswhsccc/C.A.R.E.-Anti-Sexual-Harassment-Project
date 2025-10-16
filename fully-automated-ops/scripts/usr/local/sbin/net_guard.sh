#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/moodle; mkdir -p "$LOGDIR"
LOG=$LOGDIR/net_guard.log; touch "$LOG"; chown www-data:www-data "$LOG" || true
log(){ printf "[%s] %s\n" "$(date -Is)" "$*" | tee -a "$LOG"; }

check_ok(){
  getent hosts s3.ca-central-1.amazonaws.com >/dev/null 2>&1 || return 1
  curl -sSf --max-time 5 https://s3.ca-central-1.amazonaws.com/ >/dev/null 2>&1 || return 1
  # 顺带自检本机 Web（帮助甩锅：服务正常 vs. 外网抖动）
  curl -sSf --max-time 5 http://127.0.0.1/ >/dev/null 2>&1 || return 1
  return 0
}

log "net_guard tick: probing DNS & outbound connectivity"
if check_ok; then
  log "✅ OK: DNS & outbound reachable; local web responds"
  exit 0
fi

log "⚠️ fail -> restart systemd-resolved"
systemctl restart systemd-resolved || true
resolvectl flush-caches || true
sleep 3

if check_ok; then
  log "✅ recovered after resolved restart"
  exit 0
fi

log "⚠️ still failing -> ensure FallbackDNS and restart"
CONF=/etc/systemd/resolved.conf
grep -q "^\[Resolve\]" "$CONF" || echo "[Resolve]" >> "$CONF"
sed -i -E "/^\[Resolve\]/,/^\[/{s/^FallbackDNS=.*/FallbackDNS=1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4/}" "$CONF"
grep -q "^FallbackDNS=" "$CONF" || echo "FallbackDNS=1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4" >> "$CONF"
systemctl restart systemd-resolved || true
sleep 3

if check_ok; then
  log "✅ recovered after FallbackDNS"
  exit 0
fi

log "❌ still failing after DNS repairs (manual check needed)"
exit 1
