#!/usr/bin/env bash
# >>> load /etc/moodle-notify.env >>>
[ -f /etc/moodle-notify.env ] && set -a && . /etc/moodle-notify.env && set +a
: "${EMAIL_SENDER:?set in /etc/moodle-notify.env}"
: "${EMAIL_PASSWORD:?set in /etc/moodle-notify.env}"
: "${SMTP_SERVER:=smtp.example.com}"
: "${SMTP_PORT:=587}"
# <<< load /etc/moodle-notify.env <<<
set -euo pipefail

# ===== 配置 =====
DRYRUN="${DRYRUN:-0}"                    # 0=实删，1=只预览
APT_CLEAN="${APT_CLEAN:-1}"
JOURNAL_VACUUM_DAYS="${JOURNAL_VACUUM_DAYS:-14}"
LOG_GZ_RETENTION_DAYS="${LOG_GZ_RETENTION_DAYS:-30}"
TMP_RETENTION_DAYS="${TMP_RETENTION_DAYS:-7}"
CLEAN_SNAP_OLD="${CLEAN_SNAP_OLD:-0}"

MOODLE_DIR="${MOODLE_DIR:-/var/www/html/moodle}"

# 邮件（沿用你之前的发信配置）
# MOVED_TO_ENV: EMAIL_SENDER=...
# MOVED_TO_ENV: EMAIL_PASSWORD=...
# MOVED_TO_ENV: EMAIL_TO=...
EMAIL_SUBJECT_PREFIX="[Moodle inode cleanup]"
export EMAIL_SENDER EMAIL_PASSWORD EMAIL_TO EMAIL_SUBJECT_PREFIX

# ===== 报告文件 =====
REPORT_FILE="$(mktemp -p /tmp inode-cleanup.XXXXXX.txt)"
export REPORT_FILE
say(){ printf '\n==> %s\n' "$*" | tee -a "$REPORT_FILE" ; }
log(){ echo "$*" | tee -a "$REPORT_FILE" ; }

# ===== 工具函数 =====
do_find_rm() {
  local title="$1"; shift
  local cmd=(find "$@")
  say "$title"
  if [[ "$DRYRUN" == "1" ]]; then
    log "[DRYRUN] 将匹配以下文件(最多展示 50 条)："
    "${cmd[@]}" -print | head -n 50 | tee -a "$REPORT_FILE" || true
    local count=$("${cmd[@]}" -print | wc -l || true)
    log "[DRYRUN] 总计匹配: ${count} 个"
  else
    log "[DELETE] 正在删除..."
    "${cmd[@]}" -print -delete | tee -a "$REPORT_FILE" || true
  fi
}

# ===== 读 dataroot（修复 CLI_SCRIPT 报错）=====
DATAROOT=""
if [[ -d "$MOODLE_DIR" && -f "$MOODLE_DIR/config.php" ]] && command -v php >/dev/null 2>&1; then
  DATAROOT="$(php -r "define('CLI_SCRIPT', true); require '$MOODLE_DIR/config.php'; echo isset(\$CFG->dataroot)?\$CFG->dataroot:'';")" || true
fi
if [[ -z "${DATAROOT:-}" ]]; then
  for p in ${DATAROOT:-/var/moodledata} /mnt/moodledata; do [[ -d "$p" ]] && DATAROOT="$p" && break; done
fi
say "检测到 Moodle dataroot: ${DATAROOT:-未找到}（找不到就跳过与 Moodle 相关的清理）"

# ===== 1) Moodle 安全清理 =====
if [[ -n "${DATAROOT:-}" ]]; then
  if [[ -f "$MOODLE_DIR/admin/cli/purge_caches.php" ]]; then
    say "Moodle: purge_caches.php（清缓存，不删用户数据）"
    if [[ "$DRYRUN" == "1" ]]; then
      log "[DRYRUN] sudo -u www-data php $MOODLE_DIR/admin/cli/purge_caches.php"
    else
      sudo -u www-data php "$MOODLE_DIR/admin/cli/purge_caches.php" | tee -a "$REPORT_FILE" || true
    fi
  fi

  # 关键修复：cron.php 限时 10s & 静默输出，避免长时间“继续检查任务…”
  if [[ -f "$MOODLE_DIR/admin/cli/cron.php" ]]; then
    say "Moodle: cron.php（限时 10s，静默输出）"
    if [[ "$DRYRUN" == "1" ]]; then
      log "[DRYRUN] timeout 10s sudo -u www-data php $MOODLE_DIR/admin/cli/cron.php >/dev/null 2>&1 || true"
    else
      timeout 10s sudo -u www-data php "$MOODLE_DIR/admin/cli/cron.php" >/dev/null 2>&1 || true
      log "[INFO] cron.php 已运行（10s 限时，已静默）。"
    fi
  fi

  # 精准清理“海量小文件”的热点目录（不碰 filedir）
  [[ -d "$DATAROOT/localcache" ]] && do_find_rm "清理 localcache（>1天）" "$DATAROOT/localcache" -xdev -type f -mtime +1
  [[ -d "$DATAROOT/temp"       ]] && do_find_rm "清理 temp（>2天）"       "$DATAROOT/temp"       -xdev -type f -mtime +2
  [[ -d "$DATAROOT/trashdir"   ]] && do_find_rm "清理 trashdir（>7天）"   "$DATAROOT/trashdir"   -xdev -type f -mtime +7
  [[ -d "$DATAROOT/cache"      ]] && do_find_rm "清理 cache（>7天）"      "$DATAROOT/cache"      -xdev -type f -mtime +7
