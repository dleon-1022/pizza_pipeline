$ErrorActionPreference = "Stop"

$RepoUrl       = "https://github.com/dleon-1022/pizza-pipeline.git"
$RepoZipUrl    = "https://github.com/dleon-1022/pizza-pipeline/archive/refs/heads/main.zip"
$PipelineDir   = "C:\pizza_pipeline"
$LegacyDir     = "C:\pizza-pipeline"
$DocsDir       = "C:\Users\gritseeuser1\Documents"
$LogFile       = Join-Path $env:USERPROFILE "Desktop\gritsee_configuracion.log"
$PythonVersion = "3.13.3"
$NodeVersion   = "22.16.0"

$Options = @{
    Auto          = $false
    Tipo          = ""
    Slug          = ""
    PcPass        = ""
    CamUser       = ""
    CamPass       = ""
    CamIp         = ""
    CamPort       = "554"
    CamMarca      = ""
    CamCanal      = "1"
    RtspUrl       = ""
    CleanupLegacy = $false
    SkipSync      = $false
    SkipVerify    = $false
}

foreach ($arg in $args) {
    if ($arg -ieq "/auto") { $Options.Auto = $true; continue }
    if ($arg -ieq "/cleanup_legacy") { $Options.CleanupLegacy = $true; continue }
    if ($arg -ieq "/skip_sync") { $Options.SkipSync = $true; continue }
    if ($arg -ieq "/skip_verify") { $Options.SkipVerify = $true; continue }

    if ($arg -imatch "^/tipo:(.*)$") { $Options.Tipo = $Matches[1]; continue }
    if ($arg -imatch "^/slug:(.*)$") { $Options.Slug = $Matches[1]; continue }
    if ($arg -imatch "^/pass:(.*)$") { $Options.PcPass = $Matches[1]; continue }
    if ($arg -imatch "^/cam_user:(.*)$") { $Options.CamUser = $Matches[1]; continue }
    if ($arg -imatch "^/cam_pass:(.*)$") { $Options.CamPass = $Matches[1]; continue }
    if ($arg -imatch "^/cam_ip:(.*)$") { $Options.CamIp = $Matches[1]; continue }
    if ($arg -imatch "^/cam_port:(.*)$") { $Options.CamPort = $Matches[1]; continue }
    if ($arg -imatch "^/cam_marca:(.*)$") { $Options.CamMarca = $Matches[1]; continue }
    if ($arg -imatch "^/cam_canal:(.*)$") { $Options.CamCanal = $Matches[1]; continue }
    if ($arg -imatch "^/rtsp:(.*)$") { $Options.RtspUrl = $Matches[1]; continue }
}

function Write-Log {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host $Message -ForegroundColor $Color
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File $LogFile -Append -Encoding UTF8
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Este configurador debe ejecutarse como administrador."
    }
}

