# setup_camera.ps1
# Genera C:\Users\gritseeuser1\Documents\qualityrun.bat con la URL RTSP correcta
# Modo interactivo: sin parametros
# Modo automatico: pasar -BrandNum, -CamUser, -CamPass, -CamIp, -CamPort, -Channel

param(
    [string]$LogFile  = "",
    [string]$BrandNum = "",   # numero de marca (1=Hikvision, 2=Dahua, etc.)
    [string]$CamUser  = "",
    [string]$CamPass  = "",
    [string]$CamIp    = "",
    [string]$CamPort  = "554",
    [string]$Channel  = "1",
    [string]$RtspUrl  = ""
)

$autoMode = $BrandNum -ne "" -or $RtspUrl -ne ""

function Write-Log {
    param([string]$msg)
    Write-Host $msg
    if ($LogFile) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Out-File $LogFile -Append -Encoding UTF8 }
}

Write-Log ""
Write-Log "  -----------------------------------------------"
Write-Log "    CONFIGURACION DE CAMARA RTSP"
Write-Log "  -----------------------------------------------"
Write-Log ""
Write-Log "  Marcas soportadas:"
Write-Log ""
Write-Log "    [1]  Hikvision"
Write-Log "    [2]  Dahua / Amcrest"
Write-Log "    [3]  Anpviz"
Write-Log "    [4]  Reolink"
Write-Log "    [5]  Uniview (UNV)"
Write-Log "    [6]  Hanwha / Samsung"
Write-Log "    [7]  TP-Link Tapo"
Write-Log "    [8]  Axis"
Write-Log "    [9]  Bosch"
Write-Log "    [10] Otro / Ingresar URL manualmente"
Write-Log ""

if ($autoMode) {
    # Modo automatico: usar parametros recibidos
    $brandNum = $BrandNum
    $camUser  = $CamUser
    $camPass  = $CamPass
    $camIp    = $CamIp
    $camPort  = if ($CamPort -eq "") { "554" } else { $CamPort }
    if ($RtspUrl) { $brandNum = "10" }
    Write-Log "  Modo automatico: marca=$brandNum ip=$camIp puerto=$camPort"
} else {
    # Modo interactivo
    $brandNum = Read-Host "  Selecciona el numero de tu camara"
    Write-Log ""
    $camUser = Read-Host "  Usuario de la camara"
    $passSecure = Read-Host "  Contrasena de la camara" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passSecure)
    $camPass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $camIp = Read-Host "  IP de la camara (ej: 192.168.1.100)"
    $portInput = Read-Host "  Puerto RTSP (Enter para usar 554)"
    $camPort = if ($portInput -eq "") { "554" } else { $portInput }
}

# Construir URL segun marca
$rtspUrl = ""

