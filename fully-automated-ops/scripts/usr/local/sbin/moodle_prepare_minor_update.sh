#!/usr/bin/env bash
# >>> load /etc/moodle-notify.env >>>
[ -f /etc/moodle-notify.env ] && set -a && . /etc/moodle-notify.env && set +a
: "${EMAIL_SENDER:?set in /etc/moodle-notify.env}"
: "${EMAIL_PASSWORD:?set in /etc/moodle-notify.env}"
: "${SMTP_SERVER:=smtp.example.com}"
: "${SMTP_PORT:=587}"
# <<< load /etc/moodle-notify.env <<<
set -euo pipefail

MOODLEDIR="/var/www/html/moodle"
LOG="/home/ubuntu/moodle_prepare_minor_update.log"
SECRETS="/root/.moodle_notify.conf"
RUN_ID="$(date -u +%F_%H%M%S)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# 指纹缓存目录（按分支）
CACHE_DIR="/root/moodle-update-cache"
mkdir -p "$CACHE_DIR"

timestamp(){ date -u +%F_%T; }
log(){ echo "$(timestamp) $*" | tee -a "$LOG"; }

# ---------- 自清理：准备包 >7 天；备份包 >30 天 ----------
housekeep() {
  log "Housekeeping: purge old staging/backup"
  find /root -maxdepth 1 -type d -name 'moodle-prep-*'        -mtime +7  -print -exec rm -rf {} + 2>/dev/null || true
  find /root -maxdepth 1 -type f -name 'moodle-backup-*.tgz'  -mtime +30 -print -delete           2>/dev/null || true
}
housekeep

log "==== prepare start RUN_ID=${RUN_ID} ===="

# ---------- 读取当前分支 ----------
[ -f "$MOODLEDIR/version.php" ] || { log "ERROR: $MOODLEDIR/version.php not found"; exit 1; }
BRANCH="$(php -r 'include $argv[1]; echo isset($branch)?$branch:"";' "$MOODLEDIR/version.php" || true)"
RELEASE="$(php -r 'include $argv[1]; echo isset($release)?$release:"";' "$MOODLEDIR/version.php" || true)"
[ -n "$BRANCH" ] || BRANCH="$(awk -F"'" '/^\$branch/ {print $2}' "$MOODLEDIR/version.php" || true)"
[ -n "$BRANCH" ] || { log "ERROR: cannot read \$branch from $MOODLEDIR/version.php"; exit 1; }
log "Detected branch=$BRANCH release=${RELEASE:-unknown}"

STATE_FILE="$CACHE_DIR/branch-${BRANCH}.state"

# ---------- 目标 URL ----------
PKG_URL_TGZ="https://download.moodle.org/download.php/direct/stable${BRANCH}/moodle-latest-${BRANCH}.tgz"
PKG_URL_ZIP="https://download.moodle.org/download.php/direct/stable${BRANCH}/moodle-latest-${BRANCH}.zip"
GH_URL_ZIP="https://github.com/moodle/moodle/archive/refs/heads/MOODLE_${BRANCH}_STABLE.zip"

# ---------- 计算远端“头指纹”（只用 HEAD，不下载体积） ----------
finger_from_url() {
  local url="$1"
  local hdr; hdr="$(curl -fsIL --retry 2 "$url" || true)"
  [ -n "$hdr" ] || return 1
  printf "%s\n" "$hdr" | grep -iE '^(etag:|last-modified:|content-length:)' | sha256sum | awk '{print $1}'
}

FINGER="" ; FINGER_SRC=""
if FINGER="$(finger_from_url "$PKG_URL_TGZ")"; then
  FINGER_SRC="$PKG_URL_TGZ"
elif FINGER="$(finger_from_url "$PKG_URL_ZIP")"; then
  FINGER_SRC="$PKG_URL_ZIP"
elif FINGER="$(finger_from_url "$GH_URL_ZIP")"; then
  FINGER_SRC="$GH_URL_ZIP"
fi

OLD_HEAD=""; OLD_PKGSHA=""; OLD_TS=""
if [ -f "$STATE_FILE" ]; then
  # 格式：HEAD PKGSHA TYPE TIMESTAMP
  read -r OLD_HEAD OLD_PKGSHA _ OLD_TS < "$STATE_FILE" || true
fi

# ---------- 跳过逻辑（稳健版） ----------
# 1) 若远端 HEAD 指纹非空，且等于本地缓存的 HEAD，则跳过
if [ -n "${FINGER:-}" ] && [ -n "${OLD_HEAD:-}" ] && [ "$FINGER" = "$OLD_HEAD" ]; then
  log "No change detected by HEAD (unchanged). Skip download."
  exit 0
