<?php
$response = [];
$writer = function () use (&$response) {
    echo json_encode($response);
    die();
};
$serviceName = "testgo";
$result = [
    "code" => 200,
    "message" => "",
];
$result_code = 0;

exec("sc query $serviceName", $result, $result_code);
if (empty($result)) {
    $response["code"] = 500;
    $response["message"] = "failed to start";
    $writer();
}
if (stripos($result[3], "RUNNING") > -1) {
    exec("sc stop $serviceName", $result, $result_code);
    if (empty($result) || false === stripos($result[3], "STOP_PENDING")) {
        $response["code"] = 500;
        $response["message"] = "failed to stop";
        $writer();
    }
}
$binPath = "D:\\bin\bin\\testgo.exe";
$filename = pathinfo($binPath, PATHINFO_BASENAME);
if (file_exists($binPath)) {
    if (!unlink($binPath)) {
        $response["code"] = 500;
        $response["message"] = "failed to delete $downfile";
        $writer();
    }
}
$logPath = "D:\\bin\\bin\\" . pathinfo($binPath, PATHINFO_FILENAME) . ".log";
if (file_exists($logPath)) {
    if (!file_put_contents($logPath, "123")) {
        $response["code"] = 500;
        $response["message"] = "failed to delete $logPath";
        $writer();
    }
} else {
    touch($logPath);
}
// 10.27.6.25:8080
// 10.27.84.7
// 192.168.50.157:8080
$data = file_get_contents("http://192.168.50.157:8080/$filename");
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

exec("sc query $serviceName", $result, $result_code);
if (empty($result)) {
    $response["code"] = 500;
    $response["message"] = "failed to start";
    $writer();
}

if (stripos($result[3], "STOPPED") > -1) {
    exec("sc start $serviceName", $result, result_code: $result_code);
    if (empty($result) || $result[2] == "An instance of the service is already running." || false === stripos($result[3], "START_PENDING")) {
        $response["code"] = 500;
        $response["message"] = "failed to start";
        $writer();
    }
}

$writer();