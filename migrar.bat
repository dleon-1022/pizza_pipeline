@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Gritsee - Migracion a nueva estructura

:: =====================================================
::  SCRIPT DE MIGRACION - Ejecutar UNA SOLA VEZ
::  Convierte la estructura antigua:
::    C:\PC-configuration\  (repo)
::    C:\pizza_pipeline\    (copia de archivos)
::  A la nueva estructura:
::    C:\pizza_pipeline\    (= el repo directamente)
::
::  Conserva: google_key.json, location_slug.txt,
::            qualityrun.bat y tareas programadas
:: =====================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set OLD_REPO=C:\PC-configuration
set PIPELINE=C:\pizza_pipeline
set BACKUP=%TEMP%\gritsee_migracion_backup
set LOG_FILE=%USERPROFILE%\Desktop\gritsee_migracion.log

mkdir "%BACKUP%" 2>nul

echo ============================================================ > "%LOG_FILE%"
echo  GRITSEE - MIGRACION >> "%LOG_FILE%"
echo  Fecha: %date%  Hora: %time% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"

cls
echo.
echo  =============================================================
echo         GRITSEE  -  MIGRACION A NUEVA ESTRUCTURA
echo  =============================================================
echo.
echo  Este script reorganiza la instalacion:
echo    Antes: C:\PC-configuration + C:\pizza_pipeline (separados)
echo    Ahora: C:\pizza_pipeline (el repo directamente)
echo.
echo  Se conservaran: google_key.json, location_slug.txt,
echo                  qualityrun.bat y tareas programadas
echo.
echo  Presiona cualquier tecla para continuar...
pause >nul

:: Verificar que existe la instalacion antigua
if not exist "%OLD_REPO%\.git" (
    echo  No se encontro el repo antiguo en %OLD_REPO%
    echo  Quizas esta PC ya tiene la nueva estructura.
    echo  Si es nueva, usa configuracion.bat directamente.
    pause & exit /b 0
)

echo  [1/4]  Haciendo backup de archivos locales...
echo [PASO 1/4] Backup >> "%LOG_FILE%"

:: Backup google_key.json
if exist "%PIPELINE%\google_key.json" (
    copy /Y "%PIPELINE%\google_key.json" "%BACKUP%\google_key.json" >nul
    echo [OK] Backup google_key.json >> "%LOG_FILE%"
)

:: Backup location_slug.txt
if exist "%PIPELINE%\location_slug.txt" (
    copy /Y "%PIPELINE%\location_slug.txt" "%BACKUP%\location_slug.txt" >nul
    set /p SLUG=<"%PIPELINE%\location_slug.txt"
    echo [OK] Backup location_slug.txt (!SLUG!) >> "%LOG_FILE%"
)

:: Backup qualityrun.bat (tiene RTSP configurado)
if exist "C:\Users\gritseeuser1\Documents\qualityrun.bat" (
    copy /Y "C:\Users\gritseeuser1\Documents\qualityrun.bat" "%BACKUP%\qualityrun.bat" >nul
    echo [OK] Backup qualityrun.bat >> "%LOG_FILE%"
)

echo         Backup  [OK]

:: Actualizar repo antiguo
echo  [2/4]  Actualizando repo con ultima version...
echo [PASO 2/4] git pull >> "%LOG_FILE%"

cd /d "%OLD_REPO%"
git pull >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  AVISO: No se pudo hacer git pull. Continuando con version actual.
    echo [WARN] git pull fallo, continuando >> "%LOG_FILE%"
)
echo         Repo actualizado  [OK]

:: Reemplazar C:\pizza_pipeline con el contenido del repo
echo  [3/4]  Reemplazando pizza_pipeline con el repo...
echo [PASO 3/4] Reemplazar pipeline >> "%LOG_FILE%"

:: Borrar contenido actual de pizza_pipeline (excepto lo que ya backupeamos)
rd /s /q "%PIPELINE%" >> "%LOG_FILE%" 2>&1

:: Clonar el repo directamente a C:\pizza_pipeline
git clone https://github.com/dleon-1022/PC-configuration.git "%PIPELINE%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  ERROR: No se pudo clonar el repo en %PIPELINE%
    echo  Restaurando backup...
    mkdir "%PIPELINE%" 2>nul
    if exist "%BACKUP%\google_key.json"  copy /Y "%BACKUP%\google_key.json"  "%PIPELINE%\google_key.json" >nul
    if exist "%BACKUP%\location_slug.txt" copy /Y "%BACKUP%\location_slug.txt" "%PIPELINE%\location_slug.txt" >nul
    if exist "%BACKUP%\qualityrun.bat"   copy /Y "%BACKUP%\qualityrun.bat"   "C:\Users\gritseeuser1\Documents\qualityrun.bat" >nul
    echo [ERROR] Clone fallo - backup restaurado >> "%LOG_FILE%"
    pause & exit /b 1
)

echo         Clone  [OK]
echo [OK] Repo clonado en %PIPELINE% >> "%LOG_FILE%"

:: Crear carpetas de runtime
mkdir "%PIPELINE%\frames"          2>nul
mkdir "%PIPELINE%\cropped_frames"  2>nul
mkdir "%PIPELINE%\selected_frames" 2>nul

:: Restaurar archivos locales
echo  [4/4]  Restaurando configuracion local...
echo [PASO 4/4] Restaurar >> "%LOG_FILE%"

if exist "%BACKUP%\google_key.json" (
    copy /Y "%BACKUP%\google_key.json" "%PIPELINE%\google_key.json" >nul
    echo [OK] google_key.json restaurado >> "%LOG_FILE%"
)

if exist "%BACKUP%\location_slug.txt" (
    copy /Y "%BACKUP%\location_slug.txt" "%PIPELINE%\location_slug.txt" >nul
    echo [OK] location_slug.txt restaurado >> "%LOG_FILE%"
)

if exist "%BACKUP%\qualityrun.bat" (
    copy /Y "%BACKUP%\qualityrun.bat" "C:\Users\gritseeuser1\Documents\qualityrun.bat" >nul
    echo [OK] qualityrun.bat restaurado >> "%LOG_FILE%"
)

:: Instalar dependencias nuevas (ultralytics para el crop)
echo         Actualizando dependencias Python...
python -m pip install -r "%PIPELINE%\requirements.txt" -q >> "%LOG_FILE%" 2>&1
echo         Actualizando dependencias Node.js...
cd /d "%PIPELINE%"
call npm install >> "%LOG_FILE%" 2>&1

:: Borrar repo antiguo
echo.
echo  Eliminando repo antiguo en %OLD_REPO%...
rd /s /q "%OLD_REPO%" >> "%LOG_FILE%" 2>&1
echo [OK] %OLD_REPO% eliminado >> "%LOG_FILE%"

:: Limpiar backup
rmdir /s /q "%BACKUP%" >nul 2>&1

echo [FIN] Migracion completada %date% %time% >> "%LOG_FILE%"

echo.
echo  =============================================================
echo         MIGRACION COMPLETADA
echo  =============================================================
echo.
echo  Nueva estructura:
echo    C:\pizza_pipeline\   = repo git + pipeline
echo.
echo  Conservado:
echo    google_key.json      OK
echo    location_slug.txt    OK
echo    qualityrun.bat       OK
echo    Tareas programadas   Sin cambios
echo.
echo  Para futuras actualizaciones usa: actualizar.bat
echo.
echo  Log en: %LOG_FILE%
echo.
pause
exit /b 0
