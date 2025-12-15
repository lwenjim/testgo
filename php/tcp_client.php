<?php

$socket = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);

if ($socket === false) {
    die("socket_create failed".socket_strerror(socket_last_error()));
}

echo "attemp to connect server ...\n";

$host = '192.168.1.16';
$port = 9501;
$timeout = 10;

$result = socket_connect($socket, $host, $port);
if ($result === false) {
    die('socket_connect() failed:'.socket_strerror(socket_last_error()));
}

echo "success to connect server\n";

if (socket_getpeername($socket, $remote_address, $remote_port)) {
    echo "success server: $remote_address:$remote_port\n";
}

$message = "Hello Server!\n";
socket_write($socket, $message, strlen($message));

$response = socket_read($socket, 1024);
echo "response from server:".$response;

echo socket_close($socket);