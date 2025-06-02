<?php
// Sample Moodle configuration file for local development.
// DO NOT use real passwords or sensitive credentials in this file.

$CFG = new stdClass();

$CFG->dbtype    = 'mysqli';            // Database type (e.g., mysqli, pgsql)
$CFG->dblibrary = 'native';            // Database library
$CFG->dbhost    = 'localhost';         // Database host
$CFG->dbport    = '3306';              // Database port
$CFG->dbname    = 'your_db_name';      // Database name
$CFG->dbuser    = 'your_db_user';      // Database username
$CFG->dbpass    = 'your_db_password';  // Database password
$CFG->prefix    = 'mdl_';              // Table prefix (default: mdl_)

// Optional settings:
// $CFG->wwwroot   = 'http://localhost:8888/moodle';
// $CFG->dataroot  = '/path/to/moodledata';
// $CFG->admin     = 'admin';

// Copy this file to config.php and update with your actual values.
// NEVER commit config.php with real credentials to version control.
