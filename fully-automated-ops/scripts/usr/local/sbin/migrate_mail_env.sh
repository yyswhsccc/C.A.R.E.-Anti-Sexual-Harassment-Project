#!/usr/bin/env bash
set -euo pipefail
MODE="${1:---dry-run}"   # --dry-run | --apply
TS="$(date +%F-%H%M%S)"; BACKUP="/root/migrate_mail_env_backup/$TS"; mkdir -p "$BACKUP"

SEARCH_DIRS=(/etc /home /usr/local)
EXCLUDES=( -path '*/.git/*' -o -path '*/venv/*' -o -path '*/.venv/*' -o -path '*/node_modules/*'
          -o -path '/proc/*' -o -path '/sys/*' -o -path '/run/*' -o -path '/var/lib/docker/*'
          -o -name '*.log' -o -name '*.bak' -o -name '*.bak.*' -o -name '.bash_history' )
GREP_PAT='smtp\.gmail\.com|EMAIL_(SENDER|PASSWORD|PASS|PWD|TO|RECEIVERS|SMTP_SERVER|SMTP_PORT)|pwd[[:space:]]*='

declare -a CANDS=()
while IFS= read -r -d '' f; do
  file -b --mime "$f" | grep -qi 'text' || continue
  grep -E -q "$GREP_PAT" "$f" || continue
  case "$f" in
    /etc/moodle-notify.env) continue ;;
    */alertmanager.yml)     continue ;;
    /usr/local/sbin/migrate_mail_env.sh) continue ;;
  esac
  CANDS+=("$f")
done < <(find "${SEARCH_DIRS[@]}" -type f \( ! \( "${EXCLUDES[@]}" \) \) -size -2M -print0 2>/dev/null)

echo "==> Candidates: ${#CANDS[@]} files"
for f in "${CANDS[@]}"; do echo " - $f"; done

if [[ "$MODE" == "--dry-run" ]]; then
  echo; echo "==> DRY-RUN: sample matches"
  for f in "${CANDS[@]}"; do
    echo "--- $f ---"
    grep -En 'EMAIL_(SENDER|PASSWORD|PASS|PWD|TO|RECEIVERS|SMTP_SERVER|SMTP_PORT)|smtp\.gmail\.com|pwd[[:space:]]*=' "$f" | head -3 || true
  done
  exit 0
fi

echo; echo "==> APPLY: backup & patch"
for f in "${CANDS[@]}"; do
  mkdir -p "$BACKUP/$(dirname "$f")"
  cp -a "$f" "$BACKUP/$f"

  firstline="$(head -n1 "$f" || true)"
  if [[ "$firstline" =~ ^#!.*(bash|sh) ]]; then
    # ---- Shell 脚本 ----
    if ! grep -q '>>> load /etc/moodle-notify.env >>>' "$f"; then
      tmp="$(mktemp)"
      {
        echo "$firstline"
        echo "# >>> load /etc/moodle-notify.env >>>"
        echo '[ -f /etc/moodle-notify.env ] && set -a && . /etc/moodle-notify.env && set +a'
        echo ': "${EMAIL_SENDER:?set in /etc/moodle-notify.env}"'
        echo ': "${EMAIL_PASSWORD:?set in /etc/moodle-notify.env}"'
        echo ': "${SMTP_SERVER:=smtp.example.com}"'
        echo ': "${SMTP_PORT:=587}"'
        echo "# <<< load /etc/moodle-notify.env <<<"
        tail -n +2 "$f"
      } > "$tmp"
      cat "$tmp" > "$f"; rm -f "$tmp"
    fi
    sed -Ei \
      -e 's/^([[:space:]]*)(export[[:space:]]+)?(EMAIL_(SENDER|PASSWORD|PASS|PWD|TO|RECEIVERS|SMTP_SERVER|SMTP_PORT))[[:space:]]*=.*/# MOVED_TO_ENV: \1\3=.../g' \
      "$f" || true

  elif [[ "$firstline" =~ ^#!.*python || "$f" =~ \.py$ ]]; then
    # ---- Python 脚本（含无 shebang 的 .py）----
    if ! grep -q '>>> load /etc/moodle-notify.env >>>' "$f"; then
      tmp="$(mktemp)"
      {
        echo "$firstline"
        cat <<'PYENV'
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
EMAIL_PASSWORD = os.getenv("EMAIL_PASSWORD", os.getenv("EMAIL_PASS", os.getenv("EMAIL_PWD", "")))
EMAIL_PASS = EMAIL_PASSWORD
EMAIL_PWD = EMAIL_PASSWORD
EMAIL_SENDER = os.getenv("EMAIL_SENDER", "")
SMTP_SERVER = os.getenv("SMTP_SERVER", "smtp.example.com")
try:
    SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
except Exception:
    SMTP_PORT = 587
# <<< load /etc/moodle-notify.env <<<
PYENV
        tail -n +2 "$f"
      } > "$tmp"
      cat "$tmp" > "$f"; rm -f "$tmp"
    fi
    sed -Ei \
      -e 's/^([[:space:]]*)(EMAIL_PASSWORD|EMAIL_PASS|EMAIL_PWD|EMAIL_SENDER|SMTP_SERVER|SMTP_PORT)[[:space:]]*=.*/# MOVED_TO_ENV: \1\2=.../g' \
      "$f" || true

  else
    # 其它文本：只注释 Shell 风格的硬编码
    sed -Ei \
      -e 's/^([[:space:]]*)(export[[:space:]]+)?(EMAIL_(SENDER|PASSWORD|PASS|PWD|TO|RECEIVERS|SMTP_SERVER|SMTP_PORT))[[:space:]]*=.*/# MOVED_TO_ENV: \1\3=.../g' \
      "$f" || true
  fi
done

echo "==> DONE. Backups at: $BACKUP"
