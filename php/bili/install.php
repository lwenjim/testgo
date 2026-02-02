<?php
set_time_limit(0);
$scriptPath = 'D:\workdata\golang\src\testgo\php\bili\start.ps1';
exec("powershell -ExecutionPolicy Bypass -File \"$scriptPath\"", $output, $returnCode);
echo json_encode($output);