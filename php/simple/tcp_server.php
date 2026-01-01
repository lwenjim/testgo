<?php
set_time_limit(0);
$socket = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);
if ($socket === false) {
    die("failed to create socket");
}

$address = '192.168.1.3';
$port = 9501;

if (!socket_bind($socket, $address, $port)) {
    die("failed to bind");
}

echo "tcp starting:{$address}:{$port}\n";

if (!socket_listen($socket, 5)) {
    die("failed to listen");
}

while (true) {
    $client = socket_accept($socket);
    if (!$client) {
        echo "socket_accept failed:" . socket_strerror(socket_last_error($socket)) . "\n";
        break;
    }

    // 获取客户端信息
    $clientAddress = "";
    $clientPort = '';
    socket_getpeername($client, $clientAddress, $clientPort);
    echo "client connect:{$clientAddress}:{$clientPort}\n";

    // 读取客户端数据
    $input = socket_read($client, 1024);
    echo "receive data:" . trim($input) . "\n";

    // 响应客户端
    $response = date('Y-m-d H:i:s') . "\n";
    socket_write($client, $response, strlen($response));

}
socket_close($socket);
