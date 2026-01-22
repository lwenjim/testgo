<?php

use Swoole\Coroutine\Http\Client;
use function Swoole\Coroutine\run;

run(function () {
    $cli = new Client('localhost', 9502);
    $cli->get('/');
    echo $cli->body;
    $cli->close();
});
