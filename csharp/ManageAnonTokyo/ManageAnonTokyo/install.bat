@echo off
set "workdata=D:\bin\bin\temp"

d:
if not exist "%workdata%" (
    echo 目录不存在，正在创建...
    mkdir "%workdata%"
)

cd "%workdata%"
set "filename=AnonTokyoManage.exe"
if not exist "%filename%" (
    echo 文件不存在，正在下载...
    curl -s -L -o %filename% http://10.27.6.27/%filename%   
    echo AnonTokyoManage.exe 下载成功 !
)

cd ..
set "nssmpath=nssm.exe"
if not exist "%nssmpath%" (
    echo 文件不存在，正在下载...
    curl -s -L -o %nssmpath% http://10.27.6.27/%nssmpath%   
    echo nssm.exe 下载成功 !
)

cd "%workdata%"
%filename% service daemon
echo 恭喜你 安装成功!!!
pause