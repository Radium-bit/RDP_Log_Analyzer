@echo off
chcp 65001 >nul
:: 检查管理员权限
@echo off
NET FILE >NUL 2>&1
IF %ERRORLEVEL% EQU 0 (
    PowerShell -ExecutionPolicy Bypass -Command "& { [Console]::InputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8; & '%~dp0SMB_Log_Analyzer.ps1' }"
    pause
) ELSE (
    echo 需要管理员权限才能运行此脚本！
    echo 请右键以管理员身份运行此批处理文件。
    pause
    exit /b 1
)