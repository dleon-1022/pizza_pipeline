# setup.ps1
# Configuracion automatica de Pizza Pipeline
# Requisito: correr como Administrador DESPUES de clonar el repo
# y de haber pegado google_key.json en C:\pizza_pipeline\
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File C:\pizza_pipeline\setup.ps1

Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$PIPELINE    = "C:\pizza_pipeline"
$DOCS        = "C:\Users\gritseeuser1\Documents"
$REPO_URL    = "https://github.com/dleon-1022/pizza-pipeline.git"
$PY_VERSION  = "3.14.4"
$NODE_VERSION = "22.22.0"

# =====================================================
#  VERIFICAR ADMINISTRADOR
# =====================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Relanzando como administrador..." -ForegroundColor Yellow
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# =====================================================
#  LOG INTERNO
# =====================================================
$log = @{
    fecha    = (Get-Date -Format "yyyy-MM-dd HH:mm")
    slug     = ""
    locacion = ""
    estado   = "OK"
    python   = "?"
    node     = "?"
    vcpp     = "?"
    pip      = "?"
    npm      = "?"
    tareas   = ""
    detalle  = ""
}

$errores = @()

function Add-Error { param([string]$msg) $script:errores += $msg; $script:log.estado = "PARCIAL" }

# =====================================================
#  HELPERS
# =====================================================
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

function Invoke-WithRetry {
    param([scriptblock]$Action, [string]$Name, [int]$Retries = 3, [int]$Delay = 8)
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $result = & $Action
            return $true
        } catch {
            $msg = $_.Exception.Message
            if ($i -lt $Retries) {
                Write-Host "    Intento $i/$Retries fallo ($msg). Reintentando en ${Delay}s..." -ForegroundColor Yellow
                Start-Sleep -Seconds $Delay
            } else {
                Write-Host "    ERROR en $Name tras $Retries intentos: $msg" -ForegroundColor Red
                Add-Error "$Name FALLO: $msg"
                return $false
            }
        }
    }
}

function Download-File {
    param([string]$Uri, [string]$OutFile, [string]$Name)
    Invoke-WithRetry -Name "Descarga $Name" -Action {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 120
        if (-not (Test-Path $OutFile)) { throw "Archivo no descargado" }
    }
}

# =====================================================
#  PANTALLA INICIAL
# =====================================================
Clear-Host
Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "    GRITSEE - SETUP AUTOMATICO PIZZA PIPELINE" -ForegroundColor Cyan
Write-Host "  ============================================="
Write-Host ""
Write-Host "  Antes de continuar asegurate de haber pegado" -ForegroundColor Yellow
Write-Host "  google_key.json en C:\pizza_pipeline\       " -ForegroundColor Yellow
Write-Host ""

# =====================================================
#  PEDIR SLUG Y CONTRASENA PRIMERO
# =====================================================
do {
    $Slug = (Read-Host "  Slug de locacion (ej: pcsapi-benavides-abc123)").Trim()
} while ($Slug -eq "")

$secPass = Read-Host "  Contrasena de gritseeuser1" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass)
$Pass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

