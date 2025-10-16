#!/usr/bin/env bash
# >>> load /etc/moodle-notify.env >>>
[ -f /etc/moodle-notify.env ] && set -a && . /etc/moodle-notify.env && set +a
: "${EMAIL_SENDER:?set in /etc/moodle-notify.env}"
: "${EMAIL_PASSWORD:?set in /etc/moodle-notify.env}"
: "${SMTP_SERVER:=smtp.example.com}"
: "${SMTP_PORT:=587}"
# <<< load /etc/moodle-notify.env <<<
set -Euo pipefail

# --- 邮件与环境 ---
: "${EMAIL_FROM_NAME:?}"; : "${EMAIL_FROM:?}"; : "${EMAIL_PASS:?}"
: "${SMTP_HOST:?}"; : "${SMTP_PORT:?}"; : "${RECIPIENTS_CSV:?}"
REGION="${REGION:-ca-central-1}"
FUNC="${FUNC:-ls-autoheal-CouragetoactMoodleVersion2}"

LOGDIR="/var/log/moodle"
LOGFILE="$LOGDIR/daily_audit.log"
REPORT="$(mktemp)"; trap 'rm -f "$REPORT"' EXIT
append(){ printf "%s\n" "$1" >>"$REPORT"; }
ts(){ date +"%Y-%m-%d %H:%M:%S %Z"; }

append "==== Daily Audit @ $(ts) ===="

