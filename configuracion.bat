@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Gritsee - Configuracion Pizza Quality

:: =====================================================
::  ESTRUCTURA DEL SISTEMA
::  El repo se clona directo a C:\pizza_pipeline\
::  No hay copia de archivos - el repo ES el pipeline
::
::  Pipeline (= repo)   →  C:\pizza_pipeline\
::  Scripts de video    →  C:\Users\gritseeuser1\Documents\
::  Videos grabados     →  C:\Users\gritseeuser1\Documents\qualityvids\
:: =====================================================

:: === VERIFICAR ADMINISTRADOR ===
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set SCRIPT_DIR=%~dp0
set TEMP_SETUP=%TEMP%\gritsee_setup
set LOG_FILE=%USERPROFILE%\Desktop\gritsee_configuracion.log
mkdir "%TEMP_SETUP%" 2>nul

:: Iniciar log
echo ============================================================ > "%LOG_FILE%"
echo  GRITSEE - LOG DE CONFIGURACION >> "%LOG_FILE%"
echo  Fecha: %date%  Hora: %time% >> "%LOG_FILE%"
echo  Ejecutado desde: %SCRIPT_DIR% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"

cls
echo.
echo  =============================================================
echo         GRITSEE  -  CONFIGURACION PIZZA QUALITY
echo  =============================================================
echo.
echo  Este asistente instalara y configurara automaticamente:
echo.
echo    [1/5]  Python 3.14.4
echo    [2/5]  Node.js 22.22.2
echo    [3/5]  Microsoft Visual C++ Redistributable
echo    [4/5]  Dependencias pip y npm
echo    [5/5]  Camara RTSP + Tareas programadas
echo.
echo  Tiempo estimado: 5-10 minutos  ^|  Requiere internet
echo  Log guardado en: %LOG_FILE%
echo.
echo  Presiona cualquier tecla para comenzar...
pause >nul

:: =====================================================
::  CONTRASENA de gritseeuser1
:: =====================================================
echo.
echo  Ingresa la contrasena del usuario gritseeuser1
echo  (necesaria para registrar las tareas programadas):
echo.
powershell -NoProfile -Command "$p = Read-Host '  Contrasena' -AsSecureString; $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); $t = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b); [System.IO.File]::WriteAllText('%TEMP_SETUP%\pwd.tmp', $t, [System.Text.Encoding]::UTF8)"
if not exist "%TEMP_SETUP%\pwd.tmp" (
    echo  ERROR: No se pudo obtener la contrasena.
    echo [ERROR] No se obtuvo contrasena >> "%LOG_FILE%"
    pause & exit /b 1
)

:: =====================================================
::  LOCACION
:: =====================================================
echo.
echo  Ingresa el nombre de esta locacion
echo  (ej: mirasierra2, lasrozas1, centro3):
set /p LOCATION_SLUG=  Locacion:
if "!LOCATION_SLUG!"=="" (
    echo  ERROR: Debes ingresar un nombre de locacion.
    echo [ERROR] Locacion vacia >> "%LOG_FILE%"
    pause & exit /b 1
)
echo [INFO] Locacion: !LOCATION_SLUG! >> "%LOG_FILE%"

echo.
echo  =============================================================
echo.

:: =====================================================
::  1/5 - Python 3.14.4
:: =====================================================
echo  [1/5]  Descargando Python 3.14.4...
echo [PASO 1/5] Python 3.14.4 >> "%LOG_FILE%"

powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.14.4/python-3.14.4-amd64.exe' -OutFile '%TEMP_SETUP%\python_setup.exe' -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if not exist "%TEMP_SETUP%\python_setup.exe" (
    echo  ERROR: No se pudo descargar Python 3.14.4
    echo [ERROR] Descarga Python fallo >> "%LOG_FILE%"
    goto :error
)

echo         Instalando Python 3.14.4...
"%TEMP_SETUP%\python_setup.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_launcher=1 >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  ERROR: Fallo la instalacion de Python.
    echo [ERROR] Instalacion Python fallo >> "%LOG_FILE%"
    goto :error
)
echo         Python 3.14.4  [OK]
echo [OK] Python 3.14.4 instalado >> "%LOG_FILE%"
echo.