fi
# 2) 若拿不到 HEAD（FINGER 为空），且我们在 24 小时内刚下过包（用 PKGSHA + 时间判断），则跳过，避免反复下载
if [ -z "${FINGER:-}" ] && [ -n "${OLD_PKGSHA:-}" ] && [ -n "${OLD_TS:-}" ]; then
  NOW=$(date -u +%s); THEN=$(date -u -d "${OLD_TS}" +%s 2>/dev/null || echo 0)
  AGE=$(( NOW - THEN ))
  if [ "$AGE" -lt 86400 ]; then
    log "HEAD unavailable; last download ${AGE}s ago (<24h). Skip to avoid re-download."
    exit 0
  fi
fi

# ---------- 下载（tgz → zip → GitHub） ----------
PKG=""; PKG_TYPE=""
log "Try TGZ: $PKG_URL_TGZ"
if curl -fSL --retry 3 -o "$WORK/moodle.tgz" "$PKG_URL_TGZ" && tar -tzf "$WORK/moodle.tgz" >/dev/null 2>&1; then
  PKG="$WORK/moodle.tgz"; PKG_TYPE="tgz"
else
  log "TGZ failed, try ZIP: $PKG_URL_ZIP"
  if command -v unzip >/dev/null 2>&1 && curl -fSL --retry 3 -o "$WORK/moodle.zip" "$PKG_URL_ZIP" && unzip -t "$WORK/moodle.zip" >/dev/null 2>&1; then
    PKG="$WORK/moodle.zip"; PKG_TYPE="zip"
  else
    log "Official mirrors failed, try GitHub branch: $GH_URL_ZIP"
    if command -v unzip >/dev/null 2>&1 && curl -fSL --retry 3 -o "$WORK/gh.zip" "$GH_URL_ZIP" && unzip -t "$WORK/gh.zip" >/dev/null 2>&1; then
      PKG="$WORK/gh.zip"; PKG_TYPE="ghzip"
    else
      log "ERROR: failed to download a valid package (tgz/zip/github)."; exit 1
    fi
  fi
fi
log "Package ok ($PKG_TYPE)"

# ---------- 解包 ----------
SRC="$WORK/new"; mkdir -p "$SRC"
case "$PKG_TYPE" in
  tgz) tar -xzf "$PKG" -C "$SRC" ;;
  zip|ghzip) unzip -q "$PKG" -d "$SRC" ;;
esac

if [ -d "$SRC/moodle" ]; then
  SRC_DIR="$SRC/moodle"
else
  SRC_DIR="$(find "$SRC" -maxdepth 1 -type d -name 'moodle-*STABLE' | head -n1)"
  [ -n "$SRC_DIR" ] || { log "ERROR: unpacked folder not found"; exit 1; }
fi

# ---------- 生成 staging ----------
STAGE="/root/moodle-prep-${BRANCH}-${RUN_ID}"
mkdir -p "$STAGE/moodle"
rsync -a "$SRC_DIR"/ "$STAGE/moodle/"

# 保留关键文件
[ -f "$MOODLEDIR/config.php" ] && cp -a "$MOODLEDIR/config.php" "$STAGE/moodle/config.php"
[ -d "$MOODLEDIR/local" ] && rsync -a "$MOODLEDIR/local/" "$STAGE/moodle/local/"
[ -f "$MOODLEDIR/.htaccess" ] && cp -a "$MOODLEDIR/.htaccess" "$STAGE/moodle/.htaccess"

# 下载包实际内容指纹（解决“拿不到 HEAD 导致反复下载”）
PKGSHA="$(sha256sum "$PKG" | awk '{print $1}')"
# 状态文件：HEAD PKGSHA TYPE TIMESTAMP
echo "${FINGER:-nohead} ${PKGSHA} ${PKG_TYPE} $(date -u +%F_%T)" > "$STATE_FILE"

# 记录各包 SHA 以备查
( cd "$WORK" && for f in moodle.tgz moodle.zip gh.zip; do [ -f "$f" ] && sha256sum "$f"; done ) | tee -a "$LOG" >/dev/null || true

# ---------- README ----------
cat > "$STAGE/README_MOODLE_UPDATE.txt" <<TXT
Prepared by moodle_prepare_minor_update.sh (RUN_ID=${RUN_ID})
Branch: ${BRANCH}   Release: ${RELEASE:-unknown}
Staging: ${STAGE}
HEAD fingerprint: ${FINGER:-nohead}
Package SHA256: ${PKGSHA}

Deploy steps (maintenance window):
  1) sudo -u www-data php ${MOODLEDIR}/admin/cli/maintenance.php --enable
  2) sudo systemctl stop apache2
  3) sudo tar -C /var/www/html -czf /root/moodle-backup-\$(date +%F_%H%M%S).tgz moodle
  4) sudo rsync -a --delete ${STAGE}/moodle/ ${MOODLEDIR}/
  5) sudo chown -R www-data:www-data ${MOODLEDIR}
  6) sudo systemctl start apache2
  7) sudo -u www-data php ${MOODLEDIR}/admin/cli/upgrade.php --non-interactive
  8) sudo -u www-data php ${MOODLEDIR}/admin/cli/purge_caches.php || true
  9) sudo -u www-data php ${MOODLEDIR}/admin/cli/maintenance.php --disable
