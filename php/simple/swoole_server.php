<?php

use Swoole\WebSocket\Server;
use Swoole\WebSocket\Frame;

$server = new Server("0.0.0.0", 9501);

$server->connections = [];

$server->on("open", function (Server $server, $request) {
    echo "新连接：{$request->fd}\n";
    $server->connections[$request->fd] = $request->fd;
});

$server->on("message", function (Server $server, Frame $frame) {
    $msg = $frame->data;
    foreach ($server->connections as $fd) {
        if ($server->isEstablished($fd)) {
            $data = [
                "type" => "system",
                "content" => $msg,
                "time" => time(),
            ];
            $backData = json_encode($data, true);
            $server->push($fd, $backData);
        }
    }
});

$server->on("close", function (Server $server, $fd) {
    unset($server->connections[$fd]);
});

echo "WebSocket 服务器启动在 ws://0.0.0.0:9501\n";
$server->start();
