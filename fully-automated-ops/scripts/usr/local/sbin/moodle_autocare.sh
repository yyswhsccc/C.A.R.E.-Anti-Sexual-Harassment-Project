#!/usr/bin/env bash
set -euo pipefail
LOGDIR=/var/log/moodle
LOG=$LOGDIR/autocare.log
mkdir -p "$LOGDIR"; touch "$LOG"; chown www-data:www-data "$LOG" || true
log(){ printf "[%s] %s\n" "$(date -Is)" "$*" | tee -a "$LOG"; }

log "=== Autocare start ==="
df -h /var | tee -a "$LOG" || true

# 1) MySQL/binlog（跨版本）
if command -v mysql >/dev/null 2>&1; then
  log "MySQL: enforce 1-day binlog retention (cross-version)"
  ver=$(mysql -NBe "SELECT @@version;" 2>/dev/null || echo "")
  comm=$(mysql -NBe "SELECT @@version_comment;" 2>/dev/null || echo "")
  [ -n "$ver$comm" ] && log "MySQL version: $ver $comm"

  if mysql -NBe "SHOW VARIABLES LIKE binlog_expire_logs_seconds;" 2>/dev/null | grep -q binlog_expire_logs_seconds; then
    mysql -e "SET PERSIST binlog_expire_logs_seconds = 86400;" >/dev/null 2>&1 || \
    mysql -e "SET GLOBAL  binlog_expire_logs_seconds = 86400;"  >/dev/null 2>&1 || true
  elif mysql -NBe "SHOW VARIABLES LIKE expire_logs_days;" 2>/dev/null | grep -q expire_logs_days; then
    mysql -e "SET GLOBAL expire_logs_days = 1;" >/dev/null 2>&1 || true
    # 持久化到配置文件
    CFG=""
    for c in /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
      [ -f "$c" ] && CFG="$c" && break
    done
    if [ -n "$CFG" ]; then
      sed -i -E "/^\[mysqld\]/,/^\[/{s/^[[:space:]]*expire_logs_days.*/expire_logs_days = 1/}" "$CFG" || true
      grep -q "expire_logs_days" "$CFG" || sed -i "/^\[mysqld\]/a expire_logs_days = 1" "$CFG" || true
    fi
  fi

  # 若未配置复制，则清理 1 天前的 binlog
  if (mysql -NBe "SHOW SLAVE HOSTS;" 2>/dev/null | grep -q .) || \
     (mysql -NBe "SHOW SLAVE STATUS\\G" 2>/dev/null | grep -q .) || \
     (mysql -NBe "SHOW REPLICA STATUS\\G" 2>/dev/null | grep -q .); then
    log "MySQL: replicas detected; skip manual PURGE"
  else
    log "MySQL: purge binlogs older than 1 day"
    mysql -e "PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 1 DAY);" >/dev/null 2>&1 || true
  fi

  # 文本日志：常规轮转；目录>300MB时截断当前巨型日志
  if [ -d /var/log/mysql ]; then
    log "MySQL: rotate text logs (mysql-server)"
    logrotate /etc/logrotate.d/mysql-server || true
    sz=$(du -sb /var/log/mysql | awk "{print \$1}")
    if [ "${sz:-0}" -gt $((300*1024*1024)) ]; then
      for f in /var/log/mysql/error.log /var/log/mysql/mysql-slow.log /var/log/mysql/mysql.log; do
        [ -f "$f" ] || continue
        cs=$(stat -c%s "$f" 2>/dev/null || echo 0)
        if [ "$cs" -gt $((100*1024*1024)) ]; then
          log "MySQL: truncating $f ($cs bytes)"; : > "$f"
        fi
      done
    fi
  fi
fi

# 2) journald：≤100M / 7d
log "journald: vacuum to 100M / 7d"
journalctl --vacuum-size=100M >/dev/null 2>&1 || true
journalctl --vacuum-time=7d   >/dev/null 2>&1 || true

# 3) APT 缓存
log "APT: autoremove/autoclean/clean"
apt-get -y autoremove --purge >/dev/null 2>&1 || true
apt-get -y autoclean            >/dev/null 2>&1 || true
apt-get clean                   >/dev/null 2>&1 || true

# 4) PHP 会话 & /var/tmp
log "PHP sessions >2d; /var/tmp >7d"
find /var/lib/php/sessions -type f -mtime +2 -delete 2>/dev/null || true
find /var/tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true
find /var/tmp -xdev -mindepth 1 -type d -empty -delete 2>/dev/null || true

# 5) snap 旧修订
if command -v snap >/dev/null 2>&1; then
  log "snap: remove disabled revisions & set retain=2"
  snap list --all 2>/dev/null | awk '$NF=="disabled"{print "snap remove --revision="$3" "$1}' | bash 2>/dev/null || true
  snap set system refresh.retain=2 2>/dev/null || true
fi

# 6) /var 高水位保护（>80%）
usep=$(df -P /var | awk "NR==2{print \$5}" | tr -d "%")
if [ "${usep:-0}" -ge 80 ]; then
  log "High /var usage (${usep}%). Aggressive cleanup."
  find /var/log/mysql -type f -regextype posix-extended -regex ".*/(mysql|error|mysqld).*\.log\.[0-9]+" -mtime +1 -exec gzip -f {} + 2>/dev/null || true
  # 无复制时可一键只留最近 1 个 binlog
  if command -v mysql >/dev/null 2>&1 && \
     ! (mysql -NBe "SHOW SLAVE STATUS\\G" 2>/dev/null | grep -q . || mysql -NBe "SHOW REPLICA STATUS\\G" 2>/dev/null | grep -q .); then
    mysql -e "PURGE BINARY LOGS BEFORE NOW();" >/dev/null 2>&1 || true
  fi
  journalctl --vacuum-size=50M >/dev/null 2>&1 || true
fi

log "=== Autocare end ==="
