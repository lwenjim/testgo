<?php

$socket = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);

if ($socket === false) {
    die("socket_create failed" . socket_strerror(socket_last_error()));
}

$host = '192.168.1.3';
$port = 9501;
$timeout = 10;

$result = socket_connect($socket, $host, $port);
if ($result === false) {
    die('socket_connect() failed:' . socket_strerror(socket_last_error()));
}

echo sprintf("成功连接服务器\n");
while (true) {
    $response = socket_read($socket, 1024);
    if ($response === false) {
        break;
    }
    $response =     trim($response);
    if (strlen($response)>0) {
        echo sprintf("%s:%s->%s\n", $host, $port, $response);
    }
    $message = fread(STDIN, 1024) . "\n";
    if (strlen($message) > 0) {
        socket_write($socket, $message, strlen($message));
    }
}

socket_close($socket);
