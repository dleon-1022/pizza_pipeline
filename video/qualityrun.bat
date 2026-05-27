@echo off
set HOUR=%time:~0,2%
set HOUR=%HOUR: =0%
REM Horas permitidas
if "%HOUR%"=="11" goto RUN
if "%HOUR%"=="12" goto RUN
if "%HOUR%"=="13" goto RUN
if "%HOUR%"=="14" goto RUN
if "%HOUR%"=="15" goto RUN
if "%HOUR%"=="18" goto RUN
if "%HOUR%"=="19" goto RUN
if "%HOUR%"=="20" goto RUN
if "%HOUR%"=="21" goto RUN
exit /b
:RUN
if not exist "C:\Users\gritseeuser1\Documents\qualityvids" mkdir "C:\Users\gritseeuser1\Documents\qualityvids"
ffmpeg -rtsp_transport tcp ^
-i "RTSP_URL_GENERADA_POR_SETUP_CAMERA" ^
-an ^
-c:v libx264 -preset ultrafast -tune zerolatency ^
-f segment -segment_time 600 -reset_timestamps 1 -strftime 1 ^
-segment_format mp4 ^
-segment_format_options movflags=+faststart ^
-t 3600 ^
"C:\Users\gritseeuser1\Documents\qualityvids\%%Y%%m%%d%%p-%%Y%%m%%d-%%H%%M%%S.mp4"
