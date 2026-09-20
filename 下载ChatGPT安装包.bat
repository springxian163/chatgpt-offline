@echo off
chcp 65001 >nul 2>&1
setlocal
title Download ChatGPT MSIX

cd /d "%~dp0"

set "PS=powershell"
where pwsh >nul 2>&1 && set "PS=pwsh"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\download-chatgpt-msix.ps1" %*
set "RC=%errorlevel%"
endlocal & exit /b %RC%
