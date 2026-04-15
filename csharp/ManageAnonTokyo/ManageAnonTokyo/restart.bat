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

@cd %tempWorkData%
@cd ..

if not exist "%atCbor%" (
    echo %atCbor%文件不存在，正在下载...
    @call :download %atCbor%
    @copy %atCbor% ..
)

echo 开始打包AT小游戏配表...
@net stop %atServer% && %atCbor% && net start %atServer%
if %ERRORLEVEL% gtr 0 (
    echo 命令执行失败，错误码：%ERRORLEVEL%
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
@net stop %siriusServer% && %siriusCbor% && net start %siriusServer%
if %ERRORLEVEL% gtr 0 (
    echo 命令执行失败，错误码：%ERRORLEVEL%
    pause
    exit /b 104
)
echo 主游戏配表打包完成.

echo 配表已重新加载
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