function Read-Required {
    param([string]$Prompt)

    do {
        $value = Read-Host $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value.Trim()
}

function Read-SecretText {
    param([string]$Prompt)

    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-ExistingSlug {
    $slugFile = Join-Path $PipelineDir "location_slug.txt"
    if (Test-Path $slugFile) {
        return (Get-Content -Raw -LiteralPath $slugFile).Trim()
    }

    return ""
}

function Ask-InteractiveOptions {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host "         GRITSEE - PIZZA QUALITY" -ForegroundColor Cyan
    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    [1]  Actualizar"
    Write-Host "    [2]  Configuracion nueva"
    Write-Host ""

    $choice = Read-Required "  Selecciona una opcion [1 o 2]"
    if ($choice -eq "1") {
        $Options.Tipo = "actualizar"
    } elseif ($choice -eq "2") {
        $Options.Tipo = "nueva"
    } else {
        throw "Opcion no valida."
    }

    Write-Host ""
    Write-Host "  Responde ahora todo lo necesario; despues el proceso corre solo." -ForegroundColor Yellow
    Write-Host ""

    if ($Options.Tipo -ieq "nueva") {
        $Options.PcPass = Read-SecretText "  Contrasena del usuario gritseeuser1"
        $Options.Slug = Read-Required "  Slug de locacion (ej: pcsapi-cardenas)"
        $Options.CamMarca = Read-Required "  Marca [1 Hikvision, 2 Dahua, 3 Anpviz, 4 Reolink, 5 UNV, 6 Hanwha, 7 Tapo, 8 Axis, 9 Bosch, 10 URL manual]"

        if ($Options.CamMarca -eq "10") {
            $Options.RtspUrl = Read-Required "  URL RTSP completa"
        } else {
            $Options.CamUser = Read-Required "  Usuario de la camara"
            $Options.CamPass = Read-SecretText "  Contrasena de la camara"
            $Options.CamIp = Read-Required "  IP de la camara"
            $port = Read-Host "  Puerto RTSP (Enter para 554)"
            if (-not [string]::IsNullOrWhiteSpace($port)) { $Options.CamPort = $port.Trim() }
            $channel = Read-Host "  Canal de video (Enter para 1)"
            if (-not [string]::IsNullOrWhiteSpace($channel)) { $Options.CamCanal = $channel.Trim() }
        }
    } else {
        $currentSlug = Get-ExistingSlug
        if ($currentSlug) {
            Write-Host "  Slug actual: $currentSlug"
            $changeSlug = Read-Host "  Cambiar slug? [s/N]"
            if ($changeSlug -ieq "s") {
                $Options.Slug = Read-Required "  Nuevo slug"
            }
        } else {
            $Options.Slug = Read-Required "  No hay slug. Ingresa slug de locacion"
        }

        $recreateTasks = Read-Host "  Recrear tareas programadas? [S/n]"
        if ($recreateTasks -notin @("n", "N")) {
            $Options.PcPass = Read-SecretText "  Contrasena del usuario gritseeuser1"
        }

        $reconfigureCamera = Read-Host "  Reconfigurar camara RTSP? [s/N]"
        if ($reconfigureCamera -ieq "s") {
            $Options.CamMarca = Read-Required "  Marca [1-10]"
            if ($Options.CamMarca -eq "10") {
                $Options.RtspUrl = Read-Required "  URL RTSP completa"
            } else {
                $Options.CamUser = Read-Required "  Usuario de la camara"
                $Options.CamPass = Read-SecretText "  Contrasena de la camara"
                $Options.CamIp = Read-Required "  IP de la camara"
                $port = Read-Host "  Puerto RTSP (Enter para 554)"
                if (-not [string]::IsNullOrWhiteSpace($port)) { $Options.CamPort = $port.Trim() }
                $channel = Read-Host "  Canal de video (Enter para 1)"
                if (-not [string]::IsNullOrWhiteSpace($channel)) { $Options.CamCanal = $channel.Trim() }
            }
        }
    }

    Write-Host ""
    Write-Host "  Listo. Presiona Enter y puedes dejar esta PC corriendo." -ForegroundColor Green
    Read-Host | Out-Null
}

function Ensure-Workspace {
    New-Item -ItemType Directory -Path $PipelineDir -Force | Out-Null
    New-Item -ItemType Directory -Path $DocsDir -Force | Out-Null
    foreach ($dir in @("frames", "cropped_frames", "selected_frames", "models", "uploads")) {
        New-Item -ItemType Directory -Path (Join-Path $PipelineDir $dir) -Force | Out-Null
    }
}

function Copy-RuntimeFiles {
    param([string]$FromDir, [string]$ToDir)

    foreach ($file in @("google_key.json", "location_slug.txt", "processed_videos.txt")) {
        $source = Join-Path $FromDir $file
        $target = Join-Path $ToDir $file
        if ((Test-Path $source) -and -not (Test-Path $target)) {
            Copy-Item -LiteralPath $source -Destination $target -Force
            Write-Log "  Migrado $file desde $FromDir"
        }
    }
}

function Migrate-LegacyFolder {
    if (-not (Test-Path $LegacyDir)) { return }

    Write-Log "  Carpeta antigua detectada: $LegacyDir" Yellow
    Ensure-Workspace
    Copy-RuntimeFiles -FromDir $LegacyDir -ToDir $PipelineDir

    if ($Options.CleanupLegacy) {
        Write-Log "  Eliminando carpeta antigua: $LegacyDir" Yellow
        Remove-Item -LiteralPath $LegacyDir -Recurse -Force
    } else {
        Write-Log "  Carpeta antigua conservada. Usa /cleanup_legacy para eliminarla despues de migrar." Yellow
    }
}

function Sync-Code {
    Write-Log "  Sincronizando codigo en $PipelineDir..."
    Ensure-Workspace

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and (Test-Path (Join-Path $PipelineDir ".git"))) {
        Push-Location $PipelineDir
        try {
            & git remote set-url origin $RepoUrl >> $LogFile 2>&1
            & git pull --ff-only >> $LogFile 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "  Git pull completado." Green
                return
            }

            Write-Log "  Git pull fallo; usando descarga ZIP como respaldo." Yellow
        } finally {
            Pop-Location
        }
    }

    $zip = Join-Path $env:TEMP "pizza_pipeline_main.zip"
    $extract = Join-Path $env:TEMP "pizza_pipeline_main"
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue

    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $sourceRoot = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
    if (-not $sourceRoot) { throw "No se pudo extraer el ZIP del repo." }

    Copy-Item -Path (Join-Path $sourceRoot.FullName "*") -Destination $PipelineDir -Recurse -Force
    Write-Log "  Codigo actualizado desde ZIP." Green
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Test-Executable {
    param([string]$Path, [string[]]$Args)

    if (-not $Path -or -not (Test-Path $Path)) { return $false }

    try {
        & $Path @Args > $null 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Get-PythonExe {
    $candidates = @()
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    $candidates += @(
        "C:\Program Files\Python314\python.exe",
        "C:\Program Files\Python313\python.exe",
        "C:\Program Files\Python312\python.exe",
        "C:\Program Files\Python311\python.exe"
    )

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Executable -Path $candidate -Args @("--version")) {
            return $candidate
        }
    }

    return ""
}

function Get-NpmExe {
    $candidates = @()
    $cmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    $candidates += "C:\Program Files\nodejs\npm.cmd"

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Executable -Path $candidate -Args @("--version")) {
            return $candidate
        }
    }

    return ""
}