fi

# ===== 2) 系统层面 =====
[[ -d /tmp ]] && do_find_rm "/tmp 老文件（>${TMP_RETENTION_DAYS}天）" /tmp -xdev -type f -mtime +"$TMP_RETENTION_DAYS"
[[ -d /var/log ]] && do_find_rm "/var/log 旧压缩日志（>${LOG_GZ_RETENTION_DAYS}天）" /var/log -xdev -type f -name '*.gz' -mtime +"$LOG_GZ_RETENTION_DAYS"

if [[ "$APT_CLEAN" == "1" ]]; then
  say "apt 缓存清理（/var/cache/apt/archives）"
  if [[ "$DRYRUN" == "1" ]]; then
    du -sh /var/cache/apt/archives 2>/dev/null | tee -a "$REPORT_FILE" || true
    log "[DRYRUN] sudo apt-get clean"
  else
    sudo apt-get clean -y >/dev/null 2>&1 || true
    du -sh /var/cache/apt/archives 2>/dev/null | tee -a "$REPORT_FILE" || true
  fi
fi

if command -v journalctl >/dev/null 2>&1; then
  say "systemd 日志清理（保留 ${JOURNAL_VACUUM_DAYS} 天内）"
  if [[ "$DRYRUN" == "1" ]]; then
    journalctl --disk-usage | tee -a "$REPORT_FILE" || true
    log "[DRYRUN] sudo journalctl --vacuum-time=${JOURNAL_VACUUM_DAYS}d"
  else
    journalctl --disk-usage | tee -a "$REPORT_FILE" || true
    sudo journalctl --vacuum-time="${JOURNAL_VACUUM_DAYS}d" | tee -a "$REPORT_FILE" || true
    journalctl --disk-usage | tee -a "$REPORT_FILE" || true
  fi
fi

if [[ "$CLEAN_SNAP_OLD" == "1" && -x /usr/bin/snap ]]; then
  say "清理旧 snap 版本（disabled 修订版）"
  if [[ "$DRYRUN" == "1" ]]; then
    log "[DRYRUN] snap list --all | awk '/disabled/{print \$1, \$3}' | while read n r; do snap remove \$n --revision=\$r; done"
  else
    sudo bash -lc 'snap list --all | awk "/disabled/{print \$1, \$3}" | while read n r; do snap remove "$n" --revision="$r" || true; done' | tee -a "$REPORT_FILE" || true
  fi
fi

# ===== 3) 清理后摘要 =====
say "清理后磁盘/inode 摘要"
{
  echo "[df -h /]"; df -h /;
  echo; echo "[df -i /]"; df -i /;
  echo; echo "[/var 三个关键目录]"; du -sh ${DATAROOT:-/var/moodledata} 2>/dev/null || true; du -sh /var/lib/mysql 2>/dev/null || true; du -sh /var/log 2>/dev/null || true;
} | tee -a "$REPORT_FILE"

# ===== 4) 发送邮件（修复 f-string 反斜杠问题）=====
python3 - <<'PYMAIL'
import smtplib, os
from datetime import datetime
from email.mime.text import MIMEText
from email.utils import formataddr

sender = os.environ["EMAIL_SENDER"]
password = os.environ.get("EMAIL_PASSWORD","REPLACE_ME")
to = os.environ["EMAIL_TO"]
subject_prefix = os.environ.get("EMAIL_SUBJECT_PREFIX","[inode cleanup]")
report_file = os.environ["REPORT_FILE"]

with open(report_file,'r',encoding='utf-8',errors='ignore') as f:
    body = f.read()

now = datetime.now().strftime('%F %T')  # 用 Python 生成时间戳，避免反斜杠
msg = MIMEText(body, 'plain', 'utf-8')
msg['From'] = formataddr(("Moodle Inode Cleaner", sender))
msg['To'] = to
msg['Subject'] = f"{subject_prefix} {now}"

smtp = smtplib.SMTP("smtp.example.com", 587, timeout=20)
smtp.starttls()
smtp.login(sender, password)
smtp.sendmail(sender, [to], msg.as_string())
smtp.quit()
PYMAIL

echo "报告已发送到 ${EMAIL_TO}，报告文件：${REPORT_FILE}"
