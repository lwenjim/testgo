@echo off
set domain[-1]=http://10.27.6.27/
set domain[0]=http://192.168.50.154/
set "tempWorkData=D:\bin\bin\temp"
set "managerBin=AnonTokyoManage.exe"
set "nssmBin=nssm.exe"
set "atCbor=AnontokyoBuildCbor.exe"
set "siriusCbor=AnontokyoSiriusBuildCbor.exe"
set "atServer=AnonTokyoServer"
set "siriusServer=AnonTokyoSiriusServer"
setlocal enabledelayedexpansion

d:
if not exist "%tempWorkData%" (
    echo "%tempWorkData%"目录不存在，正在创建...
    mkdir "%tempWorkData%"  >nul 2>&1
    if %ERRORLEVEL% gtr 0 (
        echo 命令执行失败，错误码：%ERRORLEVEL%
        pause
        exit /b 100
    )
)

cd "%tempWorkData%"
if not exist "%managerBin%" (
    echo %managerBin%文件不存在，正在下载...
    call :download %managerBin%
    copy %managerBin% ..
)

if not exist "%nssmBin%" (
    echo %nssmBin%文件不存在，正在下载...
    call :download %nssmBin%
    copy %nssmBin% ..
)

cd ..
%managerBin% service daemon
if %ERRORLEVEL% gtr 0 (
    echo 命令执行失败，错误码：%ERRORLEVEL%
    pause
    exit /b 103
)
echo 恭喜你 安装成功!!!
pause
goto :eof

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
    exit /b 105

