@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Gritsee - Pizza Quality

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\" %*' -Verb RunAs"
    exit /b
)

set SCRIPT_DIR=%~dp0
set PIPELINE_DIR=C:\pizza_pipeline
set DOCS_DIR=C:\Users\gritseeuser1\Documents
set LOG_FILE=%USERPROFILE%\Desktop\gritsee_configuracion.log

:: =====================================================
::  PARSEAR ARGUMENTOS (modo automatico)
:: =====================================================
set AUTO_MODE=0
set TIPO=
set LOCATION_SLUG=
set GRITSEE_PASS=
set CAM_USER=
set CAM_PASS=
set CAM_IP=
set CAM_PORT=554
set CAM_MARCA=
set CAM_CANAL=1

:parse_args
if "%~1"=="" goto :done_parse
set _ARG=%~1
if /i "%_ARG%"=="/auto"            set AUTO_MODE=1
if /i "%_ARG:~0,6%"=="/tipo:"      set TIPO=%_ARG:~6%
if /i "%_ARG:~0,6%"=="/slug:"      set LOCATION_SLUG=%_ARG:~6%
if /i "%_ARG:~0,6%"=="/pass:"      set GRITSEE_PASS=%_ARG:~6%
if /i "%_ARG:~0,10%"=="/cam_user:" set CAM_USER=%_ARG:~10%
if /i "%_ARG:~0,10%"=="/cam_pass:" set CAM_PASS=%_ARG:~10%
if /i "%_ARG:~0,8%"=="/cam_ip:"   set CAM_IP=%_ARG:~8%
if /i "%_ARG:~0,10%"=="/cam_port:" set CAM_PORT=%_ARG:~10%
if /i "%_ARG:~0,11%"=="/cam_marca:" set CAM_MARCA=%_ARG:~11%
if /i "%_ARG:~0,11%"=="/cam_canal:" set CAM_CANAL=%_ARG:~11%
shift
goto :parse_args
:done_parse

:: Modo automatico: ir directo segun /tipo
if %AUTO_MODE%==1 (
    if /i "!TIPO!"=="actualizar" goto :actualizar
    if /i "!TIPO!"=="nueva"      goto :nueva
)

:: Modo interactivo: mostrar menu
cls
echo.
echo  =============================================================
echo         GRITSEE  -  PIZZA QUALITY
echo  =============================================================
echo.
echo    [1]  Actualizar
echo         Descarga cambios de GitHub y actualiza dependencias
echo.
echo    [2]  Configuracion nueva
echo         Instala Python, Node, configura camara y tareas
echo.
echo  =============================================================
echo.
set /p OPCION=  Selecciona una opcion [1 o 2]:

if "!OPCION!"=="1" goto :actualizar
if "!OPCION!"=="2" goto :nueva
echo  Opcion no valida.
pause & exit /b 1

:: =====================================================
::  OPCION 1 — ACTUALIZAR
:: =====================================================
:actualizar
cls
echo.
echo  =============================================================
echo         ACTUALIZANDO PIPELINE
echo  =============================================================
echo.

echo ============================================================ > "%LOG_FILE%"
echo  GRITSEE - ACTUALIZACION >> "%LOG_FILE%"
echo  Fecha: %date%  Hora: %time% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"

if not exist "%PIPELINE_DIR%\.git" (
    echo  ERROR: No se encontro el repo en %PIPELINE_DIR%
    echo  Usa la opcion 2 para hacer una instalacion nueva.
    pause & exit /b 1
)

echo  [1/3]  Descargando cambios de GitHub...
cd /d "%PIPELINE_DIR%"
git pull >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  ERROR: No se pudo conectar con GitHub. Verifica internet.
    pause & exit /b 1
)
echo         GitHub  [OK]
echo [OK] git pull completado >> "%LOG_FILE%"

echo  [2/3]  Slug de locacion...
if exist "%PIPELINE_DIR%\location_slug.txt" (
    set /p SLUG_ACTUAL=<"%PIPELINE_DIR%\location_slug.txt"
    echo.
    echo         Slug actual: !SLUG_ACTUAL!
    echo.
    set /p CAMBIAR_SLUG=         Quieres cambiarlo? [s/N]:
    if /i "!CAMBIAR_SLUG!"=="s" (
        echo.
        set /p NUEVO_SLUG=         Nuevo slug:
        if not "!NUEVO_SLUG!"=="" (
            powershell -NoProfile -Command "Set-Content -Path '%PIPELINE_DIR%\location_slug.txt' -Value '!NUEVO_SLUG!' -NoNewline"
            echo         Slug actualizado: !NUEVO_SLUG!  [OK]
            echo [OK] Slug actualizado: !NUEVO_SLUG! >> "%LOG_FILE%"
        )
    ) else (
        echo         Slug sin cambios  [OK]
    )
) else (
    echo.
    set /p NUEVO_SLUG=         No hay slug. Ingresa uno:
    powershell -NoProfile -Command "Set-Content -Path '%PIPELINE_DIR%\location_slug.txt' -Value '!NUEVO_SLUG!' -NoNewline"
    echo         Slug guardado: !NUEVO_SLUG!  [OK]
)

