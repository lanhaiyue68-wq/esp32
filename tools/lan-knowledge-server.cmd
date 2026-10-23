@echo off
rem Lan Agent 电脑端知识库服务：双击运行；要换文件夹就把路径拖到本文件上，或改下面的默认路径。
chcp 65001 >nul
set "DIR=%~1"
if "%DIR%"=="" set "DIR=E:\桌面\小蓝知识库"
py -3.12 "%~dp0lan-knowledge-server.py" --dir "%DIR%"
pause
