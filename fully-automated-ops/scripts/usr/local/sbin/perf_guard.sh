#!/usr/bin/env bash
# >>> load /etc/moodle-notify.env >>>
[ -f /etc/moodle-notify.env ] && set -a && . /etc/moodle-notify.env && set +a
: "${EMAIL_SENDER:?set in /etc/moodle-notify.env}"
: "${EMAIL_PASSWORD:?set in /etc/moodle-notify.env}"
: "${SMTP_SERVER:=smtp.example.com}"
: "${SMTP_PORT:=587}"
# <<< load /etc/moodle-notify.env <<<
set -euo pipefail

LOGDIR=/var/log/moodle
STATEDIR=/var/lib/moodle-guard
mkdir -p "$LOGDIR" "$STATEDIR"
LOG="$LOGDIR/perf_guard.log"
touch "$LOG" && chown www-data:www-data "$LOG" || true

BASE_URL=http://127.0.0.1/moodle/login/index.php
AB_BIN="$(command -v ab || true)"
. /etc/default/moodle-guard 2>/dev/null || true

THRESHOLD=0.70
N=2000
C=10
AB_TIMEOUT=30

BASELINE="$STATEDIR/baseline_rps.txt"
AB_LAST="$STATEDIR/ab_last.txt"

log(){ printf "[%s] %s\n" "$(date -Is)" "$*" | tee -a "$LOG"; }

ab_run(){
  if [ -z "$AB_BIN" ]; then echo "0 999"; return; fi
  "$AB_BIN" -n "$N" -c "$C" -s "$AB_TIMEOUT" -l -H "Cache-Control: no-cache" -H "Pragma: no-cache" -H "Connection: close" "$BASE_URL" > "$AB_LAST" 2>&1 || true
  rps=$(awk '/Requests per second:/{print $4}' "$AB_LAST")
  failed=$(awk '/Failed requests:/{print $3}' "$AB_LAST")
  [ -z "$rps" ] && rps=0
  [ -z "$failed" ] && failed=999
  echo "$rps $failed"
}

heal_once(){
  # 避免偶发 NAMESPACE 报错
  mkdir -p /var/tmp && chmod 1777 /var/tmp || true
  [ -x /usr/local/sbin/web_guard.sh ] && /usr/local/sbin/web_guard.sh || true
  [ -x /usr/local/sbin/net_guard.sh ] && /usr/local/sbin/net_guard.sh || true
  systemctl restart apache2 || true
}

[ -s "$BASELINE" ] || echo "1" > "$BASELINE"
BASE_RPS=$(awk '{print $1+0}' "$BASELINE")

log "perf_guard tick: N=$N C=$C baseline=${BASE_RPS}rps"

# 0) 轻量预热，减少冷启动抖动
curl -sS --max-time 3 "$BASE_URL" >/dev/null || true

# 1) 第一次测
set -- $(ab_run); PRE_RPS="$1"; PRE_FAILED="$2"
log "sample#1: rps=${PRE_RPS} failed=${PRE_FAILED}"
PRE_OK=$(awk -v r="$PRE_RPS" -v b="$BASE_RPS" -v t="$THRESHOLD" 'BEGIN{print (r>=b*t)?"OK":"BAD"}')

STATUS=OK
ACTIONS=none
RPS="$PRE_RPS"; FAILED="$PRE_FAILED"

if [ "$PRE_FAILED" -eq 0 ] && [ "$PRE_OK" = "OK" ]; then
  better=$(awk -v r="$PRE_RPS" -v b="$BASE_RPS" 'BEGIN{print (r>b*1.2)?"YES":"NO"}')
  [ "$better" = "YES" ] && echo "$PRE_RPS" > "$BASELINE" && log "baseline updated -> $PRE_RPS"
else
  # 2) 二次确认
  sleep 2
  set -- $(ab_run); SEC_RPS="$1"; SEC_FAILED="$2"
  log "sample#2: rps=${SEC_RPS} failed=${SEC_FAILED}"
  SEC_OK=$(awk -v r="$SEC_RPS" -v b="$BASE_RPS" -v t="$THRESHOLD" 'BEGIN{print (r>=b*t)?"OK":"BAD"}')

  if [ "$SEC_FAILED" -eq 0 ] && [ "$SEC_OK" = "OK" ]; then
    STATUS=OK
    ACTIONS="no heal (second sample OK)"
    RPS="$SEC_RPS"; FAILED="$SEC_FAILED"
  else
    # 3) 仍不达标 -> heal
    STATUS=DEGRADED
    ACTIONS="attempt heal once"
    heal_once
    sleep 3
    set -- $(ab_run); POST_RPS="$1"; POST_FAILED="$2"
    log "after heal: rps=${POST_RPS} failed=${POST_FAILED}"
    POST_OK=$(awk -v r="$POST_RPS" -v b="$BASE_RPS" -v t="$THRESHOLD" 'BEGIN{print (r>=b*t)?"OK":"BAD"}')
    RPS="$POST_RPS"; FAILED="$POST_FAILED"
    if [ "$POST_FAILED" -eq 0 ] && [ "$POST_OK" = "OK" ]; then
      STATUS=RECOVERED
      ACTIONS="healed via web_guard/net_guard/apache restart"
    fi
  fi
fi

# 邮件
BODY="$STATEDIR/perf_mail.txt"
{
  echo "Moodle Performance Daily Report"
  echo
  echo "Date: $(date -Is)"
  echo "Host: $(hostname)"
  echo "Status: $STATUS"
  echo
  echo "Summary:"
  echo "  - Baseline RPS: $BASE_RPS"
  echo "  - Measured RPS: $RPS"
  echo "  - Failed Requests: $FAILED"
  echo "  - Actions Taken: $ACTIONS"
  echo
  echo "Details:"
  echo "  - ab: N=$N, C=$C, threshold=$THRESHOLD, timeout=$AB_TIMEOUT"
  echo "  - sample#1: rps=$PRE_RPS failed=$PRE_FAILED"
  [ -n "${SEC_RPS:-}" ] && echo "  - sample#2: rps=$SEC_RPS failed=$SEC_FAILED"
  [ -n "${POST_RPS:-}" ] && echo "  - after heal: rps=$POST_RPS failed=$POST_FAILED"
  echo
  echo "--- Last ab output tail ---"
  tail -n 12 "$AB_LAST" 2>/dev/null || echo "N/A"
  echo
  echo "--- net_guard tail ---"
  tail -n 5 /var/log/moodle/net_guard.log 2>/dev/null || echo "N/A"
  echo
  echo "--- web_guard tail ---"
  tail -n 5 /var/log/moodle/web_guard.log 2>/dev/null || echo "N/A"
  echo
  echo "End of report."
} > "$BODY"

SUBJ_DATE="$(date +%F_%T_%Z)"
env -i \
  SMTP_HOST="${SMTP_HOST:-smtp.example.com}" \
  SMTP_PORT="${SMTP_PORT:-587}" \
  EMAIL_FROM="${EMAIL_FROM:-}" \
# MOVED_TO_ENV:   EMAIL_PASS=...
  EMAIL_FROM_NAME="${EMAIL_FROM_NAME:-Moodle Notifier}" \
  RECIPIENTS="${RECIPIENTS:-}" \
  MAIL_SUBJECT="Moodle Perf Report [$STATUS] $SUBJ_DATE" \
  /usr/local/sbin/sendmail_guard.py < "$BODY" 2>>"$LOG" || true

log "done: status=$STATUS rps=$RPS base=$BASE_RPS failed=$FAILED"
