<?php

use Swoole\WebSocket\Server;
use Swoole\WebSocket\Frame;

$server = new Server("0.0.0.0", 9501);

// 用户列表：fd => nickname（使用独立变量避免动态属性警告）
$users = [];

// 广播消息函数
function broadcast(Server $server, &$users, $data)
{
    $jsonData = json_encode($data, JSON_UNESCAPED_UNICODE);
    foreach ($users as $fd => $nickname) {
        if ($server->isEstablished($fd)) {
            $server->push($fd, $jsonData);
        }
    }
}

$server->on("open", function (Server $server, $request) use (&$users) {
    $fd = $request->fd;
    $users[$fd] = "用户{$fd}";
    echo "新连接：{$fd}，默认昵称：{$users[$fd]}\n";

    // 通知所有用户有人加入
    broadcast($server, $users, [
        "type" => "system",
        "content" => "{$users[$fd]} 加入了聊天室",
        "time" => date('H:i:s'),
        "online" => count($users)
    ]);
});

$server->on("message", function (Server $server, Frame $frame) use (&$users) {
    $fd = $frame->fd;
    $msg = $frame->data;

    // 解析消息
    $data = json_decode($msg, true);

    if ($data && isset($data['action'])) {
        // 处理命令
        switch ($data['action']) {
            case 'login':
                // 设置昵称
                $oldName = $users[$fd];
                $newName = $data['name'] ?: "用户{$fd}";
                $users[$fd] = $newName;
                broadcast($server, $users, [
                    "type" => "system",
                    "content" => "{$oldName} 改名为 {$newName}",
                    "time" => date('H:i:s'),
                    "online" => count($users)
                ]);
                break;

            case 'message':
                // 普通消息
                broadcast($server, $users, [
                    "type" => "message",
                    "from" => $users[$fd],
                    "content" => $data['content'],
                    "time" => date('H:i:s'),
                    "online" => count($users)
                ]);
                break;
        }
    } else {
        // 兼容旧格式，直接发送消息
        broadcast($server, $users, [
            "type" => "message",
            "from" => $users[$fd],
            "content" => $msg,
            "time" => date('H:i:s'),
            "online" => count($users)
        ]);
    }
});

$server->on("close", function (Server $server, $fd) use (&$users) {
    $nickname = $users[$fd] ?? "未知用户";
    unset($users[$fd]);
    echo "连接关闭：{$fd}\n";

    // 通知所有用户有人离开
    broadcast($server, $users, [
        "type" => "system",
        "content" => "{$nickname} 离开了聊天室",
        "time" => date('H:i:s'),
        "online" => count($users)
    ]);
});

echo "WebSocket 群聊服务器启动在 ws://0.0.0.0:9501\n";
echo "在线用户数：0\n";
$server->start();
