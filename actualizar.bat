@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Gritsee - Actualizar Pipeline

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set CLONE_DIR=C:\PC-configuration
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
echo  Este script actualiza el codigo del pipeline sin tocar:
echo    - Tareas programadas existentes
echo    - Configuracion de camara (qualityrun.bat)
echo    - location_slug.txt
echo    - google_key.json
echo.
echo  Presiona cualquier tecla para continuar...
pause >nul

:: =====================================================
::  1/3 — Git pull
:: =====================================================
echo  [1/3]  Descargando actualizaciones de GitHub...
echo [PASO 1/3] git pull >> "%LOG_FILE%"

if not exist "%CLONE_DIR%\.git" (
    echo  ERROR: El repo no esta en %CLONE_DIR%
    echo  Clona primero con:
    echo    git clone https://github.com/dleon-1022/PC-configuration.git C:\PC-configuration
    echo [ERROR] Repo no encontrado en %CLONE_DIR% >> "%LOG_FILE%"
    pause & exit /b 1
)

cd /d "%CLONE_DIR%"
git pull >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  ERROR: No se pudo descargar desde GitHub.
    echo  Verifica que el repo sea publico y haya internet.
    echo [ERROR] git pull fallo >> "%LOG_FILE%"
    pause & exit /b 1
)
echo         GitHub  [OK]
echo [OK] git pull completado >> "%LOG_FILE%"

:: =====================================================
::  2/3 — Sincronizar archivos del pipeline
::         Protegiendo archivos locales de cada PC
:: =====================================================
echo  [2/3]  Sincronizando archivos del pipeline...
echo [PASO 2/3] Sincronizando archivos >> "%LOG_FILE%"

if not exist "%PIPELINE_DIR%" mkdir "%PIPELINE_DIR%"

:: Hacer backup de archivos locales que NO deben sobreescribirse
if exist "%PIPELINE_DIR%\location_slug.txt" (
    copy /Y "%PIPELINE_DIR%\location_slug.txt" "%TEMP%\gritsee_slug_bak.txt" >nul
    echo [INFO] Backup de location_slug.txt hecho >> "%LOG_FILE%"
)
:: google_key.json NO viene en el repo (esta en .gitignore), no hace falta backup

:: Copiar archivos nuevos del pipeline
xcopy /E /I /Y "%CLONE_DIR%\pizza_pipeline\*" "%PIPELINE_DIR%\" >> "%LOG_FILE%" 2>&1
echo [OK] Archivos copiados a %PIPELINE_DIR% >> "%LOG_FILE%"

:: Restaurar location_slug.txt local (cada PC tiene el suyo)
if exist "%TEMP%\gritsee_slug_bak.txt" (
    copy /Y "%TEMP%\gritsee_slug_bak.txt" "%PIPELINE_DIR%\location_slug.txt" >nul
    del "%TEMP%\gritsee_slug_bak.txt" >nul
    echo [INFO] location_slug.txt restaurado >> "%LOG_FILE%"
)

:: Asegurar que existan las carpetas de runtime
mkdir "%PIPELINE_DIR%\frames"          2>nul
mkdir "%PIPELINE_DIR%\cropped_frames"  2>nul
mkdir "%PIPELINE_DIR%\selected_frames" 2>nul

echo         Archivos del pipeline  [OK]

:: =====================================================
::  3/3 — Actualizar dependencias Python y Node.js
:: =====================================================
echo  [3/3]  Actualizando dependencias...
echo [PASO 3/3] Dependencias >> "%LOG_FILE%"

python -m pip install -r "%PIPELINE_DIR%\requirements.txt" -q >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Python no se actualizaron.
    echo         Revisa el log para ver el detalle.
    echo [WARN] pip install con errores >> "%LOG_FILE%"
) else (
    echo         Dependencias Python  [OK]
    echo [OK] pip install completado >> "%LOG_FILE%"
)

cd /d "%PIPELINE_DIR%"
call npm install >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Node.js no se actualizaron.
    echo [WARN] npm install con errores >> "%LOG_FILE%"
) else (
    echo         Dependencias Node.js  [OK]
    echo [OK] npm install completado >> "%LOG_FILE%"
)

echo [FIN] Actualizacion completada %date% %time% >> "%LOG_FILE%"

echo.
echo  =============================================================
echo         ACTUALIZACION COMPLETADA
echo  =============================================================
echo.
echo  Cambios aplicados:
echo    - Codigo del pipeline actualizado
echo    - Dependencias actualizadas (incluyendo ultralytics para el crop)
echo.
echo  Sin cambios:
echo    - Tareas programadas intactas
echo    - qualityrun.bat (camara) intacto
echo    - location_slug.txt intacto
echo    - google_key.json intacto
echo.
echo  Log completo en: %LOG_FILE%
echo.
pause
exit /b 0
