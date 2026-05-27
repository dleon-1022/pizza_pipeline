@echo off
cd /d C:\pizza_pipeline

set /p LOCATION_SLUG=<location_slug.txt

echo 1. Extrayendo frames
python extract_frames.py
if errorlevel 1 goto error

echo 2. Recortando pizzas
python crop_pizza_images.py --model C:\pizza_pipeline\best.pt --input_dir C:\pizza_pipeline\frames --output_dir C:\pizza_pipeline\cropped_frames
if errorlevel 1 goto error

echo 3. Clasificando
python classify_frames.py
if errorlevel 1 goto error

echo 4. Subiendo a S3
node upload_selected_frames.js %LOCATION_SLUG%
if errorlevel 1 goto error

echo 5. Subiendo a Google Sheets
node upload_to_sheets.js
if errorlevel 1 goto error

echo === PROCESO COMPLETO ===
pause
exit /b 0

:error
echo.
echo ERROR EN PIPELINE
echo Revisa el mensaje de error arriba.
pause
exit /b 1