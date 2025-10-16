#!/usr/bin/env bash
set -euo pipefail

# === 路径与版本 ===
DOCROOT="/var/www/html/moodle"      # Moodle 代码目录
RELEASES="/opt/moodle/releases"     # 新版本解包目录
BACKUPS="/opt/moodle/backups"       # 备份目录
MAJOR="500"                         # 5.0 系列（与 version.php 的 $branch 对应）
PKG_URL="https://download.moodle.org/download.php/direct/stable${MAJOR}/moodle-latest-${MAJOR}.tgz"

# 从 config.php 读取 DB 信息（仅用于备份）
CFG="${DOCROOT}/config.php"
DBNAME=$(php -r "define('CLI_SCRIPT',1); include '${CFG}'; echo \$CFG->dbname;")
DBUSER=$(php -r "define('CLI_SCRIPT',1); include '${CFG}'; echo \$CFG->dbuser;")
DBPASS=$(php -r "define('CLI_SCRIPT',1); include '${CFG}'; echo isset(\$CFG->dbpass)?\$CFG->dbpass:'';")
DBHOST=$(php -r "define('CLI_SCRIPT',1); include '${CFG}'; echo isset(\$CFG->dbhost)?\$CFG->dbhost:'localhost';")

STAMP=$(date -u +%Y%m%d-%H%M%S)
NEW="${RELEASES}/moodle-${STAMP}"
OLD="${DOCROOT}.prev-${STAMP}"

sudo mkdir -p "${RELEASES}" "${BACKUPS}"

echo "== 1) Enable maintenance mode =="
sudo -u www-data php "${DOCROOT}/admin/cli/maintenance.php" --enable

echo "== 2) Stop Apache (short downtime) =="
sudo systemctl stop apache2

echo "== 3) Backup DB & code =="
if [ -n "${DBPASS}" ]; then PASSOPT=(-p"${DBPASS}"); else PASSOPT=(); fi
mysqldump -h "${DBHOST}" -u"${DBUSER}" "${PASSOPT[@]}" \
  --single-transaction --routines --triggers --no-tablespaces "${DBNAME}" \
  | gzip > "${BACKUPS}/db-${DBNAME}-${STAMP}.sql.gz"
sudo tar -C "$(dirname "${DOCROOT}")" -czf "${BACKUPS}/code-$(basename "${DOCROOT}")-${STAMP}.tgz" "$(basename "${DOCROOT}")"

echo "== 4) Download new package =="
mkdir -p "${NEW}"
curl -fsSL "${PKG_URL}" | tar -xz -C "${NEW}" --strip-components=1

echo "== 5) Migrate config & custom bits =="
# 必带配置
cp -a "${DOCROOT}/config.php" "${NEW}/config.php"
# 额外配置（如 config-redis.php 等）
cp -a ${DOCROOT}/config-*.php "${NEW}/" 2>/dev/null || true
# 自定义 .htaccess（如有）
[ -f "${DOCROOT}/.htaccess" ] && cp -a "${DOCROOT}/.htaccess" "${NEW}/.htaccess"
# 常见插件/子目录（存在才拷贝；不覆盖核心）
for d in auth blocks enrol filter local mod report theme tool availability qtype question; do
  [ -d "${DOCROOT}/${d}" ] && rsync -a --ignore-existing "${DOCROOT}/${d}/" "${NEW}/${d}/"
done

echo "== 6) Switch code directory =="
sudo mv "${DOCROOT}" "${OLD}"
sudo mv "${NEW}" "${DOCROOT}"
sudo chown -R www-data:www-data "${DOCROOT}"

echo "== 7) Start Apache back =="
sudo systemctl start apache2

echo "== 8) Run CLI upgrade =="
sudo -u www-data php "${DOCROOT}/admin/cli/upgrade.php" --non-interactive

echo "== 9) Purge caches & disable maintenance =="
sudo -u www-data php "${DOCROOT}/admin/cli/purge_caches.php" || true
sudo -u www-data php "${DOCROOT}/admin/cli/maintenance.php" --disable

echo "== DONE =="
echo "Rollback if needed:"
echo "  sudo mv ${DOCROOT} ${DOCROOT}.bad-${STAMP} && sudo mv ${OLD} ${DOCROOT} && sudo systemctl reload apache2"