function Install-SystemDependencies {
    if ($Options.Tipo -ine "nueva") {
        return
    }

    $tempSetup = Join-Path $env:TEMP "gritsee_setup"
    New-Item -ItemType Directory -Path $tempSetup -Force | Out-Null

    try {
        if (-not (Get-PythonExe)) {
            Write-Log "  Descargando Python $PythonVersion..."
            $pythonInstaller = Join-Path $tempSetup "python_setup.exe"
            Invoke-WebRequest -Uri "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe" -OutFile $pythonInstaller -UseBasicParsing
            Write-Log "  Instalando Python..."
            $p = Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "Instalador de Python fallo con codigo $($p.ExitCode)." }
            Refresh-Path
        } else {
            Write-Log "  Python ya esta instalado." Green
        }

        if (-not (Get-NpmExe)) {
            Write-Log "  Descargando Node.js $NodeVersion..."
            $nodeInstaller = Join-Path $tempSetup "node_setup.msi"
            Invoke-WebRequest -Uri "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-x64.msi" -OutFile $nodeInstaller -UseBasicParsing
            Write-Log "  Instalando Node.js..."
            $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$nodeInstaller`" /quiet /norestart ADDLOCAL=ALL" -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "Instalador de Node.js fallo con codigo $($p.ExitCode)." }
            Refresh-Path
        } else {
            Write-Log "  Node.js ya esta instalado." Green
        }

        Write-Log "  Instalando Visual C++ Redistributable..."
        $vcInstaller = Join-Path $tempSetup "vc_redist.exe"
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $vcInstaller -UseBasicParsing
        $p = Start-Process -FilePath $vcInstaller -ArgumentList "/quiet /norestart" -Wait -PassThru
        if ($p.ExitCode -notin @(0, 3010)) { throw "Instalador de VC++ fallo con codigo $($p.ExitCode)." }
    } finally {
        Remove-Item -LiteralPath $tempSetup -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-ProjectDependencies {
    $python = Get-PythonExe
    if (-not $python) { throw "Python no esta disponible en PATH ni en Program Files." }

    $npm = Get-NpmExe
    if (-not $npm) { throw "npm.cmd no esta disponible. Revisa instalacion de Node.js." }

    Write-Log "  Instalando dependencias Python..."
    & $python -m pip install --upgrade pip setuptools wheel -q >> $LogFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "No se pudo actualizar pip/setuptools/wheel." }

    & $python -m pip install torch==2.11.0 torchvision==0.26.0 --index-url https://download.pytorch.org/whl/cpu >> $LogFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "No se pudo instalar PyTorch CPU." }

    & $python -m pip install -r (Join-Path $PipelineDir "requirements.txt") --prefer-binary >> $LogFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "No se pudieron instalar todas las dependencias Python." }
    Write-Log "  Dependencias Python OK." Green

    Write-Log "  Instalando dependencias Node.js..."
    Push-Location $PipelineDir
    try {
        & $npm install >> $LogFile 2>&1
        if ($LASTEXITCODE -ne 0) { throw "npm install fallo." }
    } finally {
        Pop-Location
    }
    Write-Log "  Dependencias Node.js OK." Green
}

function Save-Slug {
    if ([string]::IsNullOrWhiteSpace($Options.Slug)) { return }

    Set-Content -LiteralPath (Join-Path $PipelineDir "location_slug.txt") -Value $Options.Slug.Trim() -NoNewline -Encoding UTF8
    Write-Log "  Slug guardado: $($Options.Slug)" Green
}

function Configure-CameraIfNeeded {
    $hasCameraConfig = -not [string]::IsNullOrWhiteSpace($Options.CamMarca) -or -not [string]::IsNullOrWhiteSpace($Options.RtspUrl)
    if ($Options.Tipo -ieq "actualizar" -and -not $hasCameraConfig) {
        Write-Log "  Camara sin cambios." Yellow
        return
    }

    Write-Log "  Configurando camara RTSP..."
    $setupCamera = Join-Path $PipelineDir "setup_camera.ps1"
    $cameraArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $setupCamera,
        "-LogFile", $LogFile,
        "-BrandNum", $Options.CamMarca,
        "-CamUser", $Options.CamUser,
        "-CamPass", $Options.CamPass,
        "-CamIp", $Options.CamIp,
        "-CamPort", $Options.CamPort,
        "-Channel", $Options.CamCanal,
        "-RtspUrl", $Options.RtspUrl
    )
    & powershell @cameraArgs
    if ($LASTEXITCODE -ne 0) { throw "No se pudo configurar la camara RTSP." }
    Write-Log "  Camara RTSP OK." Green
}

function Configure-DeleteQuality {
    New-Item -ItemType Directory -Path $DocsDir -Force | Out-Null
    $deleteQuality = Join-Path $DocsDir "deletequality.bat"
    $content = @(
        "@echo off",
        'del /S /Q "C:\Users\gritseeuser1\Documents\qualityvids\*"'
    )
    Set-Content -LiteralPath $deleteQuality -Value $content -Encoding ASCII
    Write-Log "  deletequality.bat OK." Green
}

function Configure-TasksIfNeeded {
    if ([string]::IsNullOrWhiteSpace($Options.PcPass)) {
        Write-Log "  Tareas no recreadas: no se recibio contrasena de PC." Yellow
        return
    }

    Write-Log "  Creando/verificando tareas programadas..."
    $tempPassword = Join-Path $env:TEMP "gritsee_pwd.tmp"
    try {
        [IO.File]::WriteAllText($tempPassword, $Options.PcPass.Trim(), [Text.Encoding]::UTF8)
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PipelineDir "create_tasks.ps1") -PasswordFile $tempPassword >> $LogFile 2>&1
        if ($LASTEXITCODE -ne 0) { throw "create_tasks.ps1 fallo." }
    } finally {
        Remove-Item -LiteralPath $tempPassword -Force -ErrorAction SilentlyContinue
    }
    Write-Log "  Tareas programadas OK." Green
}

function Run-Verification {
    if ($Options.SkipVerify) { return }

    $verifyScript = Join-Path $PipelineDir "verify_pipeline.ps1"
    if (-not (Test-Path $verifyScript)) {
        Write-Log "  No existe verify_pipeline.ps1; se omite verificacion." Yellow
        return
    }

    Write-Log "  Verificando pipeline..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyScript -LogFile (Join-Path $PipelineDir "verify_pipeline.log") >> $LogFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "La verificacion del pipeline encontro problemas." }
    Write-Log "  Verificacion OK." Green
}

function Validate-Options {
    if ($Options.Tipo -ieq "nueva") {
        if ([string]::IsNullOrWhiteSpace($Options.Slug)) { throw "Falta slug de locacion." }
        if ([string]::IsNullOrWhiteSpace($Options.PcPass)) { throw "Falta contrasena de PC para crear tareas." }
        if ([string]::IsNullOrWhiteSpace($Options.CamMarca) -and [string]::IsNullOrWhiteSpace($Options.RtspUrl)) {
            throw "Falta configuracion de camara."
        }
    }

    if ($Options.CamMarca -eq "10" -and [string]::IsNullOrWhiteSpace($Options.RtspUrl)) {
        throw "Marca 10 requiere /rtsp:<url>."
    }
}

try {
    Assert-Admin
    if (-not $Options.Auto) { Ask-InteractiveOptions }
    if ([string]::IsNullOrWhiteSpace($Options.Tipo)) { throw "Falta /tipo:nueva o /tipo:actualizar." }
    if ($Options.Tipo -notin @("nueva", "actualizar")) { throw "Tipo invalido: $($Options.Tipo)" }
    Validate-Options

    "============================================================" | Out-File $LogFile -Encoding UTF8
    "GRITSEE - CONFIGURACION $($Options.Tipo.ToUpper())" | Out-File $LogFile -Append -Encoding UTF8
    "Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $LogFile -Append -Encoding UTF8
    "============================================================" | Out-File $LogFile -Append -Encoding UTF8

    Write-Log ""
    Write-Log "  =============================================================" Cyan
    Write-Log "         GRITSEE - PIZZA QUALITY" Cyan
    Write-Log "  =============================================================" Cyan
    Write-Log "  Modo: $($Options.Tipo)"

    Ensure-Workspace
    Migrate-LegacyFolder
    if ($Options.SkipSync) {
        Write-Log "  Sincronizacion de codigo omitida por /skip_sync." Yellow
    } else {
        Sync-Code
    }
    Save-Slug
    Install-SystemDependencies
    Install-ProjectDependencies
    Configure-DeleteQuality
    Configure-CameraIfNeeded
    Configure-TasksIfNeeded
    Run-Verification

    Write-Log ""
    Write-Log "  CONFIGURACION COMPLETADA" Green
    Write-Log "  Pipeline: $PipelineDir" Green
    Write-Log "  Log: $LogFile" Green
    exit 0
} catch {
    Write-Log ""
    Write-Log "  ERROR: $($_.Exception.Message)" Red
    Write-Log "  Revisa el log: $LogFile" Red
    exit 1
}