TXT

log "Prepared staging directory: $STAGE"

# ---------- 邮件正文（极简易懂版，含 Lightsail 步骤；英文给同事） ----------
SUBJECT="Moodle prep is ready – please install within 30 days (branch ${BRANCH})"
BODY=$(cat <<EOM
⚠️ Please install this Moodle *minor update* within **7 days** (security & bug fixes).
Nothing has been changed yet. The package is prepared on the server.

What’s ready:
• Branch: ${BRANCH}
• Release: ${RELEASE:-unknown}
• Staging folder: ${STAGE}
• Package SHA256: ${PKGSHA}

How to install (COPY & PASTE **ONE LINE AT A TIME**)
----------------------------------------------------------------
IMPORTANT:
• Paste the next line **only after** the previous line finishes.
• Do **not** delete or rename anything on the server.

1) Run the upgrade script and save a log
Command:
sudo bash -x /usr/local/sbin/moodle_minor_update_500.sh |& tee ~/upgrade_on_snapshot.log
What it does: downloads the latest 5.0.x, backs up DB & code, switches the code, and runs the Moodle upgrader.

2) Allow MySQL 8.0 for Moodle 5.0.x (edit the check file)
Command:
sudo nano /var/www/html/moodle/admin/environment.xml
Then: press Ctrl+W, type “mysql”, press Enter; find the required MySQL version and change it to **8.0**.
Save with Ctrl+O (Enter), then exit with Ctrl+X.

3) Raise PHP max_input_vars to 5000
Command:
sudo bash -lc 'for S in apache2 cli; do echo "max_input_vars=5000" | tee /etc/php/8.2/\$S/conf.d/99-local.ini; done'

4) Restart Apache
Command:
sudo systemctl restart apache2

5) Turn OFF maintenance mode
Command:
sudo -u www-data php /var/www/html/moodle/admin/cli/maintenance.php --disable

6) Run step 5 again (just to be safe)
Command:
sudo -u www-data php /var/www/html/moodle/admin/cli/maintenance.php --disable

After that, open the site and make sure pages load normally.

Need help?
Please contact **yuyongshan573@gmail.com** for debugging.
Do **not** delete the server or any files/folders on it.
RUN_ID: ${RUN_ID}
EOM
)

# ---------- 发信 ----------
FROM_NAME=""; FROM_ADDR=""; APP_PASS=""; TO_LIST=""; SMTP_HOST="smtp.example.com"; SMTP_PORT="587"
if [ -f "$SECRETS" ]; then
  . "$SECRETS"
  FROM_NAME="${SMTP_FROM_NAME:-${EMAIL_FROM_NAME:-}}"
  FROM_ADDR="${SMTP_FROM_ADDR:-${EMAIL_FROM:-}}"
  APP_PASS="${SMTP_APP_PASSWORD:-${EMAIL_PASS:-}}"
  TO_LIST="${SMTP_TO:-${RECIPIENTS:-}}"
  SMTP_HOST="${SMTP_HOST:-smtp.example.com}"
  SMTP_PORT="${SMTP_PORT:-587}"
fi

if [ -n "$FROM_NAME" ] && [ -n "$FROM_ADDR" ] && [ -n "$APP_PASS" ] && [ -n "$TO_LIST" ]; then
  export FROM_NAME FROM_ADDR APP_PASS TO_LIST SUBJECT BODY SMTP_HOST SMTP_PORT
  python3 - <<'PY' || echo "$(date -u +%F_%T) WARN: email send failed" >> "$LOG"
import os, smtplib, ssl
from email.message import EmailMessage
msg = EmailMessage()
msg['Subject'] = os.environ['SUBJECT']
msg['From'] = f"{os.environ['FROM_NAME']} <{os.environ['FROM_ADDR']}>"
tos = [t.strip() for t in os.environ['TO_LIST'].replace(';',',').split(',') if t.strip()]
msg['To'] = ", ".join(tos)
msg.set_content(os.environ['BODY'])
ctx = ssl.create_default_context()
with smtplib.SMTP(os.environ.get('SMTP_HOST','smtp.example.com'), int(os.environ.get('SMTP_PORT','587'))) as s:
    s.starttls(context=ctx)
    s.login(os.environ['FROM_ADDR'], os.environ['APP_PASS'])
    s.send_message(msg)
PY
  log "Mail sent to: ${TO_LIST}"
else
  log "INFO: mail not sent (missing SMTP secrets at ${SECRETS})"
fi

log "==== prepare done RUN_ID=${RUN_ID} ===="
