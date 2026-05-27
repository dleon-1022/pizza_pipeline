@echo off
chcp 65001 >nul 2>&1
title Gritsee - Actualizar

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo.
echo  =============================================================
echo         GRITSEE  -  ACTUALIZANDO PROYECTO
echo  =============================================================
echo.

set CLONE_DIR=C:\PC-configuration
set KEY_DEST=C:\ProgramData\gritsee\deploy_key

if not exist "%CLONE_DIR%\.git" (
    echo  ERROR: El repo no existe en %CLONE_DIR%
    echo  Corre bootstrap.ps1 primero via AnyDesk.
    pause & exit /b 1
)

if not exist "%KEY_DEST%" (
    echo  ERROR: No se encontro la deploy key en %KEY_DEST%
    echo  Corre bootstrap.ps1 primero via AnyDesk.
    pause & exit /b 1
)

set GIT_SSH_COMMAND=ssh -i "%KEY_DEST%" -o StrictHostKeyChecking=no

echo  Descargando actualizaciones...
cd /d "%CLONE_DIR%"
git pull

if errorlevel 1 (
    echo.
    echo  ERROR: No se pudo actualizar.
    echo  Si expiro el token, vuelve a correr bootstrap.ps1
    pause & exit /b 1
)

echo.
echo  Proyecto actualizado correctamente.
echo.
pause
