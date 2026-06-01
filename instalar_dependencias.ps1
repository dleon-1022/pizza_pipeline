# instalar_dependencias.ps1
# Instala Python 3.14.4, Node.js 22.16.0, VC++ Redistributable
# y las dependencias pip y npm del pipeline.
# Ejecutar como Administrador en C:\pizza_pipeline

$ErrorActionPreference = "Stop"
$PipelineDir = "C:\pizza_pipeline"
$tmp = $env:TEMP

function Write-Step { param([string]$msg) Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Skip { param([string]$msg) Write-Host "    [--] $msg (ya instalado)" -ForegroundColor Yellow }

# -------------------------------------------------------
# 1. Python 3.14.4
# -------------------------------------------------------
Write-Step "Python 3.14.4"
$pythonExe = $null
foreach ($p in @(
    "C:\Program Files\Python314\python.exe",
    "$env:USERPROFILE\AppData\Local\Programs\Python\Python314\python.exe",
    "C:\Users\gritseeuser1\AppData\Local\Programs\Python\Python314\python.exe"
)) { if (Test-Path $p) { $pythonExe = $p; break } }

if (-not $pythonExe) {
    try { $pythonExe = (Get-Command python -ErrorAction Stop).Source } catch {}
}

if ($pythonExe) {
    Write-Skip "Python encontrado en $pythonExe"
} else {
    Write-Host "    Descargando Python 3.14.4..." -ForegroundColor White
    $installer = "$tmp\python_setup.exe"
    Invoke-WebRequest "https://www.python.org/ftp/python/3.14.4/python-3.14.4-amd64.exe" -OutFile $installer -UseBasicParsing
    $p = Start-Process $installer "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait -PassThru
    if ($p.ExitCode -notin @(0,1638)) { throw "Python fallo con codigo $($p.ExitCode)" }
    $pythonExe = "C:\Program Files\Python314\python.exe"
    Write-OK "Python instalado"
}

# -------------------------------------------------------
# 2. Node.js 22.16.0
# -------------------------------------------------------
Write-Step "Node.js 22.16.0"
$nodeExe = "C:\Program Files\nodejs\node.exe"
if (Test-Path $nodeExe) {
    Write-Skip "Node.js encontrado"
} else {
    Write-Host "    Descargando Node.js 22.16.0..." -ForegroundColor White
    $installer = "$tmp\node_setup.msi"
    Invoke-WebRequest "https://nodejs.org/dist/v22.16.0/node-v22.16.0-x64.msi" -OutFile $installer -UseBasicParsing
    $p = Start-Process msiexec "/i `"$installer`" /quiet /norestart ADDLOCAL=ALL" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Node.js fallo con codigo $($p.ExitCode)" }
    Write-OK "Node.js instalado"
}

# -------------------------------------------------------
# 3. Visual C++ Redistributable
# -------------------------------------------------------
Write-Step "Visual C++ Redistributable"
Write-Host "    Descargando VC++..." -ForegroundColor White
$installer = "$tmp\vc_redist.exe"
Invoke-WebRequest "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $installer -UseBasicParsing
$p = Start-Process $installer "/quiet /norestart" -Wait -PassThru
if ($p.ExitCode -notin @(0,3010,1638)) { throw "VC++ fallo con codigo $($p.ExitCode)" }
Write-OK "VC++ listo"

# -------------------------------------------------------
# Refrescar PATH
# -------------------------------------------------------
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

# -------------------------------------------------------
# 4. Dependencias Python (pip)
# -------------------------------------------------------
Write-Step "Dependencias Python (pip)"
& $pythonExe -m pip install --upgrade pip setuptools wheel -q
& $pythonExe -m pip install torch==2.11.0 torchvision==0.26.0 --index-url https://download.pytorch.org/whl/cpu
& $pythonExe -m pip install -r "$PipelineDir\scripts\requirements.txt" --prefer-binary
Write-OK "Dependencias Python instaladas"

# -------------------------------------------------------
# 5. Dependencias Node (npm)
# -------------------------------------------------------
Write-Step "Dependencias Node.js (npm)"
Push-Location $PipelineDir
npm install
Pop-Location
Write-OK "Dependencias Node.js instaladas"

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  INSTALACION COMPLETADA" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan
