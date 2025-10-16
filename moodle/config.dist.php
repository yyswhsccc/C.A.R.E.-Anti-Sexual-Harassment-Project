<?php  // Moodle configuration file

unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->wwwroot   = 'https://example.test/moodle';
$CFG->dataroot  = '/path/to/moodledata';
$CFG->dbtype    = 'mysqli';
$CFG->dblibrary = 'native';
$CFG->dbname    = 'moodle_db';
$CFG->dbuser    = 'moodle_user';
$CFG->dbpass    = 'CHANGE_ME';
$CFG->prefix    = 'mdl_';
$CFG->dbhost    = 'localhost';
$CFG->dboptions = array (
  'dbpersist' => 0,
  'dbport' => '3306',
  'dbsocket' => '',
  'dbcollation' => 'utf8mb4_unicode_ci',
);
$CFG->cronclionly = true;

require_once __DIR__ . '/config-redis.php';
// === BEGIN: lock executable paths (auto-added) ===
$CFG->pathtophp  = '/usr/bin/php';
$CFG->pathtozip  = '/usr/bin/zip';
$CFG->pathtounzip= '/usr/bin/unzip';
$CFG->pathtotar  = '/usr/bin/tar';
$CFG->pathtogs   = '/usr/bin/gs';
$CFG->pathtodu   = '/usr/bin/du';
$CFG->preventexecpath = true;
// === END: lock executable paths ===
require_once(dirname(__FILE__) . '/lib/setup.php');







//$CFG->session_handler_class = '\core\session\redis';
//$CFG->session_redis_host = '127.0.0.1';
//$CFG->session_redis_port = 6379;
//$CFG->session_redis_database = 0;
//$CFG->session_redis_prefix = 'sess_';
//$CFG->session_redis_acquire_lock_timeout = 120;
//$CFG->session_redis_lock_expire = 7200; 
//$CFG->session_redis_auth = 'courage2actredis';
// ----- Forced ClamAV settings (low-memory friendly) -----
$CFG->antivirusplugins = ['clamav']; // ensure enabled
$CFG->forced_plugin_settings['antivirus_clamav'] = [
    'runningmethod' => 'commandline',   // 使用命令行模式
    'pathclamscan'  => '/usr/bin/clamscan', // clamscan 路径（Debian/Ubuntu 默认）
    // 失败策略沿用默认：Refuse upload, try again
];
