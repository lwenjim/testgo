<?php
set_time_limit(0);
$socket = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);
if ($socket === false) {
    die("failed to create socket");
}

$address = '192.168.50.29';
$port = 9501;

if (!socket_bind($socket, $address, $port)) {
    die("failed to bind");
}

if (!socket_listen($socket, 5)) {
    die("failed to listen");
}
$config = require "config.php";
echo sprintf("服务器启动成功\n", $address, $port);
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
    $response = sprintf("欢迎加入聊天室\n");
    socket_write($client, $response, strlen($response));

    echo sprintf("客户端 %s:%s 加入\n", $clientAddress, $clientPort);
    $pid = pcntl_fork();
    if ($pid == -1) {
        die("failed to failed");
    } elseif ($pid) {
        for ($i = 0; $i < 1000; $i++) {
            $response = fread(STDIN, 1024) . "\n";
            if ($response === false) {
                socket_close($client);
                break;
            }
            if (strlen($response) > 0) {
                socket_write($client, $response, strlen($response));
            }
        }
        pcntl_waitpid($pid, $status, WNOHANG);
        socket_close($socket);
    } else {
        for ($i = 0; $i < 1000; $i++) {
            $input = socket_read($client, 1024);
            if ($input === false) {
                echo sprintf("客户端 %s:%s 断开\n", $clientAddress, $clientPort);
                socket_close($client);
                break;
            }
            if (strlen($input) > 0) {
                echo sprintf("%s: %s\n", $config["client"]["name"], trim($input));
            }
        }
        exit(0);
    }
}