:: =====================================================
::  2/5 - Node.js 22.22.2
:: =====================================================
echo  [2/5]  Descargando Node.js 22.22.2...
echo [PASO 2/5] Node.js 22.22.2 >> "%LOG_FILE%"

powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://nodejs.org/dist/v22.22.2/node-v22.22.2-x64.msi' -OutFile '%TEMP_SETUP%\node_setup.msi' -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if not exist "%TEMP_SETUP%\node_setup.msi" (
    echo  ERROR: No se pudo descargar Node.js 22.22.2
    echo [ERROR] Descarga Node.js fallo >> "%LOG_FILE%"
    goto :error
)

echo         Instalando Node.js 22.22.2...
msiexec /i "%TEMP_SETUP%\node_setup.msi" /quiet /norestart ADDLOCAL=ALL /l*v "%LOG_FILE%.node.log"
echo         Node.js 22.22.2  [OK]
echo [OK] Node.js 22.22.2 instalado >> "%LOG_FILE%"
echo.

:: =====================================================
::  3/5 - Visual C++ Redistributable
:: =====================================================
echo  [3/5]  Descargando Visual C++ Redistributable...
echo [PASO 3/5] Visual C++ Redistributable >> "%LOG_FILE%"

powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile '%TEMP_SETUP%\vc_redist.exe' -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if not exist "%TEMP_SETUP%\vc_redist.exe" (
    echo  ERROR: No se pudo descargar Visual C++ Redistributable
    echo [ERROR] Descarga VC++ fallo >> "%LOG_FILE%"
    goto :error
)

echo         Instalando Visual C++ Redistributable...
"%TEMP_SETUP%\vc_redist.exe" /quiet /norestart /log "%LOG_FILE%.vcredist.log"
echo         Visual C++ Redistributable  [OK]
echo [OK] Visual C++ instalado >> "%LOG_FILE%"
echo.

:: Refrescar PATH para detectar python y node recien instalados
for /f "skip=2 tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYS_PATH=%%b"
if defined SYS_PATH set "PATH=%SYS_PATH%;%PATH%"

::  4/5 - Dependencias pip y npm
::  Los archivos ya estan en SCRIPT_DIR porque el
::  repo se clono directamente a C:\pizza_pipeline\
:: =====================================================
echo  [4/5]  Configurando dependencias...
echo [PASO 4/5] Dependencias >> "%LOG_FILE%"

:: Crear carpetas de runtime (el codigo ya esta aqui)
mkdir "%SCRIPT_DIR%frames"          2>nul
mkdir "%SCRIPT_DIR%cropped_frames"  2>nul
mkdir "%SCRIPT_DIR%selected_frames" 2>nul

:: Escribir location_slug
powershell -NoProfile -Command "Set-Content -Path '%SCRIPT_DIR%location_slug.txt' -Value '!LOCATION_SLUG!' -NoNewline" >> "%LOG_FILE%" 2>&1
echo [INFO] location_slug = !LOCATION_SLUG! >> "%LOG_FILE%"

:: Copiar deletequality.bat a Documents
if not exist "C:\Users\gritseeuser1\Documents" mkdir "C:\Users\gritseeuser1\Documents"
copy /Y "%SCRIPT_DIR%video\deletequality.bat" "C:\Users\gritseeuser1\Documents\deletequality.bat" >> "%LOG_FILE%" 2>&1
echo [OK] deletequality.bat copiado >> "%LOG_FILE%"

:: pip install
echo         Instalando dependencias Python (pip)...
python -m pip install --upgrade pip -q >> "%LOG_FILE%" 2>&1
python -m pip install -r "%SCRIPT_DIR%requirements.txt" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Python no se instalaron.
    echo         Revisa el log para ver el detalle.
    echo [WARN] pip install con errores >> "%LOG_FILE%"
) else (
    echo         Dependencias Python (pip)  [OK]
    echo [OK] pip install completado >> "%LOG_FILE%"
)

