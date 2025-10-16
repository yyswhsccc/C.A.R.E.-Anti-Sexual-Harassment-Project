#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="/etc/moodle-notify.env"
BACKUP_ROOT="/root/mailpass_rotate_backups"
TS="$(date +%F-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TS"

usage(){ cat <<'USAGE'
Usage:
  sudo /usr/local/sbin/mailpass_rotate.sh             # 交互式输入新密码
  sudo /usr/local/sbin/mailpass_rotate.sh --set NEW16 # 非交互，直接设置新密码
  sudo /usr/local/sbin/mailpass_rotate.sh --revert    # 回滚到最近一次备份
USAGE
}

ensure_env(){ [[ -f "$ENV_FILE" ]] || { echo "[ERR] $ENV_FILE 不存在"; exit 1; }; }

read_new_pass(){
  local np
  read -r -s -p "Paste NEW Gmail App Password (16 chars, no spaces): " np; echo
  NEW_PASS="${np//[[:space:]]/}"
  [[ "${#NEW_PASS}" -eq 16 ]] || { echo "[ERR] 长度必须 16"; exit 1; }
}

rotate_now(){
  mkdir -p "$BACKUP_DIR"
  cp -a "$ENV_FILE" "$BACKUP_DIR/"
  # 确保键存在
  grep -q '^EMAIL_PASSWORD=' "$ENV_FILE" || echo 'EMAIL_PASSWORD=' >> "$ENV_FILE"
  grep -q '^EMAIL_PASS='     "$ENV_FILE" || echo 'EMAIL_PASS='     >> "$ENV_FILE"
  sed -i "s/^EMAIL_PASSWORD=.*/EMAIL_PASSWORD=${NEW_PASS}/" "$ENV_FILE"
  sed -i "s/^EMAIL_PASS=.*/EMAIL_PASS=${NEW_PASS}/"         "$ENV_FILE"
  chmod 644 "$ENV_FILE"
  echo "[OK] 已更新 $ENV_FILE；备份在 $BACKUP_DIR"
}

send_test(){
python3 - <<'PY'
import os, re, smtplib, datetime
from email.mime.text import MIMEText
from email.utils import formataddr

def load_env(path="/etc/moodle-notify.env"):
    try:
        for line in open(path):
            m = re.match(r'\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$', line)
            if not m: continue
            k, v = m.groups(); v = v.strip()
            if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                v = v[1:-1]
            os.environ.setdefault(k, v)
    except FileNotFoundError:
        pass

load_env()
sender=os.getenv("EMAIL_SENDER","courage2act.notify@gmail.com")
pwd=os.getenv("EMAIL_PASSWORD") or os.getenv("EMAIL_PASS","")
to=os.getenv("EMAIL_TO") or os.getenv("RECIPIENTS") or os.getenv("DEFAULT_EMAIL_TO","yuyongshan573@gmail.com")
from_name=os.getenv("EMAIL_FROM_NAME","Moodle Bot")
smtp=os.getenv("SMTP_SERVER","smtp.example.com"); port=int(os.getenv("SMTP_PORT","587"))
now=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

msg=MIMEText(f"Mail password rotated at {now}","plain","utf-8")
msg["From"]=formataddr((from_name,sender)); msg["To"]=to; msg["Subject"]="Mail password rotated ✔"
s=smtplib.SMTP(smtp,port,timeout=20); s.starttls(); s.login(sender,pwd)
s.sendmail(sender,[to],msg.as_string()); s.quit()
print("[TEST] sent to", to)
PY
}

revert_last(){
  local last rel
  last=$(ls -1dt "$BACKUP_ROOT"/* 2>/dev/null | head -1 || true)
  [[ -n "${last:-}" ]] || { echo "[ERR] 没有可回滚的备份"; exit 1; }
  rel="${ENV_FILE#/}"
  [[ -f "$last/$rel" ]] || { echo "[ERR] 备份不完整：$last"; exit 1; }
  cp -a "$last/$rel" "$ENV_FILE"
  chmod 644 "$ENV_FILE"
  echo "[OK] 已回滚到：$last"
}

main(){
  ensure_env
  case "${1:-}" in
    --revert) revert_last; send_test ;;
    --set)
      NEW_PASS="${2:-}"; [[ -n "$NEW_PASS" ]] || { usage; exit 1; }
      [[ "${#NEW_PASS}" -eq 16 ]] || { echo "[ERR] NEW 长度必须 16"; exit 1; }
      rotate_now; send_test ;;
    "") read_new_pass; rotate_now; send_test ;;
    *) usage; exit 1 ;;
  esac
}
main "$@"