switch ($brandNum) {

    "1" {
        # Hikvision
        # Formato: /Streaming/Channels/{canal}{stream}
        # Canal 1 stream principal = 101, canal 2 = 201, etc.
        $chInput = if ($autoMode) { $Channel } else { Read-Host "  Canal de video (Enter para canal 1)" }
        $ch = if ($chInput -eq "") { "1" } else { $chInput }
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/Streaming/Channels/${ch}01"
        Write-Log "  Formato Hikvision → /Streaming/Channels/${ch}01"
    }

    "2" {
        # Dahua / Amcrest
        # Formato: /cam/realmonitor?channel=N&subtype=0
        $chInput = if ($autoMode) { $Channel } else { Read-Host "  Canal de video (Enter para canal 1)" }
        $ch = if ($chInput -eq "") { "1" } else { $chInput }
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/cam/realmonitor?channel=${ch}&subtype=0"
        Write-Log "  Formato Dahua → /cam/realmonitor?channel=${ch}&subtype=0"
    }

    "3" {
        # Anpviz (compatible Hikvision)
        $chInput = if ($autoMode) { $Channel } else { Read-Host "  Canal de video (Enter para canal 1)" }
        $ch = if ($chInput -eq "") { "1" } else { $chInput }
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/Streaming/Channels/${ch}01"
        Write-Log "  Formato Anpviz → /Streaming/Channels/${ch}01"
    }

    "4" {
        # Reolink
        # Formato: /h264Preview_01_main  (canal 1 principal)
        $chInput = if ($autoMode) { $Channel } else { Read-Host "  Canal de video (Enter para canal 1)" }
        $ch = if ($chInput -eq "") { "01" } else { $chInput.PadLeft(2,"0") }
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/h264Preview_${ch}_main"
        Write-Log "  Formato Reolink → /h264Preview_${ch}_main"
    }

    "5" {
        # Uniview / UNV
        # Formato: /unicast/c{canal}/s0/live
        $chInput = if ($autoMode) { $Channel } else { Read-Host "  Canal de video (Enter para canal 1)" }
        $ch = if ($chInput -eq "") { "1" } else { $chInput }
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/unicast/c${ch}/s0/live"
        Write-Log "  Formato Uniview → /unicast/c${ch}/s0/live"
    }

    "6" {
        # Hanwha / Samsung
        # Formato: /profile1/media.smp
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/profile1/media.smp"
        Write-Log "  Formato Hanwha → /profile1/media.smp"
    }

    "7" {
        # TP-Link Tapo
        # Formato: /stream1  (stream principal)
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/stream1"
        Write-Log "  Formato TP-Link Tapo → /stream1"
    }

    "8" {
        # Axis
        # Formato: /axis-media/media.amp (sin puerto en path)
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/axis-media/media.amp"
        Write-Log "  Formato Axis → /axis-media/media.amp"
    }

    "9" {
        # Bosch
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/rtsp_tunnel"
        Write-Log "  Formato Bosch → /rtsp_tunnel"
    }

    "10" {
        # URL manual completa
        if ($autoMode) {
            if (-not $RtspUrl) {
                Write-Log "  ERROR: En modo automatico con marca 10 debes enviar -RtspUrl."
                exit 1
            }
            $rtspUrl = $RtspUrl
        } else {
            Write-Log ""
            Write-Log "  Ingresa la URL RTSP completa incluyendo usuario y contrasena."
            Write-Log "  Ejemplo: rtsp://admin:pass@192.168.1.10:554/Streaming/Channels/101"
            $rtspUrl = Read-Host "  URL RTSP"
        }
    }

    default {
        Write-Log "  Opcion no reconocida. Usando formato Hikvision por defecto."
        $chInput = if ($autoMode) { $Channel } else { Read-Host "  Canal de video (Enter para canal 1)" }
        $ch = if ($chInput -eq "") { "1" } else { $chInput }
        $rtspUrl = "rtsp://${camUser}:${camPass}@${camIp}:${camPort}/Streaming/Channels/${ch}01"
    }
}

if (-not $rtspUrl) {
    Write-Log "  ERROR: No se pudo construir la URL RTSP."
    exit 1
}

# Mostrar URL ocultando contrasena
$safeUrl = $rtspUrl -replace ":${camPass}@", ":***@"
Write-Log ""
Write-Log "  URL configurada: $safeUrl"

# --- Generar qualityrun.bat ---
$outputPath = "C:\Users\gritseeuser1\Documents\qualityrun.bat"

$batContent = @"
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
-i "${rtspUrl}" ^
-an ^
-c:v libx264 -preset ultrafast -tune zerolatency ^
-f segment -segment_time 600 -reset_timestamps 1 -strftime 1 ^
-segment_format mp4 ^
-segment_format_options movflags=+faststart ^
-t 3600 ^
"C:\Users\gritseeuser1\Documents\qualityvids\%%Y%%m%%d%%p-%%Y%%m%%d-%%H%%M%%S.mp4"
"@

try {
    [System.IO.File]::WriteAllText($outputPath, $batContent, [System.Text.Encoding]::ASCII)
    Write-Log "  qualityrun.bat generado correctamente en: $outputPath"
    if ($LogFile) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [OK] qualityrun.bat con URL: $safeUrl" | Out-File $LogFile -Append -Encoding UTF8 }
} catch {
    Write-Log "  ERROR al escribir qualityrun.bat: $_"
    exit 1
}
