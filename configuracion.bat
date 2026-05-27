@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Gritsee - Configuracion Pizza Quality

:: =====================================================
::  RUTAS FIJAS DEL SISTEMA (no dependen de donde
::  se clono el repo — siempre se despliega aqui)
:: =====================================================
::
::  Repo clonado        →  cualquier carpeta (SCRIPT_DIR)
::  Pipeline            →  C:\pizza_pipeline\
::  Scripts de video    →  C:\Users\gritseeuser1\Documents\
::  Videos grabados     →  C:\Users\gritseeuser1\Documents\qualityvids\
::
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
echo    [1/6]  Python 3.14.4
echo    [2/6]  Node.js 22.22.2
echo    [3/6]  Microsoft Visual C++ Redistributable
echo    [4/6]  Archivos del proyecto + dependencias pip y npm
echo    [5/6]  Camara RTSP
echo    [6/6]  Tareas programadas de Windows
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
::  1/6 — Python 3.14.4
:: =====================================================
echo  [1/6]  Descargando Python 3.14.4...
echo [PASO 1/6] Python 3.14.4 >> "%LOG_FILE%"

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
::  2/6 — Node.js 22.22.2
:: =====================================================
echo  [2/6]  Descargando Node.js 22.22.2...
echo [PASO 2/6] Node.js 22.22.2 >> "%LOG_FILE%"

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
::  3/6 — Microsoft Visual C++ Redistributable
:: =====================================================
echo  [3/6]  Descargando Visual C++ Redistributable...
echo [PASO 3/6] Visual C++ Redistributable >> "%LOG_FILE%"

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

:: =====================================================
::  4/6 — Archivos del proyecto + dependencias
:: =====================================================
echo  [4/6]  Copiando archivos y configurando dependencias...
echo [PASO 4/6] Archivos y dependencias >> "%LOG_FILE%"

:: --- Pipeline → C:\pizza_pipeline\ ---
if not exist "C:\pizza_pipeline" mkdir "C:\pizza_pipeline"
xcopy /E /I /Y "%SCRIPT_DIR%pizza_pipeline\*" "C:\pizza_pipeline\" >> "%LOG_FILE%" 2>&1

:: Crear carpetas de runtime
mkdir "C:\pizza_pipeline\frames" 2>nul
mkdir "C:\pizza_pipeline\cropped_frames" 2>nul
mkdir "C:\pizza_pipeline\selected_frames" 2>nul

:: Escribir location_slug
powershell -NoProfile -Command "Set-Content -Path 'C:\pizza_pipeline\location_slug.txt' -Value '!LOCATION_SLUG!' -NoNewline" >> "%LOG_FILE%" 2>&1

echo         C:\pizza_pipeline\  [OK]
echo [OK] Archivos pipeline copiados a C:\pizza_pipeline >> "%LOG_FILE%"
echo [INFO] location_slug = !LOCATION_SLUG! >> "%LOG_FILE%"

:: --- Documents de gritseeuser1 ---
if not exist "C:\Users\gritseeuser1\Documents" mkdir "C:\Users\gritseeuser1\Documents"
copy /Y "%SCRIPT_DIR%video\deletequality.bat" "C:\Users\gritseeuser1\Documents\deletequality.bat" >> "%LOG_FILE%" 2>&1
echo         C:\Users\gritseeuser1\Documents\  [OK]
echo [OK] deletequality.bat copiado >> "%LOG_FILE%"

:: --- Dependencias Python (pip) ---
echo         Instalando dependencias Python (pip)...
echo [INFO] pip install requirements.txt >> "%LOG_FILE%"
python -m pip install --upgrade pip -q >> "%LOG_FILE%" 2>&1
python -m pip install -r "C:\pizza_pipeline\requirements.txt" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Python no se instalaron.
    echo         Revisa el log para ver el detalle.
    echo [WARN] pip install con errores - revisar log >> "%LOG_FILE%"
) else (
    echo         Dependencias Python (pip)  [OK]
    echo [OK] pip install completado >> "%LOG_FILE%"
)

:: --- Dependencias Node.js (npm) ---
echo         Instalando dependencias Node.js (npm)...
echo [INFO] npm install en C:\pizza_pipeline >> "%LOG_FILE%"
cd /d "C:\pizza_pipeline"
call npm install >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Node.js no se instalaron.
    echo         Revisa el log para ver el detalle.
    echo [WARN] npm install con errores - revisar log >> "%LOG_FILE%"
) else (
    echo         Dependencias Node.js (npm)  [OK]
    echo [OK] npm install completado >> "%LOG_FILE%"
)
echo.

:: =====================================================
::  5/6 — Configuracion de camara RTSP
:: =====================================================
echo  [5/6]  Configurando camara RTSP...
echo [PASO 5/6] Configuracion camara RTSP >> "%LOG_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup_camera.ps1" -LogFile "%LOG_FILE%"
if errorlevel 1 (
    echo  AVISO: No se pudo configurar la camara.
    echo  qualityrun.bat no fue generado automaticamente.
    echo  Puedes configurarlo manualmente editando:
    echo    C:\Users\gritseeuser1\Documents\qualityrun.bat
    echo [WARN] setup_camera.ps1 fallo >> "%LOG_FILE%"
) else (
    echo         Camara RTSP configurada  [OK]
    echo [OK] qualityrun.bat generado >> "%LOG_FILE%"
)
echo.

:: =====================================================
::  6/6 — Tareas programadas de Windows
:: =====================================================
echo  [6/6]  Creando tareas programadas de Windows...
echo [PASO 6/6] Tareas programadas >> "%LOG_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%create_tasks.ps1" -PasswordFile "%TEMP_SETUP%\pwd.tmp" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  AVISO: Error al crear las tareas programadas.
    echo  Revisa el log o crealas manualmente desde el Programador de tareas.
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

echo  =============================================================
echo         CONFIGURACION COMPLETADA CON EXITO
echo  =============================================================
echo.
echo  Rutas del sistema:
echo.
echo    C:\pizza_pipeline\           Pipeline de analisis
echo    C:\Users\gritseeuser1\Documents\qualityvids\   Videos grabados
echo    C:\Users\gritseeuser1\Documents\qualityrun.bat  Grabacion
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
