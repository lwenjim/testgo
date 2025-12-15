<?php
// 服务器IP和端口
$server_ip = '127.0.0.1';
$server_port = 9501;

// 创建UDP socket
$socket = socket_create(AF_INET, SOCK_DGRAM, SOL_UDP);
if ($socket === false) {
    echo "创建socket失败: " . socket_strerror(socket_last_error()) . "\n";
    exit(1);
}

// 绑定地址和端口
if (!socket_bind($socket, $server_ip, $server_port)) {
    echo "绑定地址失败: " . socket_strerror(socket_last_error($socket)) . "\n";
    exit(1);
}

echo "UDP服务器启动在 {$server_ip}:{$server_port}\n";
echo "等待接收数据...\n";

// 服务器主循环
while (true) {
    // 接收数据（最大2048字节）
    $buffer = '';
    $from = '';
    $port = 0;

    $bytes_received = socket_recvfrom($socket, $buffer, 2048, 0, $from, $port);

    if ($bytes_received === false) {
        echo "接收数据失败: " . socket_strerror(socket_last_error($socket)) . "\n";
        continue;
    }

    echo "收到来自 {$from}:{$port} 的消息: {$buffer}\n";

    // 构造回复消息
    $response = "服务器已收到你的消息: {$buffer}";

    // 发送回复
    socket_sendto($socket, $response, strlen($response), 0, $from, $port);
    echo "已发送回复到 {$from}:{$port}\n";

    // 如果收到退出指令，则关闭服务器
    if (trim($buffer) == 'quit') {
        echo "收到退出指令，服务器关闭\n";
        break;
    }
}

// 关闭socket
socket_close($socket);
echo "服务器已关闭\n";
