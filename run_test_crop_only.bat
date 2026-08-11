@echo off
setlocal enabledelayedexpansion
:: ===========================================================================
::  PRUEBA: SOLO CROP (YOLO), SIN CLASIFICADOR RESNET
::
::  Mide cuantas imagenes saldrian si YOLO corriera directo sobre TODOS los
::  frames extraidos, sin pasar por classify_frames.py (ResNet).
::
::  NO toca produccion: no borra frames, no escribe en selected_frames ni en
::  cropped_frames, no sube a S3/Sheets, no marca videos como procesados.
:: ===========================================================================

cd /d C:\pizza_pipeline

set OUT_DIR=C:\pizza_pipeline\test_crop_only

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo ============================================================
echo  PRUEBA SOLO-CROP (YOLO) - %date% %time%
echo ============================================================
echo  Frames de entrada : C:\pizza_pipeline\frames (se leen tal como estan)
echo  Salida            : %OUT_DIR%
echo ============================================================
echo.

python scripts\test_crop_only.py ^
  --model C:\pizza_pipeline\models\best.pt ^
  --input_dir C:\pizza_pipeline\frames ^
  --output_dir "%OUT_DIR%" ^
  --conf_sweep 0.25 0.35 0.45 0.55 0.65 ^
  --save_conf 0.45

if errorlevel 1 goto :error

echo.
echo [%time%] Prueba completada. Abriendo reporte...
start "" "%OUT_DIR%\reporte_solo_crop.html"
echo.
pause
exit /b 0

:error
echo.
echo [%time%] ERROR en la prueba. Revisa los mensajes de arriba.
echo.
pause
exit /b 1
