#!/usr/bin/env bash
set -euo pipefail
WINDOW_MIN=10
COOLDOWN_MIN=120
STATE_FILE="/var/tmp/smtp_535_last_notified"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

# 收集最近日志，并排除 watcher 自己相关行
if command -v journalctl >/dev/null 2>&1; then
  journalctl --since "${WINDOW_MIN} minutes ago" -o short-iso \
    | grep -vi 'smtp_535_watcher\.sh' >"$TMP" || true
else
  cat /var/log/syslog* 2>/dev/null | tail -n 5000 \
    | grep -vi 'smtp_535_watcher\.sh' >"$TMP" || true
fi

# 仅在“真实认证失败签名”出现时触发：
#  - Python 异常：SMTPAuthenticationError:   （带冒号）
#  - Gmail 典型： (535, ... 5.7.x ... gsmtp)
#  - 或明确文案：5.7.8 Username and Password not accepted
if ! grep -Eiq 'SMTPAuthenticationError:|\(535,\s*b?5\.7\.[0-9].*gsmtp|5\.7\.8 Username and Password not accepted' "$TMP"; then
  exit 0
fi

# 冷却窗口
if [[ -f "$STATE_FILE" ]]; then
  last=$(cat "$STATE_FILE" 2>/dev/null || echo 0); now=$(date +%s)
  (( now - last < COOLDOWN_MIN*60 )) && exit 0
fi

# Python：先尝试 Gmail，失败则 SNS（实例角色→ubuntu profile 双路径）
python3 - <<'PY'
import os,re,smtplib,subprocess,sys,datetime
from email.mime.text import MIMEText
from email.utils import formataddr

def load_env(path="/etc/moodle-notify.env"):
    # 强制覆盖：无论原环境有没有同名变量，都以文件为准
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            for line in f:
                m=re.match(r'\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$', line)
                if not m: continue
                k,v=m.groups(); v=v.strip()
                if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                    v=v[1:-1]
                os.environ[k]=v
    except FileNotFoundError:
        pass

def send_gmail():
    sender=os.getenv("EMAIL_SENDER","courage2act.notify@gmail.com")
    pwd=os.getenv("EMAIL_PASSWORD") or os.getenv("EMAIL_PASS","")
    to=os.getenv("EMAIL_TO") or os.getenv("RECIPIENTS") or os.getenv("DEFAULT_EMAIL_TO","yuyongshan573@gmail.com")
    name=os.getenv("EMAIL_FROM_NAME","Moodle Bot")
    smtp=os.getenv("SMTP_SERVER","smtp.example.com"); port=int(os.getenv("SMTP_PORT","587"))
    now=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    body = ("We detected SMTPAuthenticationError/535 in the last 10 minutes.\n\n"
            "Action required:\n"
            "1) Generate a NEW Gmail App Password for courage2act.notify@gmail.com\n"
            "2) On the server, run:\n"
            "   sudo /usr/local/sbin/mailpass_rotate.sh\n"
            "   (or update /etc/moodle-notify.env: EMAIL_PASSWORD / EMAIL_PASS)\n\n"
            "This alert is suppressed for 120 minutes after each send.\n\n"
            f"-- Sent at {now} --")
    msg=MIMEText(body,"plain","utf-8")
    msg["From"]=formataddr((name,sender)); msg["To"]=to; msg["Subject"]="ALERT: Gmail App Password likely expired (535)"
    s=smtplib.SMTP(smtp,port,timeout=15); s.starttls(); s.login(sender,pwd)
    s.sendmail(sender,[to],msg.as_string()); s.quit()
    print("[ALERT] gmail sent to", to)

def publish_sns(topic, subject, message, region):
    cmd = ["aws","sns","publish","--region",region,"--topic-arn",topic,"--subject",subject,"--message",message]
    # 1) 先用当前环境（root 无本地凭证→实例角色 030…）
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=12)
    if out.returncode == 0:
        print("[ALERT] sns published via instance role")
        return True
    # 2) 如遇 AuthorizationError，用 ubuntu 的本地凭证（082…）
    if "AuthorizationError" in (out.stderr or ""):
        out2 = subprocess.run(["sudo","-u","ubuntu"] + cmd, capture_output=True, text=True, timeout=12)
        if out2.returncode == 0:
            print("[ALERT] sns published via ubuntu profile")
            return True
        print("[ERR] sns publish failed via ubuntu:", out2.stderr, file=sys.stderr)
        return False
    print("[ERR] sns publish failed:", out.stderr, file=sys.stderr)
    return False

def send_sns():
    topic=os.getenv("SNS_TOPIC_ARN")
    region=os.getenv("AWS_REGION","ca-central-1")
    if not topic:
        print("[WARN] SNS_TOPIC_ARN not set; cannot fallback.", file=sys.stderr); return
    subject="ALERT: Gmail App Password likely expired (535)"
    message=("SMTP 535 detected by watcher.\n"
             "Please rotate the Gmail App Password and run:\n"
             "  sudo /usr/local/sbin/mailpass_rotate.sh\n")
    publish_sns(topic, subject, message, region)

load_env()
try:
    send_gmail()
except Exception as e:
    print("[WARN] gmail send failed, fallback to SNS:", e)
    send_sns()
PY

# 更新冷却时间
date +%s > "$STATE_FILE"
