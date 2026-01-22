<?php

use Swoole\WebSocket\Server;
use Swoole\Http\Request;
use Swoole\WebSocket\Frame;

// 创建 WebSocket 服务器，监听 0.0.0.0:9501
$server = new Server("0.0.0.0", 9501);

// 存储所有连接的 fd（文件描述符）
$server->connections = [];

// 当有客户端连接时触发
$server->on("open", function (Server $server, $request) {
    echo "新连接：{$request->fd}\n";
    $server->connections[$request->fd] = $request->fd;
});

// 收到客户端消息时触发
$server->on("message", function (Server $server, Frame $frame) {
    $msg = $frame->data;
    echo "收到消息（来自 {$frame->fd}）: {$msg}\n";

    // 广播给所有连接的客户端（除了自己）
    foreach ($server->connections as $fd) {
        if ($fd !== $frame->fd && $server->isEstablished($fd)) {
            $server->push($fd, "用户{$frame->fd}: {$msg}");
        }
    }
});

// 客户端断开连接时触发
$server->on("close", function (Server $server, $fd) {
    echo "连接关闭：{$fd}\n";
    unset($server->connections[$fd]);
});

echo "WebSocket 服务器启动在 ws://0.0.0.0:9501\n";
$server->start();
