#!/usr/bin/env python3
# >>> load /etc/moodle-notify.env >>>
import os, re
def _load_env(path="/etc/moodle-notify.env"):
    try:
        with open(path, "r") as f:
            for line in f:
                m = re.match(r'\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$', line)
                if not m: continue
                k, v = m.group(1), m.group(2).strip()
                if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
                    v = v[1:-1]
                os.environ.setdefault(k, v)
    except FileNotFoundError:
        pass
_load_env()
# MOVED_TO_ENV: EMAIL_PASSWORD=...
# MOVED_TO_ENV: EMAIL_PASS=...
# MOVED_TO_ENV: EMAIL_PWD=...
# MOVED_TO_ENV: EMAIL_SENDER=...
# MOVED_TO_ENV: SMTP_SERVER=...
try:
    pass
# MOVED_TO_ENV:     SMTP_PORT=...
except Exception:
    pass
# MOVED_TO_ENV:     SMTP_PORT=...
# <<< load /etc/moodle-notify.env <<<
import os, sys, smtplib
from email.message import EmailMessage

host = os.environ.get("SMTP_HOST","smtp.example.com")
port = int(os.environ.get("SMTP_PORT","587"))
user = os.environ.get("EMAIL_FROM")
pwd  = os.environ.get("EMAIL_PASS")
from_name = os.environ.get("EMAIL_FROM_NAME", user or "Notifier")
rcpts = [r.strip() for r in os.environ.get("RECIPIENTS","").replace(";",",").split(",") if r.strip()]
subject = os.environ.get("MAIL_SUBJECT","Moodle Perf Report")
body = sys.stdin.read()

if not (user and pwd and rcpts):
    sys.stderr.write("[email] missing EMAIL_FROM/EMAIL_PASS/RECIPIENTS; skip\n")
    sys.exit(0)

msg = EmailMessage()
msg["Subject"] = subject
msg["From"]    = f"{from_name} <{user}>"
msg["To"]      = ", ".join(rcpts)
msg.set_content(body)

with smtplib.SMTP(host, port, timeout=15) as s:
    s.starttls()
    s.login(user, pwd)
    s.send_message(msg)
