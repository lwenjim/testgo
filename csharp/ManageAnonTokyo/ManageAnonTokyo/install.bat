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
setlocal enabledelayedexpansion

d:
if not exist "%tempWorkData%" (
    echo "%tempWorkData%"目录不存在，正在创建...
    mkdir "%tempWorkData%"  >nul 2>&1
    call :check_error 100 "创建目录 %tempWorkData% 失败"
)

cd "%tempWorkData%"
call :check_error 101 "切换到目录 %tempWorkData% 失败"

if not exist "%managerBin%" (
    echo %managerBin%文件不存在，正在下载...
    call :download %managerBin%
    call :check_error 102 "下载 %managerBin% 失败"
    copy "%managerBin%" .. >nul 2>&1
    call :check_error 103 "复制 %managerBin% 到上级目录失败"
)

if not exist "%nssmBin%" (
    echo %nssmBin%文件不存在，正在下载...
    call :download %nssmBin%
    call :check_error 104 "下载 %nssmBin% 失败"
    copy "%nssmBin%" .. >nul 2>&1
    call :check_error 105 "复制 %nssmBin% 到上级目录失败"
)

cd ..
call :check_error 106 "切换到上级目录失败"

"%managerBin%" service daemon
call :check_error 103 "执行 %managerBin% service daemon 失败"

echo 恭喜你 安装成功!!!
pause
goto :eof

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

:check_error
rem %1 = exit code to return, %2 = message
if %ERRORLEVEL% equ 0 exit /b 0
echo %~2 错误码：%ERRORLEVEL%
pause
exit /b %~1

