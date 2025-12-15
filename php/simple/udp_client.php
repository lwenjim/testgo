<?php
// 服务器地址和端口
$server_ip = '127.0.0.1';
$server_port = 9501;

// 创建UDP socket
$socket = socket_create(AF_INET, SOCK_DGRAM, SOL_UDP);
if ($socket === false) {
    echo "创建socket失败: " . socket_strerror(socket_last_error()) . "\n";
    exit(1);
}

echo "UDP客户端已创建\n";
echo "连接到服务器 {$server_ip}:{$server_port}\n";
echo "输入消息发送到服务器，输入 'quit' 退出\n";

// 设置socket非阻塞，以便可以同时处理用户输入和接收数据
socket_set_nonblock($socket);

// 客户端主循环
while (true) {
    // 从标准输入读取用户输入
    echo "> ";
    $input = trim(fgets(STDIN));

    if (empty($input)) {
        continue;
    }

    // 发送消息到服务器
    $bytes_sent = socket_sendto($socket, $input, strlen($input), 0, $server_ip, $server_port);

    if ($bytes_sent === false) {
        echo "发送失败: " . socket_strerror(socket_last_error($socket)) . "\n";
    } else {
        echo "已发送 {$bytes_sent} 字节到服务器\n";
    }

    // 尝试接收服务器的回复（非阻塞方式）
    $response = '';
    $from = '';
    $port = 0;

    // 尝试接收数据，最多尝试5次
    for ($i = 0; $i < 5; $i++) {
        $bytes_received = socket_recvfrom($socket, $response, 2048, 0, $from, $port);

        if ($bytes_received > 0) {
            echo "收到服务器回复: {$response}\n";
            break;
        }

        // 等待一小段时间再试
        usleep(100000); // 100ms
    }

    // 如果用户输入quit，则退出
    if ($input == 'quit') {
        echo "客户端关闭\n";
        break;
    }
}

// 关闭socket
socket_close($socket);
?>