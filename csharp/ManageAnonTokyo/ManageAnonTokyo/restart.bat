@echo off
@set "workdata=D:\bin\bin"

@d:
@cd "%workdata%"

echo 开始打包配表...
@AnontokyoBuildCbor.exe
@net stop AnonTokyoServer
@net start AnonTokyoServer
echo 配表打包完成.


echo 开始重启服务...
@AnontokyoSiriusBuildCbor.exe
@net stop AnonTokyoSiriusServer
@net start AnonTokyoSiriusServer
echo 服务已重启.

pause
