@echo off
setlocal
chcp 65001 >nul 2>&1
title Gritsee - Pizza Quality

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

set SCRIPT_DIR=%~dp0
set CONFIG_PS=%SCRIPT_DIR%configure_pipeline.ps1

if not exist "%CONFIG_PS%" (
    echo ERROR: No se encontro "%CONFIG_PS%".
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%CONFIG_PS%" %*
set EXIT_CODE=%ERRORLEVEL%

if not "%~1"=="/auto" (
    echo.
    pause
)

exit /b %EXIT_CODE%