echo  [3/3]  Actualizando dependencias...
python -m pip install -r "%PIPELINE_DIR%\requirements.txt" -q >> "%LOG_FILE%" 2>&1
echo         Python  [OK]
call npm install >> "%LOG_FILE%" 2>&1
echo         Node.js  [OK]
echo [OK] Dependencias actualizadas >> "%LOG_FILE%"

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

:: =====================================================
::  OPCION 2 — CONFIGURACION NUEVA
:: =====================================================
:nueva
cls
set TEMP_SETUP=%TEMP%\gritsee_setup
mkdir "%TEMP_SETUP%" 2>nul

echo.
echo  =============================================================
echo         CONFIGURACION NUEVA
echo  =============================================================
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
if %AUTO_MODE%==0 (
    echo  Presiona cualquier tecla para comenzar...
    pause >nul
)

echo ============================================================ > "%LOG_FILE%"
echo  GRITSEE - CONFIGURACION NUEVA >> "%LOG_FILE%"
echo  Fecha: %date%  Hora: %time% >> "%LOG_FILE%"
echo ============================================================ >> "%LOG_FILE%"

:: Contrasena
if %AUTO_MODE%==1 goto :pass_auto
echo.
echo  Ingresa la contrasena del usuario gritseeuser1:
echo.
powershell -NoProfile -Command "$p = Read-Host '  Contrasena' -AsSecureString; $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); $t = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b); [System.IO.File]::WriteAllText('%TEMP_SETUP%\pwd.tmp', $t, [System.Text.Encoding]::UTF8)"
goto :check_pass
:pass_auto
powershell -NoProfile -Command "[System.IO.File]::WriteAllText('%TEMP_SETUP%\pwd.tmp', '!GRITSEE_PASS!', [System.Text.Encoding]::UTF8)"
:check_pass
if not exist "%TEMP_SETUP%\pwd.tmp" (
    echo  ERROR: No se pudo obtener la contrasena.
    pause
    exit /b 1
)

:: Locacion
if %AUTO_MODE%==1 goto :check_slug
echo.
echo  Ingresa el nombre de esta locacion (ej: pcsapi-cardenas):
set /p LOCATION_SLUG=  Locacion:
:check_slug
if "!LOCATION_SLUG!"=="" (
    echo  ERROR: Debes ingresar un nombre de locacion.
    pause
    exit /b 1
)
echo [INFO] Locacion: !LOCATION_SLUG! >> "%LOG_FILE%"

echo.
echo  =============================================================
echo.

:: 1/5 Python
echo  [1/5]  Descargando Python 3.14.4...
echo [PASO 1/5] Python >> "%LOG_FILE%"
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.14.4/python-3.14.4-amd64.exe' -OutFile '%TEMP_SETUP%\python_setup.exe' -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if not exist "%TEMP_SETUP%\python_setup.exe" goto :error
echo         Instalando...
"%TEMP_SETUP%\python_setup.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0 >> "%LOG_FILE%" 2>&1
if errorlevel 1 goto :error
echo         Python 3.14.4  [OK]
echo [OK] Python instalado >> "%LOG_FILE%"

:: 2/5 Node.js
echo  [2/5]  Descargando Node.js 22.22.2...
echo [PASO 2/5] Node.js >> "%LOG_FILE%"
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://nodejs.org/dist/v22.22.2/node-v22.22.2-x64.msi' -OutFile '%TEMP_SETUP%\node_setup.msi' -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if not exist "%TEMP_SETUP%\node_setup.msi" goto :error
echo         Instalando...
msiexec /i "%TEMP_SETUP%\node_setup.msi" /quiet /norestart ADDLOCAL=ALL
echo         Node.js 22.22.2  [OK]
echo [OK] Node.js instalado >> "%LOG_FILE%"

:: 3/5 VC++
echo  [3/5]  Descargando Visual C++ Redistributable...
echo [PASO 3/5] VC++ >> "%LOG_FILE%"
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile '%TEMP_SETUP%\vc_redist.exe' -UseBasicParsing" >> "%LOG_FILE%" 2>&1
if not exist "%TEMP_SETUP%\vc_redist.exe" goto :error
echo         Instalando...
"%TEMP_SETUP%\vc_redist.exe" /quiet /norestart
echo         Visual C++ Redistributable  [OK]
echo [OK] VC++ instalado >> "%LOG_FILE%"

:: Refrescar PATH
for /f "skip=2 tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYS_PATH=%%b"
if defined SYS_PATH set "PATH=%SYS_PATH%;%PATH%"

