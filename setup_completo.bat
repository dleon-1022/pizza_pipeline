@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Gritsee - Instalacion Completa

:: =====================================================
::  VERIFICAR ADMINISTRADOR
:: =====================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set SCRIPT_DIR=%~dp0
set KEY_SRC=%SCRIPT_DIR%pizza_deploy_key
set KEY_DEST=C:\ProgramData\gritsee\deploy_key
set REPO_URL=git@github.com:dleon-1022/PC-configuration.git
set CLONE_DIR=C:\PC-configuration
set LOG_FILE=%USERPROFILE%\Desktop\gritsee_setup_completo.log

echo ============================================================ > "%LOG_FILE%"
echo  GRITSEE - SETUP COMPLETO >> "%LOG_FILE%"
echo  Fecha: %date%  Hora: %time% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"

cls
echo.
echo  =============================================================
echo         GRITSEE  -  INSTALACION COMPLETA
echo  =============================================================
echo.
echo  Este script hara todo automaticamente:
echo.
echo    [1]  Instalar Git
echo    [2]  Configurar acceso al repositorio
echo    [3]  Descargar el proyecto desde GitHub
echo    [4]  Instalar Python, Node.js, dependencias y tareas
echo.
echo  Solo necesitas el archivo pizza_deploy_key
echo  en la misma carpeta que este script.
echo.
echo  Presiona cualquier tecla para comenzar...
pause >nul

:: =====================================================
::  VERIFICAR DEPLOY KEY
:: =====================================================
if not exist "%KEY_SRC%" (
    echo.
    echo  ERROR: No se encontro el archivo pizza_deploy_key
    echo  Debe estar en la misma carpeta que este script.
    echo [ERROR] pizza_deploy_key no encontrado en: %KEY_SRC% >> "%LOG_FILE%"
    pause & exit /b 1
)
echo [OK] Deploy key encontrada >> "%LOG_FILE%"

echo.
echo  =============================================================
echo.

:: =====================================================
::  1 — Instalar Git
:: =====================================================
echo  [1/4]  Verificando Git...
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo         Git no encontrado. Instalando...
    echo [INFO] Instalando Git via winget >> "%LOG_FILE%"
    winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements >> "%LOG_FILE%" 2>&1
    :: Refrescar PATH
    for /f "skip=2 tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYS_PATH=%%b"
    if defined SYS_PATH set "PATH=%SYS_PATH%;%PATH%"
    echo         Git instalado  [OK]
    echo [OK] Git instalado >> "%LOG_FILE%"
) else (
    echo         Git ya instalado  [OK]
    echo [OK] Git ya presente >> "%LOG_FILE%"
)
echo.

:: =====================================================
::  2 — Configurar deploy key
:: =====================================================
echo  [2/4]  Configurando acceso al repositorio...
if not exist "C:\ProgramData\gritsee" mkdir "C:\ProgramData\gritsee"
copy /Y "%KEY_SRC%" "%KEY_DEST%" >nul 2>&1

:: Permisos: solo SYSTEM y Administrators pueden leerla
icacls "%KEY_DEST%" /inheritance:r /grant:r "SYSTEM:(R)" /grant:r "Administrators:(R)" >nul 2>&1

echo         Deploy key configurada  [OK]
echo [OK] Deploy key copiada a %KEY_DEST% >> "%LOG_FILE%"
echo.

:: =====================================================
::  3 — Clonar o actualizar el repo
:: =====================================================
echo  [3/4]  Descargando proyecto desde GitHub...
set GIT_SSH_COMMAND=ssh -i "%KEY_DEST%" -o StrictHostKeyChecking=no

if exist "%CLONE_DIR%\.git" (
    echo         Repo ya existe — actualizando...
    cd /d "%CLONE_DIR%"
    git pull >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        echo  ERROR: No se pudo actualizar el repositorio.
        echo [ERROR] git pull fallo >> "%LOG_FILE%"
        goto :error
    )
    echo         Repositorio actualizado  [OK]
    echo [OK] git pull completado >> "%LOG_FILE%"
) else (
    git clone "%REPO_URL%" "%CLONE_DIR%" >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        echo  ERROR: No se pudo clonar el repositorio.
        echo  Verifica que la deploy key este agregada en GitHub.
        echo [ERROR] git clone fallo >> "%LOG_FILE%"
        goto :error
    )
    echo         Repositorio clonado  [OK]
    echo [OK] git clone completado >> "%LOG_FILE%"
)
echo.

:: Guardar key dest para que git pull futuro funcione
setx GRITSEE_DEPLOY_KEY "%KEY_DEST%" /M >nul 2>&1

:: =====================================================
::  4 — Correr configuracion completa
:: =====================================================
echo  [4/4]  Iniciando configuracion del sistema...
echo [INFO] Llamando a configuracion.bat >> "%LOG_FILE%"
echo.
call "%CLONE_DIR%\configuracion.bat"

exit /b 0

:error
echo.
echo  =============================================================
echo         SE PRODUJO UN ERROR
echo  =============================================================
echo  Revisa el log: %LOG_FILE%
echo.
pause
exit /b 1
