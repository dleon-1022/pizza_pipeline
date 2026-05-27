@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Gritsee - Configuracion Pizza Quality

:: =====================================================
::  Verificar privilegios de administrador
:: =====================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set SCRIPT_DIR=%~dp0
set TEMP_SETUP=%TEMP%\gritsee_setup
mkdir "%TEMP_SETUP%" 2>nul

cls
echo.
echo  =============================================================
echo          GRITSEE  -  CONFIGURACION PIZZA QUALITY
echo  =============================================================
echo.
echo  Este asistente instalara y configurara automaticamente:
echo.
echo    - Python 3.14.4
echo    - Node.js 22.22.2
echo    - Microsoft Visual C++ Redistributable
echo    - Dependencias del pipeline  (pip + npm)
echo    - Tareas programadas de Windows
echo.
echo  Tiempo estimado: 5 a 10 minutos
echo  Se requiere conexion a internet
echo.
echo  Presiona cualquier tecla para comenzar...
echo  (Ctrl+C para cancelar)
pause >nul

:: =====================================================
::  Solicitar contrasena de gritseeuser1
:: =====================================================
echo.
echo  Ingresa la contrasena del usuario gritseeuser1
echo  (se necesita para registrar las tareas programadas):
echo.
powershell -NoProfile -Command "$p = Read-Host '  Contrasena' -AsSecureString; $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); $t = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b); [System.IO.File]::WriteAllText('%TEMP_SETUP%\pwd.tmp', $t, [System.Text.Encoding]::UTF8)"

if not exist "%TEMP_SETUP%\pwd.tmp" (
    echo.
    echo  ERROR: No se pudo obtener la contrasena.
    pause
    exit /b 1
)

echo.
echo  =============================================================
echo.

:: =====================================================
::  1 / 5  -  Python 3.14.4
:: =====================================================
echo  [1/5]  Descargando Python 3.14.4...
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.14.4/python-3.14.4-amd64.exe' -OutFile '%TEMP_SETUP%\python_setup.exe' -UseBasicParsing"
if not exist "%TEMP_SETUP%\python_setup.exe" (
    echo  ERROR: No se pudo descargar Python 3.14.4
    echo  Verifica tu conexion a internet e intenta de nuevo.
    goto :error
)
echo         Instalando Python 3.14.4...
"%TEMP_SETUP%\python_setup.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_launcher=1
if errorlevel 1 (
    echo  ERROR: Fallo la instalacion de Python.
    goto :error
)
echo         Python 3.14.4  [OK]
echo.

:: =====================================================
::  2 / 5  -  Node.js 22.22.2
:: =====================================================
echo  [2/5]  Descargando Node.js 22.22.2...
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://nodejs.org/dist/v22.22.2/node-v22.22.2-x64.msi' -OutFile '%TEMP_SETUP%\node_setup.msi' -UseBasicParsing"
if not exist "%TEMP_SETUP%\node_setup.msi" (
    echo  ERROR: No se pudo descargar Node.js 22.22.2
    echo  Verifica tu conexion a internet e intenta de nuevo.
    goto :error
)
echo         Instalando Node.js 22.22.2...
msiexec /i "%TEMP_SETUP%\node_setup.msi" /quiet /norestart ADDLOCAL=ALL
echo         Node.js 22.22.2  [OK]
echo.

:: =====================================================
::  3 / 5  -  Microsoft Visual C++ Redistributable
:: =====================================================
echo  [3/5]  Descargando Microsoft Visual C++ Redistributable...
powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile '%TEMP_SETUP%\vc_redist.exe' -UseBasicParsing"
if not exist "%TEMP_SETUP%\vc_redist.exe" (
    echo  ERROR: No se pudo descargar Visual C++ Redistributable
    echo  Verifica tu conexion a internet e intenta de nuevo.
    goto :error
)
echo         Instalando Visual C++ Redistributable...
"%TEMP_SETUP%\vc_redist.exe" /quiet /norestart
echo         Microsoft Visual C++ Redistributable  [OK]
echo.

:: Refrescar PATH para que python y node sean detectables
for /f "skip=2 tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "SYS_PATH=%%b"
if defined SYS_PATH set "PATH=%SYS_PATH%;%PATH%"

:: =====================================================
::  4 / 5  -  Archivos del proyecto y dependencias
:: =====================================================
echo  [4/5]  Configurando archivos del proyecto...

if not exist "C:\pizza_pipeline" mkdir "C:\pizza_pipeline"
xcopy /E /I /Y "%SCRIPT_DIR%pizza_pipeline\*" "C:\pizza_pipeline\" >nul 2>&1
mkdir "C:\pizza_pipeline\frames" 2>nul
mkdir "C:\pizza_pipeline\cropped_frames" 2>nul
mkdir "C:\pizza_pipeline\selected_frames" 2>nul
echo         Archivos copiados a C:\pizza_pipeline

if not exist "C:\Users\gritseeuser1\Documents" mkdir "C:\Users\gritseeuser1\Documents"
copy /Y "%SCRIPT_DIR%video\qualityrun.bat"    "C:\Users\gritseeuser1\Documents\qualityrun.bat"    >nul 2>&1
copy /Y "%SCRIPT_DIR%video\deletequality.bat" "C:\Users\gritseeuser1\Documents\deletequality.bat" >nul 2>&1
echo         Scripts de video copiados a Documents de gritseeuser1

echo         Instalando dependencias Python (puede tardar unos minutos)...
python -m pip install --upgrade pip -q >nul 2>&1
python -m pip install -r "C:\pizza_pipeline\requirements.txt" -q
if errorlevel 1 (
    echo         AVISO: Algunas dependencias no se instalaron correctamente.
    echo         Instalalas manualmente con:
    echo           pip install -r C:\pizza_pipeline\requirements.txt
) else (
    echo         Dependencias Python  [OK]
)

echo         Instalando dependencias Node.js...
cd /d "C:\pizza_pipeline"
call npm install --silent >nul 2>&1
echo         Dependencias Node.js  [OK]
echo.

:: =====================================================
::  5 / 5  -  Tareas programadas de Windows
:: =====================================================
echo  [5/5]  Creando tareas programadas de Windows...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%create_tasks.ps1" -PasswordFile "%TEMP_SETUP%\pwd.tmp"
if errorlevel 1 (
    echo.
    echo  AVISO: Hubo un problema al crear las tareas.
    echo  Puedes crearlas manualmente desde el Programador de tareas de Windows
    echo  usando los archivos XML en la carpeta video\.
) else (
    echo         Tareas programadas  [OK]
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

echo  =============================================================
echo          CONFIGURACION COMPLETADA CON EXITO
echo  =============================================================
echo.
echo  El sistema funcionara automaticamente:
echo.
echo    3:00 AM  -  Pipeline de analisis de pizza
echo   10:21 AM  -  Grabacion de video (cada 15 min, 13 horas)
echo    8:20 AM  -  Limpieza de videos del dia anterior
echo.
echo  Presiona cualquier tecla para cerrar.
pause >nul
exit /b 0

:error
del /f /q "%TEMP_SETUP%\pwd.tmp" >nul 2>&1
echo.
echo  =============================================================
echo          SE PRODUJO UN ERROR
echo  =============================================================
echo  Corrige el problema indicado y vuelve a correr configuracion.bat
echo.
pause
exit /b 1
