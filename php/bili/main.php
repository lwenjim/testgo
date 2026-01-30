<?php
$response = [];
$writer = function () use (&$response) {
    echo json_encode($response);
    die();
};

$result = [
    "code" => 200,
    "message" => "",
];
$result_code = 0;

exec("sc query AnonTokyoServer", $result, $result_code);
if (empty($result)) {
    $response["code"] = 500;
    $response["message"] = "failed to start";
    $writer();
}
if (stripos($result[3], "RUNNING") > -1) {
    exec("sc stop AnonTokyoServer", $result, $result_code);
    if (empty($result) || false === stripos($result[3], "STOP_PENDING")) {
        $response["code"] = 500;
        $response["message"] = "failed to stop";
        $writer();
    }
}

$downfile = "anontokyo_server.exe";
$downfile = 'web.config';
$binPath = "D:\bin\bin\\$downfile";
$logPath = "D:\bin\bin\anontokyo_server.log";
if (file_exists($binPath)) {
    if (!unlink($binPath)) {
        $response["code"] = 500;
        $response["message"] = "failed to delete $downfile";
        $writer();
    }
}
if (file_exists($logPath)) {
    if (unlink($logPath)) {
        $response["code"] = 500;
        $response["message"] = "failed to delete $logPath";
        $writer();
    }
}
// 10.27.6.25:8080
// 10.27.84.7
$data = file_get_contents("http://10.27.6.25:8080/anontokyo_server.exe");
// $data = file_get_contents("https://www.baidu.com");
$result = file_put_contents($binPath, $data);
if ($result === false) {
    $response["code"] = 500;
    $response["message"] = "failed to download file";
    $writer();
}

$handler = fopen($binPath, 'r', false);
if (false === fgetc($handler)) {
    $response["code"] = 500;
    $response["message"] = "failed to download file";
    $writer();
}

exec("sc query AnonTokyoServer", $result, $result_code);
if (empty($result)) {
    $response["code"] = 500;
    $response["message"] = "failed to start";
    $writer();
}

if (stripos($result[3], "RUNNING")>-1) {
    exec("sc start AnonTokyoServer", $result, result_code: $result_code);
    if (empty($result) || $result[2] == "An instance of the service is already running." || false === stripos($result[3], "START_PENDING")) {
        $response["code"] = 500;
        $response["message"] = "failed to start";
        $writer();
    }
}

$writer();