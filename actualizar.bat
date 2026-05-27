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

set KEY_DEST=C:\ProgramData\gritsee\deploy_key
set CLONE_DIR=C:\PC-configuration

if not exist "%KEY_DEST%" (
    echo  ERROR: No se encontro la deploy key en %KEY_DEST%
    echo  Corre setup_completo.bat primero.
    pause & exit /b 1
)

if not exist "%CLONE_DIR%\.git" (
    echo  ERROR: El repo no existe en %CLONE_DIR%
    echo  Corre setup_completo.bat primero.
    pause & exit /b 1
)

set GIT_SSH_COMMAND=ssh -i "%KEY_DEST%" -o StrictHostKeyChecking=no
cd /d "%CLONE_DIR%"

echo  Descargando actualizaciones...
git pull

if errorlevel 1 (
    echo.
    echo  ERROR: No se pudo actualizar. Revisa tu conexion.
    pause & exit /b 1
)

echo.
echo  Proyecto actualizado correctamente.
echo  Los cambios estan en: %CLONE_DIR%
echo.
pause
