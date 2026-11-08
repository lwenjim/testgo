<?php

use Swoole\Coroutine\Http\Client;
use function Swoole\Coroutine\run;

run(function () {
    // 使用 Swoole Table 实现协程间共享变量（比普通变量更可靠）
    $table = new Swoole\Table(1);
    $table->column('isClosed', Swoole\Table::TYPE_INT, 1);
    $table->create();
    $table->set('status', ['isClosed' => 0]);

    $cli = new Client('localhost', 9501);

    // 升级到 WebSocket 协议
    $ret = $cli->upgrade('/');
    if (!$ret) {
        echo "WebSocket 握手失败: " . $cli->errCode . "\n";
        return;
    }

    echo "=== WebSocket 群聊客户端 ===\n";
    flush();
    echo "连接成功！输入消息发送（输入 exit 退出）\n";
    flush();

    // 设置昵称
    echo "请输入您的昵称：";
    $nickname = trim(fgets(STDIN));
    flush();
    if ($nickname) {
        $cli->push(json_encode([
            'action' => 'login',
            'name' => $nickname
        ]));
    }

    // 协程1：接收消息
    go(function () use ($cli, $table) {
        while (true) {
            $frame = $cli->recv();
            if (!$frame) {
                echo "\n连接已断开\n";
                flush();
                // 设置连接断开标志（使用 Table 确保协程间可见）
                $table->set('status', ['isClosed' => 1]);
                // 强制关闭客户端连接
                $cli->close(true);
                break;
            }

            $data = json_decode($frame->data, true);
            if ($data) {
                $time = $data['time'] ?? date('H:i:s');
                if ($data['type'] == 'system') {
                    $online = $data['online'] ?? '未知';
                    echo "\n[{$time}] [系统] {$data['content']} (在线: {$online})\n";
                } else if ($data['type'] == 'message') {
                    $from = $data['from'] ?? '未知';
                    echo "\n[{$time}] {$from}: {$data['content']}\n";
                }
            } else {
                echo "\n[收到] {$frame->data}\n";
            }
            echo "> ";
            flush();
        }
    });

    // 协程2：发送消息
    go(function () use ($cli, $table) {
        // 设置 STDIN 为非阻塞模式
        stream_set_blocking(STDIN, false);

        while (true) {
            // 检查连接是否已断开（使用 Table 读取状态）
            $status = $table->get('status');
            if ($status && $status['isClosed'] == 1) {
                echo "\n连接已断开，退出客户端\n";
                $cli->close(true);
                break;
            }

            echo "> ";
            flush();

            // 非阻塞读取输入
            $msg = '';
            $startTime = microtime(true);
            while (microtime(true) - $startTime < 0.1) {
                // 再次检查连接状态（防止读取过程中连接断开）
                $status = $table->get('status');
                if ($status && $status['isClosed'] == 1) {
                    echo "\n连接已断开，退出客户端\n";
                    $cli->close(true);
                    return; // 直接返回退出协程
                }

                $char = fgetc(STDIN);
                if ($char === false) {
                    usleep(10000);
                    continue;
                }
                if ($char === "\n") {
                    break;
                }
                $msg .= $char;
            }

            $msg = trim($msg);

            if ($msg === 'exit') {
                echo "退出群聊\n";
                $table->set('status', ['isClosed' => 1]);
                $cli->close(true);
                break;
            }

            if ($msg) {
                $cli->push(json_encode([
                    'action' => 'message',
                    'content' => $msg
                ]));
            }
        }
    });
});