# [A] journald
append "\n==== [A] journald 限额 & 占用 ===="
if [ -d /etc/systemd/journald.conf.d ]; then
  grep -HnE '^(SystemMaxUse|MaxRetentionSec)=' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/* 2>/dev/null \
    | sed 's/^/  /' >>"$REPORT" || true
fi
journalctl --disk-usage 2>&1 | sed 's/^/  /' >>"$REPORT" || true
du -sh /var/log/journal 2>/dev/null | sed 's/^/  /' >>"$REPORT" || true

# [B] Moodle cron
append "\n==== [B] Moodle cron 日志轮转 ===="
[ -f /etc/logrotate.d/moodle-cron ] && { echo "-- /etc/logrotate.d/moodle-cron --" >>"$REPORT"; sed 's/^/  /' /etc/logrotate.d/moodle-cron >>"$REPORT"; }
append "\n-- 最近轮转状态 --"
grep -E '(/home/ubuntu/moodledata/cron\.log|/var/log/moodle/cron\.log)' /var/lib/logrotate/status 2>/dev/null \
  | sed 's/^/  /' >>"$REPORT" || true
append "\n-- 当前日志文件 --"
ls -lh /home/ubuntu/moodledata/cron.log 2>/dev/null | sed 's/^/  /' >>"$REPORT" || append "  (not found)"

# [C] mysqltuner 清理
append "\n==== [C] mysqltuner 日志清理（>1天应无） ===="
find /home/ubuntu -maxdepth 1 -type f -name "mysqltuner_*.log" -printf "  %TY-%Tm-%Td %TH:%TM %p\n" 2>/dev/null \
  | sort >>"$REPORT" || true

# [D] MySQL binlog
append "\n==== [D] MySQL binlog ===="
mysql -NBe "SHOW VARIABLES LIKE 'binlog_expire_logs_seconds';" 2>/dev/null | awk '{print "  "$1": "$2}' >>"$REPORT" \
  || append "  (mysql unavailable)"
append "\n-- 当前 binlog 文件 --"
if compgen -G '/var/log/mysql/mysql-bin.00*' >/dev/null; then
  ls -l --time-style=long-iso /var/log/mysql/mysql-bin.00* 2>/dev/null | sed 's/^/  /' >>"$REPORT" || true
else
  append "  (no binlog files)"
fi

# [E] ClamAV & Moodle 片段
append "\n==== [E] ClamAV 守护状态 ===="
systemctl is-enabled clamav-daemon 2>/dev/null | sed 's/^/  enabled: /' >>"$REPORT" || true
systemctl is-active  clamav-daemon 2>/dev/null | sed 's/^/  active:  /'  >>"$REPORT" || true
pgrep -a clamd >/dev/null 2>&1 && append "  WARN: clamd running" || append "  OK: no clamd process"
append "\n-- Moodle clamav 片段 (config.php) --"
{ nl -ba /var/www/html/moodle/config.php 2>/dev/null | sed -n '1,200p' \
  | grep -n "forced_plugin_settings.*clamav" -n -A2 -B1 || true; } \
  | sed 's/^/  /' >>"$REPORT"

# [F] timers
append "\n==== [F] 自愈 timers（net/web/panic_guard） ===="
for t in net_guard.timer web_guard.timer panic_guard.timer; do
  echo "== $t ==" >>"$REPORT"
  systemctl show -p NextElapseUSecRealtime -p LastTriggerUSec "$t" 2>/dev/null | sed 's/^/  /' >>"$REPORT" || true
done
append "\n-- 守护日志尾部 --"
for f in /var/log/moodle/net_guard.log /var/log/moodle/web_guard.log /var/log/moodle/panic_guard.log; do
  [ -f "$f" ] && { echo "== tail $f ==" >>"$REPORT"; tail -n 12 "$f" | sed 's/^/  /' >>"$REPORT"; }
done

# [G] Lambda 近24h
append "\n==== [G] AWS Auto-Heal（Lambda）近24h ===="
if command -v aws >/dev/null 2>&1; then
  START="$(date -u -d '24 hours ago' +%FT%TZ 2>/dev/null || date -u -v-24H +%FT%TZ)"
  END="$(date -u +%FT%TZ)"
  INV=$(aws cloudwatch get-metric-statistics --region "$REGION" --namespace AWS/Lambda --metric-name Invocations \
        --dimensions Name=FunctionName,Value="$FUNC" --start-time "$START" --end-time "$END" \
        --statistics Sum --period 3600 --output text 2>/dev/null | awk 'NF==2{sum+=$2} END{print sum+0}')
  ERR=$(aws cloudwatch get-metric-statistics --region "$REGION" --namespace AWS/Lambda --metric-name Errors \
        --dimensions Name=FunctionName,Value="$FUNC" --start-time "$START" --end-time "$END" \
        --statistics Sum --period 3600 --output text 2>/dev/null | awk 'NF==2{sum+=$2} END{print sum+0}')
  echo "  Invocations(24h): ${INV:-N/A}" >>"$REPORT"
  echo "  Errors(24h):      ${ERR:-N/A}" >>"$REPORT"
else
  append "  aws cli not found"
fi

# 写日志
{
  echo
  echo "====== $(ts) ======"
  cat "$REPORT"
} >>"$LOGFILE"

# 发邮件
export REPORT EMAIL_FROM_NAME EMAIL_FROM EMAIL_PASS SMTP_HOST SMTP_PORT
export RECIPIENTS="$RECIPIENTS_CSV"
python3 - <<'PY'
import os, smtplib, ssl
from email.mime.text import MIMEText
from email.header import Header
from email.utils import formataddr
from pathlib import Path
from datetime import datetime

frm_name=os.environ['EMAIL_FROM_NAME']
frm=os.environ['EMAIL_FROM']
pwd=os.environ['EMAIL_PASS']
smtp=os.environ['SMTP_HOST']; port=int(os.environ['SMTP_PORT'])
rcpts=[x.strip() for x in os.environ['RECIPIENTS'].split(',') if x.strip()]
body=Path(os.environ['REPORT']).read_text(encoding='utf-8')

sub=f"[Moodle] Daily audit {datetime.now().strftime('%Y-%m-%d %H:%M')}"
msg=MIMEText(body, _subtype='plain', _charset='utf-8')
msg['Subject']=Header(sub,'utf-8')
msg['From']=formataddr((str(Header(frm_name,'utf-8')), frm))
msg['To']=', '.join(rcpts)

ctx=ssl.create_default_context()
with smtplib.SMTP(smtp, port, timeout=20) as s:
    s.starttls(context=ctx)
    s.login(frm, pwd)
    s.sendmail(frm, rcpts, msg.as_string())
print("sent ok")
PY
