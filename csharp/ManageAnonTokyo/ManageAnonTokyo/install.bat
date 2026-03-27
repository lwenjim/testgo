@echo off
set "workdata=d:\"

if not exist "%workdata%" (
    echo 目录不存在，正在创建...
    mkdir "%workdata%"
)

cd "%workdata%"
set "filename=AnonTokyoManage.exe"
if not exist "%filename%" (
    echo 文件不存在，正在下载...
    curl -L -o %filename% http://10.27.84.42/%filename%   
    echo 目录创建成功
)

%filename% service daemon
echo 恭喜你 安装成功!!!
pause