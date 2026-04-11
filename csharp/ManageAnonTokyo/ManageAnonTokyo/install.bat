@echo off
set domain[0]=http://10.27.6.27/
set domain[1]=http://192.168.50.154/
set "workdata=D:\bin\bin\temp"
set "filename=AnonTokyoManage.exe"
set "nssmpath=nssm.exe"
setlocal enabledelayedexpansion

d:
if not exist "%workdata%" (
    echo 目录不存在，正在创建...
    mkdir "%workdata%"  >nul 2>&1
    if %ERRORLEVEL% gtr 0 (
        echo 命令执行失败，错误码：%ERRORLEVEL%
        pause
        exit /b 100
    )
)

cd "%workdata%"
if not exist "%filename%" (
    echo %filename%文件不存在，正在下载...
    call :download %filename%
    copy %filename% ..
)

if not exist "%nssmpath%" (
    echo %nssmpath%文件不存在，正在下载...
    call :download %nssmpath%
    copy %nssmpath% ..
)

cd "%workdata%"
%filename% service daemon
if %ERRORLEVEL% gtr 0 (
    echo 命令执行失败，错误码：%ERRORLEVEL%
    pause
    exit /b 103
)
echo 恭喜你 安装成功!!!
pause

:download
    set count=2
    for /l %%i in (0,1,%count%-1) do (
        curl -s -L -o %1 !domain[%%i]!%1
        if %ERRORLEVEL% equ 0 (
            break
        )
        if %ERRORLEVEL% gtr 0 if %%i equ 1 (
            echo curl -s -L -o %1 !domain[%%i]!%1
            echo 命令执行失败，错误码：%ERRORLEVEL%
            pause
            exit /b 102
        )
    )
    exit /b
