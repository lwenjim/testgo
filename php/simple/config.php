<?php
$config = parse_ini_file(__DIR__ . "/config.ini", true);
if (!$config) {
    die("failed to load config.ini");
}
return $config;