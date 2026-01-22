<?php

$socket = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);

if ($socket === false) {
    die("socket_create failed" . socket_strerror(socket_last_error()));
}

$host = '127.0.0.1';
$port = 9501;
$timeout = 10;

$result = socket_connect($socket, $host, $port);
if ($result === false) {
    die('socket_connect() failed:' . socket_strerror(socket_last_error()));
}
$config = require "config.php";
echo sprintf("成功连接服务器\n");
$pid = pcntl_fork();
if ($pid == -1) {
    die("failed to fork");
} elseif ($pid) {
    for ($i = 0; $i < 1000; $i++) {
        $message = fread(STDIN, 1024) . "\n";
        if (strlen($message) > 0) {
            socket_write($socket, $message, strlen($message));
        }
    }
    pcntl_waitpid($pid, $status, WNOHANG);
    socket_close($socket);
} else {
    for ($i = 0; $i < 1000; $i++) {
        $response = socket_read($socket, 1024);
        if ($response === false) {
            break;
        }
        $response =     trim($response);
        if (strlen($response) > 0) {
            echo sprintf("%s: %s\n", $config["server"]["name"], $response);
        }
    }
    exit(0);
}