:: npm install
echo         Instalando dependencias Node.js (npm)...
cd /d "%SCRIPT_DIR%"
call npm install >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Node.js no se instalaron.
    echo         Revisa el log para ver el detalle.
    echo [WARN] npm install con errores >> "%LOG_FILE%"
) else (
    echo         Dependencias Node.js (npm)  [OK]
    echo [OK] npm install completado >> "%LOG_FILE%"
)
echo.

:: =====================================================
::  5/5 - Camara RTSP + Tareas programadas
:: =====================================================
echo  [5/5]  Configurando camara y tareas programadas...
echo [PASO 5/5] Camara y tareas >> "%LOG_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup_camera.ps1" -LogFile "%LOG_FILE%"
if errorlevel 1 (
    echo  AVISO: No se pudo configurar la camara.
    echo  Puedes configurarlo manualmente editando:
    echo    C:\Users\gritseeuser1\Documents\qualityrun.bat
    echo [WARN] setup_camera.ps1 fallo >> "%LOG_FILE%"
) else (
    echo         Camara RTSP  [OK]
    echo [OK] qualityrun.bat generado >> "%LOG_FILE%"
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%create_tasks.ps1" -PasswordFile "%TEMP_SETUP%\pwd.tmp" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  AVISO: Error al crear las tareas programadas.
    echo  Revisa el log o crealas manualmente.
    echo [WARN] create_tasks.ps1 con errores >> "%LOG_FILE%"
) else (
    echo         Tareas programadas  [OK]
    echo [OK] Tareas programadas creadas >> "%LOG_FILE%"
)
echo.

:: =====================================================
::  Limpieza
:: =====================================================
del /f /q "%TEMP_SETUP%\python_setup.exe" >nul 2>&1
del /f /q "%TEMP_SETUP%\node_setup.msi"   >nul 2>&1
del /f /q "%TEMP_SETUP%\vc_redist.exe"    >nul 2>&1
del /f /q "%TEMP_SETUP%\pwd.tmp"          >nul 2>&1
rmdir /s /q "%TEMP_SETUP%"               >nul 2>&1

echo [FIN] Configuracion completada %date% %time% >> "%LOG_FILE%"

:: =====================================================
::  Verificar google_key.json
:: =====================================================
if not exist "%SCRIPT_DIR%google_key.json" (
    echo  =============================================================
    echo   ATENCION - FALTA UN ARCHIVO
    echo  =============================================================
    echo.
    echo   google_key.json no esta en C:\pizza_pipeline\ (= esta carpeta)
    echo.
    echo   Para copiarlo:
    echo     1. En AnyDesk abre el File Manager ^(icono carpeta arriba^)
    echo     2. En tu PC navega hasta google_key.json
    echo     3. Copialo a C:\pizza_pipeline\ en la PC remota
    echo.
    echo   Sin este archivo NO funcionara la subida a Google Sheets.
    echo.
    pause
)

echo  =============================================================
echo         CONFIGURACION COMPLETADA CON EXITO
echo  =============================================================
echo.
echo  Carpeta del proyecto:  C:\pizza_pipeline\
echo  Videos grabados:       C:\Users\gritseeuser1\Documents\qualityvids\
echo  Script de grabacion:   C:\Users\gritseeuser1\Documents\qualityrun.bat
echo.
echo  Tareas programadas:
echo.
echo    3:00 AM  Pipeline de analisis de pizza (diario)
echo   10:21 AM  Grabacion de video (cada 15 min, 13 horas)
echo    8:20 AM  Limpieza de videos (diario)
echo.
echo  Log completo guardado en:
echo    %LOG_FILE%
echo.
echo  Presiona cualquier tecla para cerrar.
pause >nul
exit /b 0

:error
del /f /q "%TEMP_SETUP%\pwd.tmp" >nul 2>&1
echo [ERROR] Configuracion interrumpida %date% %time% >> "%LOG_FILE%"
echo.
echo  =============================================================
echo         SE PRODUJO UN ERROR
echo  =============================================================
echo  Revisa el log para ver el detalle:
echo    %LOG_FILE%
echo.
pause
exit /b 1