:: 4/5 Dependencias + archivos
echo  [4/5]  Configurando dependencias...
echo [PASO 4/5] Dependencias >> "%LOG_FILE%"

:: Carpetas runtime
mkdir "%PIPELINE_DIR%\frames"          2>nul
mkdir "%PIPELINE_DIR%\cropped_frames"  2>nul
mkdir "%PIPELINE_DIR%\selected_frames" 2>nul
mkdir "%PIPELINE_DIR%\models"          2>nul

:: Location slug
powershell -NoProfile -Command "Set-Content -Path '%PIPELINE_DIR%\location_slug.txt' -Value '!LOCATION_SLUG!' -NoNewline" >> "%LOG_FILE%" 2>&1

:: Crear deletequality.bat en Documents
if not exist "%DOCS_DIR%" mkdir "%DOCS_DIR%"
echo @echo off > "%DOCS_DIR%\deletequality.bat"
echo del /S /Q "C:\Users\gritseeuser1\Documents\qualityvids\*" >> "%DOCS_DIR%\deletequality.bat"
echo [OK] deletequality.bat creado en Documents >> "%LOG_FILE%"

:: pip install
echo         Instalando dependencias Python...
python -m pip install --upgrade pip -q >> "%LOG_FILE%" 2>&1
python -m pip install -r "%PIPELINE_DIR%\requirements.txt" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Python no se instalaron.
    echo [WARN] pip con errores >> "%LOG_FILE%"
) else (
    echo         Python  [OK]
    echo [OK] pip completado >> "%LOG_FILE%"
)

:: npm install
cd /d "%PIPELINE_DIR%"
call npm install >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo         AVISO: Algunas dependencias Node.js no se instalaron.
    echo [WARN] npm con errores >> "%LOG_FILE%"
) else (
    echo         Node.js  [OK]
    echo [OK] npm completado >> "%LOG_FILE%"
)

:: 5/5 Camara + Tareas
echo  [5/5]  Configurando camara y tareas programadas...
echo [PASO 5/5] Camara y tareas >> "%LOG_FILE%"

if %AUTO_MODE%==1 (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup_camera.ps1" -LogFile "%LOG_FILE%" -BrandNum "!CAM_MARCA!" -CamUser "!CAM_USER!" -CamPass "!CAM_PASS!" -CamIp "!CAM_IP!" -CamPort "!CAM_PORT!" -Channel "!CAM_CANAL!"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup_camera.ps1" -LogFile "%LOG_FILE%"
)
if errorlevel 1 (
    echo  AVISO: No se pudo configurar la camara automaticamente.
    echo [WARN] setup_camera.ps1 fallo >> "%LOG_FILE%"
) else (
    echo         Camara RTSP  [OK]
    echo [OK] qualityrun.bat generado >> "%LOG_FILE%"
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%create_tasks.ps1" -PasswordFile "%TEMP_SETUP%\pwd.tmp" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo  AVISO: Error al crear las tareas programadas.
    echo [WARN] create_tasks.ps1 con errores >> "%LOG_FILE%"
) else (
    echo         Tareas programadas  [OK]
    echo [OK] Tareas creadas >> "%LOG_FILE%"
)

:: Limpieza
del /f /q "%TEMP_SETUP%\python_setup.exe" >nul 2>&1
del /f /q "%TEMP_SETUP%\node_setup.msi"   >nul 2>&1
del /f /q "%TEMP_SETUP%\vc_redist.exe"    >nul 2>&1
del /f /q "%TEMP_SETUP%\pwd.tmp"          >nul 2>&1
rmdir /s /q "%TEMP_SETUP%"               >nul 2>&1

echo [FIN] Configuracion completada %date% %time% >> "%LOG_FILE%"

:: Verificar google_key.json
if not exist "%PIPELINE_DIR%\google_key.json" (
    echo.
    echo  =============================================================
    echo   ATENCION: Falta google_key.json
    echo  =============================================================
    echo.
    echo   Copialo via AnyDesk File Manager a:
    echo   C:\pizza_pipeline\google_key.json
    echo.
    pause
)

echo.
echo  =============================================================
echo         CONFIGURACION COMPLETADA
echo  =============================================================
echo.
echo  Pipeline:   C:\pizza_pipeline\
echo  Videos:     C:\Users\gritseeuser1\Documents\qualityvids\
echo.
echo  Tareas:
echo    3:00 AM  Pipeline de analisis
echo   10:21 AM  Grabacion de video
echo    8:20 AM  Limpieza de videos
echo.
echo  Log en: %LOG_FILE%
echo.
if %AUTO_MODE%==0 pause
exit /b 0

:error
del /f /q "%TEMP_SETUP%\pwd.tmp" >nul 2>&1
echo [ERROR] %date% %time% >> "%LOG_FILE%"
echo.
echo  ERROR - Revisa: %LOG_FILE%
echo.
if %AUTO_MODE%==0 pause
exit /b 1
