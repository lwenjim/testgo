@echo off
@set "workdata=D:\bin\bin"

@d:
@cd "%workdata%"

@AnontokyoBuildCbor.exe
@net stop AnonTokyoServer
@net start AnonTokyoServer

@AnontokyoSiriusBuildCbor.exe
@net stop AnonTokyoSiriusServer
@net start AnonTokyoSiriusServer

echo 恭喜你 更新成功!!!
pause
