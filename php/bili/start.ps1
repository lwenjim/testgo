

Set-Variable -Name "Service_Name" -Value AnonTokyoServer -Option ReadOnly -Scope Script
$startTime = Get-Date
function response {
    param (
        [int]$code = 500,
        [string]$message = "error"
    )
    $response = @{
        "code"    = $code
        "message" = $message
        "interval" = ((Get-Date)-$startTime).TotalSeconds
    }
    $json = $response | ConvertTo-Json
    [System.IO.File]::WriteAllText("D:\\workdata\\testgo\\php\\bili\\data.log", $json)
    Write-Host $json
}

function Wait-ForServiceState {
    param(
        [System.ServiceProcess.ServiceControllerStatus]$DesiredState,
        [int]$Timeout = 30
    )
    $service = Get-Service -Name $Service_Name
    $elapsed = 0
    $interval = 1
    while ($service.Status -ne $DesiredState -and $elapsed -lt $Timeout) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $service.Refresh()
    }
    return $service.Status -eq $DesiredState
}

function Update-Server {
    [OutputType([bool])]
    param (
        [bool]$isStart
    )
    if ( !$isStart ) {
        Stop-Service -Name $Service_Name
        return Wait-ForServiceState -ServiceName $Service_Name -DesiredState Stopped -Timeout 30
    }
    else {
        Start-Service -Name $Service_Name -WarningAction SilentlyContinue
        return Wait-ForServiceState -ServiceName $Service_Name -DesiredState Running -Timeout 30
    }
}

function main(){
    if ( (Get-Service -Name $Service_Name).Status -eq "Running" ) {
        if (!(Update-Server -serviceName $Service_Name -isStart $false)){
            response -message "Service failed to stop within the timeout."
            return
        }
    }
    $binPath = "D:\\bin\\bin\\anontokyo_server.exe";
    if ([System.IO.File]::Exists($binPath)) {
        [System.IO.File]::Delete($binPath)
    }
    $filename = [System.IO.Path]::GetFileNameWithoutExtension($binPath)
    $logPath = "D:\\bin\\bin\\$filename.log"
    if (![System.IO.File]::Exists($logPath)){
        [System.IO.File]::WriteAllText($logPath, "ok")
    }
    Invoke-WebRequest -Uri "http://10.27.84.42/$filename.exe" -OutFile $binPath
    if ( (Get-Service -Name $Service_Name).Status -eq "Stopped" ) {
        if (!(Update-Server -serviceName $Service_Name -isStart $true)) {
            response -message "Service failed to start within the timeout."
            return
        }
    }
    response -code 200 -message "Service update successfully."
}

main