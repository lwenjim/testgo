@echo off
set domain[0]=http://10.27.6.27/
set domain[1]=http://192.168.50.154/
set "tempWorkData=D:\bin\bin\temp"
set "managerBin=AnonTokyoManage.exe"
set "nssmBin=nssm.exe"
set "atCbor=AnontokyoBuildCbor.exe"
set "siriusCbor=AnontokyoSiriusBuildCbor.exe"
set "atServer=AnonTokyoServer"
set "siriusServer=AnonTokyoSiriusServer"
set "masterData=sirius_master_data"
setlocal enabledelayedexpansion

d:
@cd %tempWorkData%
@cd ..
if not exist "%masterData%" (
    echo %masterData%文件夹不存在, 请拉去配表仓库
    pause
    exit /b 106
)

@cd %tempWorkData%
if not exist "%tempWorkData%" (
    echo "%tempWorkData%"目录不存在，正在创建...
    mkdir "%tempWorkData%"  >nul 2>&1
    if %ERRORLEVEL% gtr 0 (
        echo 命令执行失败，错误码：%ERRORLEVEL%
        pause
        exit /b 100
    )
)

if not exist "%atCbor%" (
    echo %atCbor%文件不存在，正在下载...
    @call :download %atCbor%
    @copy %atCbor% ..
)

echo 开始打包AT小游戏配表...
echo 确保 %atServer% 已运行...
call :ensure_running "%atServer%" 30
if %ERRORLEVEL% neq 0 (
    echo 无法使服务 %atServer% 运行，错误码：%ERRORLEVEL%
    pause
    exit /b 103
)

echo 停止 %atServer%...
net stop "%atServer%"
if %ERRORLEVEL% gtr 0 (
    echo 停止服务 %atServer% 失败，错误码：%ERRORLEVEL%
    pause
    exit /b 103
)

echo 运行打包工具1...
@cd %tempWorkData%
cd ..
%atCbor%
if %ERRORLEVEL% gtr 0 (
    echo 打包工具执行失败，错误码：%ERRORLEVEL%
    pause
    exit /b 103
)

echo 确保 %atServer% 已停止（若未停止则尝试停止）...
call :ensure_stopped "%atServer%" 30
if %ERRORLEVEL% neq 0 (
    echo 无法使服务 %atServer% 停止，错误码：%ERRORLEVEL%
    pause
    exit /b 103
)

echo 启动 %atServer%...
net start "%atServer%"
if %ERRORLEVEL% gtr 0 (
    echo 启动服务 %atServer% 失败，错误码：%ERRORLEVEL%
    pause
    exit /b 103
)
echo AT小游戏配表打包完成.

if not exist "%siriusCbor%" (
    echo %siriusCbor%文件不存在，正在下载...
    @call :download %siriusCbor%
    @copy %siriusCbor% ..
)

echo 开始打包主游戏配表...
echo 确保 %siriusServer% 已运行...
call :ensure_running "%siriusServer%" 30
if %ERRORLEVEL% neq 0 (
    echo 无法使服务 %siriusServer% 运行，错误码：%ERRORLEVEL%
    pause
    exit /b 104
)

echo 停止 %siriusServer%...
net stop "%siriusServer%"
if %ERRORLEVEL% gtr 0 (
    echo 停止服务 %siriusServer% 失败，错误码：%ERRORLEVEL%
    pause
    exit /b 104
)

echo 运行打包工具2...
%siriusCbor%
if %ERRORLEVEL% gtr 0 (
    echo 打包工具执行失败，错误码：%ERRORLEVEL%
    pause
    exit /b 104
)

echo 确保 %siriusServer% 已停止（若未停止则尝试停止）...
call :ensure_stopped "%siriusServer%" 30
if %ERRORLEVEL% neq 0 (
    echo 无法使服务 %siriusServer% 停止，错误码：%ERRORLEVEL%
    pause
    exit /b 104
)

echo 启动 %siriusServer%...
net start "%siriusServer%"
if %ERRORLEVEL% gtr 0 (
    echo 启动服务 %siriusServer% 失败，错误码：%ERRORLEVEL%
    pause
    exit /b 104
)
echo 主游戏配表打包完成.

echo 配表已重新加载
pause
goto :eof

:ensure_running
rem ensure_running %1=serviceName %2=timeoutSeconds
set "svc=%~1"
set "timeoutSec=%~2"
rem If already running, return success
sc query "%svc%" | findstr /I "RUNNING" >nul
if %ERRORLEVEL% equ 0 exit /b 0

echo 服务 %svc% 未在运行，正在尝试启动...
net start "%svc%" >nul 2>&1
if %ERRORLEVEL% gtr 0 (
    echo 启动命令失败，错误码：%ERRORLEVEL%
    exit /b 1
)

call :wait_for_status "%svc%" "RUNNING" %timeoutSec%
exit /b %ERRORLEVEL%

:ensure_stopped
rem ensure_stopped %1=serviceName %2=timeoutSeconds
set "svc=%~1"
set "timeoutSec=%~2"
rem If already stopped, return success
sc query "%svc%" | findstr /I "STOPPED" >nul
if %ERRORLEVEL% equ 0 exit /b 0

echo 服务 %svc% 未停止，正在尝试停止...
net stop "%svc%" >nul 2>&1
if %ERRORLEVEL% gtr 0 (
    echo 停止命令失败，错误码：%ERRORLEVEL%
    exit /b 2
)

call :wait_for_status "%svc%" "STOPPED" %timeoutSec%
exit /b %ERRORLEVEL%

:wait_for_status
rem wait_for_status %1=serviceName %2=expectedStatus %3=timeoutSeconds
set "svc=%~1"
set "expected=%~2"
set /a timeout=%~3
set /a elapsed=0

:wait_loop
sc query "%svc%" | findstr /I "%expected%" >nul
if %ERRORLEVEL% equ 0 (
    exit /b 0
)
if %elapsed% geq %timeout% (
    echo 等待服务 %svc% 达到状态 %expected% 超时 (%timeout% 秒)
    exit /b 3
)
timeout /T 1 /NOBREAK >nul
set /a elapsed+=1
goto :wait_loop

:download
    set count=2
    for /l %%i in (0,1,%count%-1) do (
        curl -s -L -o %1 !domain[%%i]!%1
        if %ERRORLEVEL% equ 0 (
            goto :dl_done
        )
        if %ERRORLEVEL% gtr 0 if %%i equ 1 (
            echo curl -s -L -o %1 !domain[%%i]!%1
            echo 命令执行失败，错误码：%ERRORLEVEL%
            pause
            exit /b 102
        )
    )
:dl_done
    exit /b 105
