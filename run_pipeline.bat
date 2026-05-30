@echo off
setlocal enabledelayedexpansion
cd /d C:\pizza_pipeline

set LOG_FILE=C:\pizza_pipeline\pipeline.log
set /p LOCATION_SLUG=<location_slug.txt

echo ============================================================ > "%LOG_FILE%"
echo  GRITSEE PIPELINE >> "%LOG_FILE%"
echo  Fecha: %date%  Hora: %time% >> "%LOG_FILE%"
echo  Locacion: %LOCATION_SLUG% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"

echo [%time%] Iniciando pipeline - %LOCATION_SLUG%

:: Limpiar carpetas de trabajo (solo una vez aqui)
del /q "C:\pizza_pipeline\frames\*"          2>nul
del /q "C:\pizza_pipeline\selected_frames\*" 2>nul
del /q "C:\pizza_pipeline\cropped_frames\*"  2>nul
echo [%time%] Carpetas limpiadas >> "%LOG_FILE%"

:: =====================================================
::  1. Extraer frames de los videos
:: =====================================================
echo [%time%] PASO 1: Extrayendo frames...
echo [PASO 1] Extraccion de frames >> "%LOG_FILE%"
python extract_frames.py >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%time%] ERROR en extraccion de frames >> "%LOG_FILE%"
    goto :error
)
echo [%time%] Frames extraidos OK >> "%LOG_FILE%"

:: =====================================================
::  2. Clasificar frames completos con ResNet
::     Selecciona los mejores frames antes del crop
:: =====================================================
echo [%time%] PASO 2: Clasificando frames con ResNet...
echo [PASO 2] Clasificacion ResNet >> "%LOG_FILE%"
python classify_frames.py >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%time%] ERROR en clasificacion ResNet >> "%LOG_FILE%"
    goto :error
)
echo [%time%] Clasificacion OK >> "%LOG_FILE%"

:: =====================================================
::  3. Recortar pizzas con YOLO (solo de los frames buenos)
:: =====================================================
echo [%time%] PASO 3: Recortando pizzas con YOLO...
echo [PASO 3] Crop YOLO >> "%LOG_FILE%"
python crop_pizza_images.py ^
  --model C:\pizza_pipeline\models\best.pt ^
  --input_dir C:\pizza_pipeline\selected_frames ^
  --output_dir C:\pizza_pipeline\cropped_frames ^
  --conf 0.45 >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%time%] ERROR en crop YOLO >> "%LOG_FILE%"
    goto :error
)
echo [%time%] Crop OK >> "%LOG_FILE%"

:: =====================================================
::  4. Subir recortes a S3
:: =====================================================
echo [%time%] PASO 4: Subiendo a S3...
echo [PASO 4] Upload S3 >> "%LOG_FILE%"
node upload_selected_frames.js %LOCATION_SLUG% >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%time%] ERROR en upload S3 >> "%LOG_FILE%"
    goto :error
)
echo [%time%] S3 OK >> "%LOG_FILE%"

:: =====================================================
::  5. Actualizar Google Sheets
:: =====================================================
echo [%time%] PASO 5: Actualizando Google Sheets...
echo [PASO 5] Google Sheets >> "%LOG_FILE%"
node upload_to_sheets.js >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%time%] ERROR en Google Sheets >> "%LOG_FILE%"
    goto :error
)
echo [%time%] Google Sheets OK >> "%LOG_FILE%"

echo ============================================================ >> "%LOG_FILE%"
echo [FIN] Pipeline completado %date% %time% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"
echo [%time%] Pipeline completado OK
exit /b 0

:error
echo ============================================================ >> "%LOG_FILE%"
echo [ERROR] Pipeline interrumpido %date% %time% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"
echo [%time%] ERROR - Revisa: %LOG_FILE%
exit /b 1
