<?php
set_time_limit(0);
$socket = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);
if ($socket === false) {
    die("failed to create socket");
}

$address = '127.0.0.1';
$port = 9501;

if (!socket_bind($socket, $address, $port)) {
    die("failed to bind");
}

if (!socket_listen($socket, 5)) {
    die("failed to listen");
}
$config = require "config.php";
echo sprintf("服务器启动成功\n", $address, $port);

$key = ftok(__FILE__, 'a');
$queue = msg_get_queue($key, 0666);

$pids = [];
$queuePid = pcntl_fork();
if ($queuePid == -1) {
    die("failed to fork");
} else if (!$queuePid) {
    while (true) {
        msg_receive($queue, 1, $msgtype, 1024, $parentMessage);
        echo sprintf("%s: %s\n", $parentMessage[0], $parentMessage[1]);
        print_r($pids);
        foreach ($pids as $pid => $client) {
            if (strlen($parentMessage[1]) > 0) {
                socket_write($client, $parentMessage[1], strlen($parentMessage[1]));
            }
        }
        sleep(1);
    }
    exit(0);
}

// shmop_write($shmId, json_encode($pids), 0);
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
        die("failed to fork");
    } elseif (!$pid) {
        for ($i = 0; $i < 1000; $i++) {
            $input = socket_read($client, 1024);
            if ($input === false) {
                echo sprintf("客户端 %s:%s 断开\n", $clientAddress, $clientPort);
                socket_close($client);
                break;
            }
            if (strlen($input) > 0) {
                msg_send($queue, 1, [posix_getpid(), trim($input)]);
            }
        }
        exit(0);
    }
    $pids[$pid] = $client;
}