$log.slug = $Slug
# Extraer nombre legible: pcsapi-sol-de-oriente-abc123 -> Sol De Oriente
$sinPrefix = $Slug -replace "^[^-]+-", ""
$sinId     = $sinPrefix -replace "-[0-9a-f]{16,}$", ""
$log.locacion = ($sinId -split "-" | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -join " "

Write-Host ""
Write-Host "  Locacion detectada: $($log.locacion)" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Iniciando configuracion. No cierres esta ventana..." -ForegroundColor Green
Write-Host ""

# =====================================================
#  1. PYTHON
# =====================================================
Write-Host "  [1/7] Python $PY_VERSION..." -NoNewline

$pyOk = $false
$pyCmd = Get-Command python -ErrorAction SilentlyContinue
if ($pyCmd) {
    try {
        $pyVer = (python --version 2>&1) -replace "Python ", ""
        if ([Version]$pyVer -ge [Version]$PY_VERSION) {
            Write-Host " ya instalado ($pyVer)" -ForegroundColor Green
            $log.python = "OK ($pyVer)"
            $pyOk = $true
        } else {
            Write-Host " actualizando ($pyVer -> $PY_VERSION)..." -ForegroundColor Yellow
        }
    } catch {}
}

if (-not $pyOk) {
    $pyInst = "$env:TEMP\python_setup.exe"
    $ok = Download-File -Uri "https://www.python.org/ftp/python/$PY_VERSION/python-$PY_VERSION-amd64.exe" `
                        -OutFile $pyInst -Name "Python"
    if ($ok) {
        $r = Invoke-WithRetry -Name "Instalar Python" -Action {
            Start-Process $pyInst -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait -PassThru | Out-Null
        }
        if ($r) { Write-Host " instalado" -ForegroundColor Green; $log.python = "Instalado $PY_VERSION" }
        else     { $log.python = "ERROR instalacion" }
    } else { $log.python = "ERROR descarga" }
}

Refresh-Path

# =====================================================
#  2. NODE.JS
# =====================================================
Write-Host "  [2/7] Node.js v$NODE_VERSION..." -NoNewline

$nodeOk = $false
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
    try {
        $nodeVer = (node --version 2>&1) -replace "v", ""
        if ([Version]$nodeVer -ge [Version]$NODE_VERSION) {
            Write-Host " ya instalado (v$nodeVer)" -ForegroundColor Green
            $log.node = "OK (v$nodeVer)"
            $nodeOk = $true
        } else {
            Write-Host " actualizando (v$nodeVer -> v$NODE_VERSION)..." -ForegroundColor Yellow
        }
    } catch {}
}

if (-not $nodeOk) {
    $nodeInst = "$env:TEMP\node_setup.msi"
    $ok = Download-File -Uri "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-x64.msi" `
                        -OutFile $nodeInst -Name "Node.js"
    if ($ok) {
        $r = Invoke-WithRetry -Name "Instalar Node.js" -Action {
            Start-Process msiexec -ArgumentList "/i `"$nodeInst`" /quiet /norestart ADDLOCAL=ALL" -Wait | Out-Null
        }
        if ($r) { Write-Host " instalado" -ForegroundColor Green; $log.node = "Instalado v$NODE_VERSION" }
        else     { $log.node = "ERROR instalacion" }
    } else { $log.node = "ERROR descarga" }
}

Refresh-Path

# =====================================================
#  3. VISUAL C++
# =====================================================
Write-Host "  [3/7] Visual C++ Redistributable..." -NoNewline

$vcKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
if ($vcKey -and $vcKey.Installed -eq 1) {
    Write-Host " ya instalado" -ForegroundColor Green
    $log.vcpp = "OK"
} else {
    $vcInst = "$env:TEMP\vc_redist.exe"
    $ok = Download-File -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
                        -OutFile $vcInst -Name "VC++"
    if ($ok) {
        $r = Invoke-WithRetry -Name "Instalar VC++" -Action {
            Start-Process $vcInst -ArgumentList "/quiet /norestart" -Wait | Out-Null
        }
        if ($r) { Write-Host " instalado" -ForegroundColor Green; $log.vcpp = "Instalado" }
        else     { $log.vcpp = "ERROR" }
    } else { $log.vcpp = "ERROR descarga" }
}

# =====================================================
#  4. PIP INSTALL
# =====================================================
Write-Host "  [4/7] Dependencias Python (pip)..." -NoNewline
$r = Invoke-WithRetry -Name "pip install" -Action {
    $out = pip install -r "$PIPELINE\scripts\requirements.txt" -q 2>&1
    if ($LASTEXITCODE -ne 0) { throw $out }
}
if ($r) { Write-Host " OK" -ForegroundColor Green; $log.pip = "OK" }
else    { $log.pip = "ERROR" }

# =====================================================
#  5. NPM INSTALL
# =====================================================
Write-Host "  [5/7] Dependencias Node.js (npm)..." -NoNewline
$r = Invoke-WithRetry -Name "npm install" -Action {
    Push-Location $PIPELINE
    $out = npm install --silent 2>&1
    Pop-Location
    if ($LASTEXITCODE -ne 0) { throw $out }
}
if ($r) { Write-Host " OK" -ForegroundColor Green; $log.npm = "OK" }
else    { $log.npm = "ERROR" }

# =====================================================
#  6. ARCHIVOS Y SLUG
# =====================================================
Write-Host "  [6/7] Configurando archivos..."

# Crear carpeta qualityvids
New-Item -ItemType Directory -Path "$DOCS\qualityvids" -Force | Out-Null

# Copiar video files sin sobreescribir
foreach ($file in @("qualityrun.bat", "deletequality.bat")) {
    $src = "$PIPELINE\video\$file"
    $dst = "$DOCS\$file"
    if ((Test-Path $src) -and -not (Test-Path $dst)) {
        Copy-Item $src $dst -Force
        Write-Host "    Copiado: $file" -ForegroundColor Green
    } elseif (Test-Path $dst) {
        Write-Host "    Ya existe: $file" -ForegroundColor DarkGray
    }
}

# Guardar slug
Set-Content -Path "$PIPELINE\location_slug.txt" -Value $Slug -NoNewline
Write-Host "    Slug guardado: $Slug" -ForegroundColor Green

# =====================================================
#  7. TAREAS PROGRAMADAS
# =====================================================
Write-Host "  [7/7] Creando tareas programadas..."

$tareasLog = @()
$tareas = @(
    @{ xml = "Daily Pizza Pipeline.xml"; name = "Daily Pizza Pipeline" },
    @{ xml = "Quality run.xml";          name = "Quality run"          },
    @{ xml = "Quality delete.xml";       name = "Quality delete"       }
)

foreach ($t in $tareas) {
    $xmlPath = "$PIPELINE\video\$($t.xml)"
    if (-not (Test-Path $xmlPath)) {
        Write-Host "    FALTA XML: $($t.xml)" -ForegroundColor Red
        $tareasLog += "$($t.name):SIN XML"
        Add-Error "Falta $($t.xml)"
        continue
    }

    $existe = Get-ScheduledTask -TaskPath "\Gritsee\" -TaskName $t.name -ErrorAction SilentlyContinue

    if ($existe) {
        # Tarea existe — solo verificar ruta y usuario
        $accion  = $existe.Actions | Select-Object -First 1
        $usuario = $existe.Principal.UserId

        $rutaOk    = ($accion.Execute -like "*$($t.name.Replace(' ','*'))*") -or
                     ($accion.Execute -like "*gritseeuser1*") -or
                     ($accion.Arguments -like "*pizza_pipeline*") -or
                     ($accion.Execute -like "*pizza_pipeline*") -or
                     ($accion.Execute -like "*qualityrun*") -or
                     ($accion.Execute -like "*deletequality*")
        $usuarioOk = $usuario -eq "gritseeuser1"

        if ($rutaOk -and $usuarioOk) {
            Write-Host "    OK (existia, verificada): $($t.name)" -ForegroundColor Green
            $tareasLog += "$($t.name):OK-existia"
        } else {
            Write-Host "    AVISO (existia, ruta o usuario diferente): $($t.name)" -ForegroundColor Yellow
            Write-Host "      Usuario: $usuario | Comando: $($accion.Execute)" -ForegroundColor DarkGray
            $tareasLog += "$($t.name):AVISO-verificar"
        }
    } else {
        # Tarea no existe — crearla
        $r = Invoke-WithRetry -Name "Tarea $($t.name)" -Retries 2 -Delay 3 -Action {
            schtasks /Create /XML $xmlPath /TN "\Gritsee\$($t.name)" /RU gritseeuser1 /RP $Pass /F 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "schtasks retorno $LASTEXITCODE" }
        }
        if ($r) {
            Write-Host "    OK (nueva): $($t.name)" -ForegroundColor Green
            $tareasLog += "$($t.name):nueva"
        } else {
            Write-Host "    ERROR creando: $($t.name)" -ForegroundColor Red
            $tareasLog += "$($t.name):ERROR"
            Add-Error "No se pudo crear tarea $($t.name)"
        }
    }
}

$log.tareas = $tareasLog -join " | "

# =====================================================
#  SUBIR LOG A GOOGLE SHEETS
# =====================================================
Write-Host ""
Write-Host "  Subiendo log a Google Sheets..." -NoNewline

if ($errores.Count -gt 0) {
    $log.estado  = "PARCIAL"
    $log.detalle = $errores -join " | "
} else {
    $log.estado  = "OK"
    $log.detalle = "Configuracion exitosa"
}

$jsonLog  = $log | ConvertTo-Json -Compress
$jsonFile = "$env:TEMP\gritsee_deploy_log.json"
[System.IO.File]::WriteAllText($jsonFile, $jsonLog, [System.Text.Encoding]::UTF8)

$logOk = Invoke-WithRetry -Name "Subir log" -Retries 3 -Delay 5 -Action {
    $out = node "$PIPELINE\scripts\log_deploy.js" $jsonFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw $out }
}

if ($logOk) { Write-Host " OK" -ForegroundColor Green }
else        { Write-Host " no se pudo subir (revisa google_key.json)" -ForegroundColor Yellow }

# =====================================================
#  RESUMEN FINAL
# =====================================================
Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
if ($log.estado -eq "OK") {
    Write-Host "    SETUP COMPLETADO SIN ERRORES" -ForegroundColor Green
} else {
    Write-Host "    SETUP COMPLETADO CON AVISOS" -ForegroundColor Yellow
    foreach ($e in $errores) {
        Write-Host "    - $e" -ForegroundColor Yellow
    }
}
Write-Host "  ============================================="
Write-Host ""
Write-Host "  PENDIENTE MANUAL:"
Write-Host "  - Editar qualityrun.bat con el RTSP de la camara" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Log subido a Google Sheets > pestaña Deployments"
Write-Host ""
Read-Host "  Presiona Enter para cerrar"
