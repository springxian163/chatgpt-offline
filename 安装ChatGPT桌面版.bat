@echo off
chcp 65001 >nul 2>&1
setlocal enabledelayedexpansion
title Install ChatGPT Desktop

rem ---- require administrator; re-launch elevated (forwarding arguments) ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    if "%~1"=="" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs" >nul 2>&1
    )
    if !errorlevel! neq 0 (
        echo.
        echo [X] Elevation was cancelled or failed.
        echo     Right-click this file and choose "Run as administrator".
        echo.
        pause
    )
    exit /b
)

cd /d "%~dp0"

set "PS=powershell"
where pwsh >nul 2>&1 && set "PS=pwsh"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-chatgpt-desktop.ps1" %*
set "RC=%errorlevel%"
endlocal & exit /b %RC%
