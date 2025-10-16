#!/usr/bin/env bash
set -euo pipefail
timeout="${1:-600}"  # 默认 600s
end=$((SECONDS+timeout))
while (( SECONDS < end )); do
  if getent hosts s3.ca-central-1.amazonaws.com >/dev/null 2>&1 \
     && curl -sSf --max-time 5 https://s3.ca-central-1.amazonaws.com >/dev/null 2>&1; then
    exit 0
  fi
  sleep 10
done
echo "wait_net: timeout ${timeout}s" >&2
exit 1
