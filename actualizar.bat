@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Gritsee - Actualizar Pipeline

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set PIPELINE_DIR=C:\pizza_pipeline
set LOG_FILE=%USERPROFILE%\Desktop\gritsee_actualizacion.log

echo ============================================================ > "%LOG_FILE%"
echo  GRITSEE - LOG DE ACTUALIZACION >> "%LOG_FILE%"
echo  Fecha: %date%  Hora: %time% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"

cls
echo.
echo  =============================================================
echo         GRITSEE  -  ACTUALIZANDO PIPELINE
echo  =============================================================
echo.
echo  Actualiza el codigo sin tocar:
echo    - Tareas programadas
echo    - Camara (qualityrun.bat)
echo    - location_slug.txt
echo    - google_key.json
echo.

if not exist "%PIPELINE_DIR%\.git" (
    echo  ERROR: El repo no existe en %PIPELINE_DIR%
    echo  Para instalar desde cero ejecuta:
    echo    git clone https://github.com/dleon-1022/PC-configuration.git C:\pizza_pipeline
    echo    C:\pizza_pipeline\configuracion.bat
    echo [ERROR] Repo no encontrado >> "%LOG_FILE%"
    pause & exit /b 1
)

:: 1. Git pull
echo  [1/2]  Descargando actualizaciones...
cd /d "%PIPELINE_DIR%"
git pull >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  ERROR: No se pudo actualizar desde GitHub.
    echo  Verifica la conexion a internet.
    echo [ERROR] git pull fallo >> "%LOG_FILE%"
    pause & exit /b 1
)
echo         GitHub  [OK]
echo [OK] git pull completado >> "%LOG_FILE%"

:: 2. Actualizar dependencias (por si hay nuevos paquetes)
echo  [2/2]  Actualizando dependencias...

python -m pip install -r "%PIPELINE_DIR%\requirements.txt" -q >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Python no se actualizaron.
    echo [WARN] pip con errores >> "%LOG_FILE%"
) else (
    echo         Python  [OK]
    echo [OK] pip completado >> "%LOG_FILE%"
)

call npm install >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Node.js no se actualizaron.
    echo [WARN] npm con errores >> "%LOG_FILE%"
) else (
    echo         Node.js  [OK]
    echo [OK] npm completado >> "%LOG_FILE%"
)

echo [FIN] Actualizacion completada %date% %time% >> "%LOG_FILE%"

echo.
echo  =============================================================
echo         ACTUALIZACION COMPLETADA
echo  =============================================================
echo.
echo  Log en: %LOG_FILE%
echo.
pause
exit /b 0
