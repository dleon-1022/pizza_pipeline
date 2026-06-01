$ErrorActionPreference = "Stop"

$RepoZipUrl  = "https://github.com/dleon-1022/pizza_pipeline/archive/refs/heads/main.zip"
$PipelineDir = "C:\pizza_pipeline"
$LegacyDir   = "C:\pizza-pipeline"   # repo anterior (con guion)
$DocsDir     = "C:\Users\gritseeuser1\Documents"
$LogFile     = Join-Path $env:USERPROFILE "Desktop\gritsee_configuracion.log"

$Options = @{
    Auto    = $false
    Tipo    = ""
    Slug    = ""
    PcPass  = ""
    CamUser = ""
    CamPass = ""
    CamIp   = ""
    CamPort = "554"
    CamMarca= ""
    CamCanal= "1"
    RtspUrl = ""
    SkipSync= $false
}

foreach ($arg in $args) {
    if ($arg -ieq "/auto")        { $Options.Auto     = $true;          continue }
    if ($arg -ieq "/skip_sync")   { $Options.SkipSync = $true;          continue }
    if ($arg -imatch "^/tipo:(.*)$")      { $Options.Tipo     = $Matches[1]; continue }
    if ($arg -imatch "^/slug:(.*)$")      { $Options.Slug     = $Matches[1]; continue }
    if ($arg -imatch "^/pass:(.*)$")      { $Options.PcPass   = $Matches[1]; continue }
    if ($arg -imatch "^/cam_user:(.*)$")  { $Options.CamUser  = $Matches[1]; continue }
    if ($arg -imatch "^/cam_pass:(.*)$")  { $Options.CamPass  = $Matches[1]; continue }
    if ($arg -imatch "^/cam_ip:(.*)$")    { $Options.CamIp    = $Matches[1]; continue }
    if ($arg -imatch "^/cam_port:(.*)$")  { $Options.CamPort  = $Matches[1]; continue }
    if ($arg -imatch "^/cam_marca:(.*)$") { $Options.CamMarca = $Matches[1]; continue }
    if ($arg -imatch "^/cam_canal:(.*)$") { $Options.CamCanal = $Matches[1]; continue }
    if ($arg -imatch "^/rtsp:(.*)$")      { $Options.RtspUrl  = $Matches[1]; continue }
}

# -------------------------------------------------------
# Utilidades
# -------------------------------------------------------
function Write-Log {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Message -ForegroundColor $Color
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Out-File $LogFile -Append -Encoding UTF8
}

function Assert-Admin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Debe ejecutarse como Administrador."
    }
}

function Read-Required {
    param([string]$Prompt)
    do { $v = Read-Host $Prompt } while ([string]::IsNullOrWhiteSpace($v))
    return $v.Trim()
}

function Read-SecretText {
    param([string]$Prompt)
    $s = Read-Host $Prompt -AsSecureString
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# -------------------------------------------------------
# Preguntas interactivas
# -------------------------------------------------------
function Ask-InteractiveOptions {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host "         GRITSEE - PIZZA QUALITY" -ForegroundColor Cyan
    Write-Host "  =============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    [1]  Actualizar codigo"
    Write-Host "    [2]  Configuracion nueva"
    Write-Host ""

    $choice = Read-Required "  Selecciona [1 o 2]"
    if     ($choice -eq "1") { $Options.Tipo = "actualizar" }
    elseif ($choice -eq "2") { $Options.Tipo = "nueva" }
    else   { throw "Opcion no valida." }

    Write-Host ""
    Write-Host "  Responde ahora; luego el proceso corre solo." -ForegroundColor Yellow
    Write-Host ""

    if ($Options.Tipo -ieq "nueva") {
        $Options.PcPass  = Read-SecretText "  Contrasena de gritseeuser1"
        $Options.Slug    = Read-Required   "  Slug de locacion (ej: pcsapi-nombre-id)"
        $Options.CamMarca= Read-Required   "  Marca camara [1=Hikvision 2=Dahua 3=Anpviz 4=Reolink 5=UNV 6=Hanwha 7=Tapo 8=Axis 9=Bosch 10=URL manual]"

        if ($Options.CamMarca -eq "10") {
            $Options.RtspUrl = Read-Required "  URL RTSP completa"
        } else {
            $Options.CamUser = Read-Required   "  Usuario camara"
            $Options.CamPass = Read-SecretText "  Contrasena camara"
            $Options.CamIp   = Read-Required   "  IP camara"
            $p = Read-Host "  Puerto RTSP (Enter=554)"; if ($p) { $Options.CamPort = $p.Trim() }
            $c = Read-Host "  Canal video (Enter=1)";   if ($c) { $Options.CamCanal= $c.Trim() }
        }
    } else {
        # Actualizar: solo preguntar si quiere cambiar slug o recrear tareas
        $slugFile = Join-Path $PipelineDir "location_slug.txt"
        if (Test-Path $slugFile) {
            $current = (Get-Content -Raw $slugFile).Trim()
            Write-Host "  Slug actual: $current"
            $cs = Read-Host "  Cambiar slug? [s/N]"
            if ($cs -ieq "s") { $Options.Slug = Read-Required "  Nuevo slug" }
        } else {
            $Options.Slug = Read-Required "  No hay slug. Ingresa slug"
        }

        $rt = Read-Host "  Recrear tareas programadas? [S/n]"
        if ($rt -notin @("n","N")) {
            $Options.PcPass = Read-SecretText "  Contrasena de gritseeuser1"
        }
    }

    Write-Host ""
    Write-Host "  Listo. Presiona Enter y puedes dejar esta PC corriendo." -ForegroundColor Green
    Read-Host | Out-Null
}

# -------------------------------------------------------
# Workspace
# -------------------------------------------------------
function Ensure-Workspace {
    New-Item -ItemType Directory -Path $PipelineDir -Force | Out-Null
    New-Item -ItemType Directory -Path $DocsDir     -Force | Out-Null
    foreach ($d in @("frames","cropped_frames","selected_frames","models","uploads")) {
        New-Item -ItemType Directory -Path (Join-Path $PipelineDir $d) -Force | Out-Null
    }
}

# -------------------------------------------------------
# Sincronizar codigo desde GitHub
# -------------------------------------------------------
function Sync-Code {
    Write-Log "  Sincronizando codigo..."
    Ensure-Workspace

    # Intentar git pull si hay repo local
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and (Test-Path (Join-Path $PipelineDir ".git"))) {
        Push-Location $PipelineDir
        try {
            & git pull --ff-only >> $LogFile 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Log "  Codigo actualizado (git pull)." Green; return }
            Write-Log "  Git pull fallo; descargando ZIP..." Yellow
        } finally { Pop-Location }
    }

    # Fallback: descargar ZIP
    $zip     = Join-Path $env:TEMP "pizza_pipeline_main.zip"
    $extract = Join-Path $env:TEMP "pizza_pipeline_main"
    Remove-Item $zip     -Force -ErrorAction SilentlyContinue
    Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue

    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $src = Get-ChildItem $extract -Directory | Select-Object -First 1
    if (-not $src) { throw "No se pudo extraer ZIP del repo." }
    Copy-Item -Path (Join-Path $src.FullName "*") -Destination $PipelineDir -Recurse -Force
    Write-Log "  Codigo actualizado (ZIP)." Green
}

# -------------------------------------------------------
# Limpiar scripts viejos de la raiz (estructura anterior)
# -------------------------------------------------------
function Cleanup-OldRootScripts {
    $old = @(
        "extract_frames.py","classify_frames.py","crop_pizza_images.py",
        "mark_processed_videos.py","upload_selected_frames.js","upload_to_sheets.js",
        "requirements.txt","create_tasks.ps1","setup_camera.ps1","verify_pipeline.ps1"
    )
    foreach ($f in $old) {
        $p = Join-Path $PipelineDir $f
        if (Test-Path $p) { Remove-Item $p -Force; Write-Log "  Eliminado: $f" Yellow }
    }
    $pc = Join-Path $PipelineDir "__pycache__"
    if (Test-Path $pc) { Remove-Item $pc -Recurse -Force }
    $sub = Join-Path $PipelineDir "pizza_pipeline"
    if (Test-Path $sub) { Remove-Item $sub -Recurse -Force; Write-Log "  Eliminada subcarpeta pizza_pipeline" Yellow }
}

# -------------------------------------------------------
# Migrar carpeta legacy pizza-pipeline (guion)
# -------------------------------------------------------
function Migrate-Legacy {
    if (-not (Test-Path $LegacyDir)) { return }
    Write-Log "  Migrando archivos desde $LegacyDir..." Yellow
    foreach ($f in @("google_key.json","location_slug.txt","processed_videos.txt")) {
        $src = Join-Path $LegacyDir $f
        $dst = Join-Path $PipelineDir $f
        if ((Test-Path $src) -and -not (Test-Path $dst)) {
            Copy-Item $src $dst -Force
            Write-Log "  Migrado: $f"
        }
    }
}

# -------------------------------------------------------
# Guardar slug
# -------------------------------------------------------
function Save-Slug {
    if ([string]::IsNullOrWhiteSpace($Options.Slug)) { return }
    Set-Content -LiteralPath (Join-Path $PipelineDir "location_slug.txt") `
        -Value $Options.Slug.Trim() -NoNewline -Encoding UTF8
    Write-Log "  Slug guardado: $($Options.Slug)" Green
}

# -------------------------------------------------------
# Instalar dependencias (solo nueva)
# -------------------------------------------------------
function Install-Dependencies {
    $script = Join-Path $PipelineDir "instalar_dependencias.ps1"
    if (-not (Test-Path $script)) { throw "No existe instalar_dependencias.ps1 en $PipelineDir" }
    Write-Log "  Instalando dependencias..." Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script
    if ($LASTEXITCODE -ne 0) { throw "instalar_dependencias.ps1 fallo." }
    Write-Log "  Dependencias OK." Green
}

# -------------------------------------------------------
# Configurar camara RTSP (solo nueva, o si se pide)
# -------------------------------------------------------
function Configure-Camera {
    $hasConfig = -not [string]::IsNullOrWhiteSpace($Options.CamMarca) -or `
                 -not [string]::IsNullOrWhiteSpace($Options.RtspUrl)
    if (-not $hasConfig) { Write-Log "  Camara: sin cambios." Yellow; return }

    Write-Log "  Configurando camara RTSP..."
    & powershell -NoProfile -ExecutionPolicy Bypass `
        -File (Join-Path $PipelineDir "scripts\setup_camera.ps1") `
        -LogFile $LogFile `
        -BrandNum $Options.CamMarca `
        -CamUser  $Options.CamUser  `
        -CamPass  $Options.CamPass  `
        -CamIp    $Options.CamIp    `
        -CamPort  $Options.CamPort  `
        -Channel  $Options.CamCanal `
        -RtspUrl  $Options.RtspUrl
    if ($LASTEXITCODE -ne 0) { throw "setup_camera.ps1 fallo." }
    Write-Log "  Camara OK." Green
}

# -------------------------------------------------------
# deletequality.bat
# -------------------------------------------------------
function Configure-DeleteQuality {
    $path = Join-Path $DocsDir "deletequality.bat"
    @(
        "@echo off",
        'if exist "C:\Users\gritseeuser1\Documents\qualityvids\" (',
        '    del /S /Q "C:\Users\gritseeuser1\Documents\qualityvids\*" 2>nul',
        ')'
    ) | Set-Content -LiteralPath $path -Encoding ASCII
    Write-Log "  deletequality.bat OK." Green
}

# -------------------------------------------------------
# Tareas programadas
# -------------------------------------------------------
function Configure-Tasks {
    if ([string]::IsNullOrWhiteSpace($Options.PcPass)) {
        Write-Log "  Tareas: sin cambios (no se recibio contrasena)." Yellow
        return
    }
    Write-Log "  Creando tareas programadas..."
    $tmp = Join-Path $env:TEMP "gritsee_pwd.tmp"
    try {
        [IO.File]::WriteAllText($tmp, $Options.PcPass.Trim(), [Text.Encoding]::UTF8)
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $PipelineDir "scripts\create_tasks.ps1") `
            -PasswordFile $tmp >> $LogFile 2>&1
        if ($LASTEXITCODE -ne 0) { throw "create_tasks.ps1 fallo." }
    } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    Write-Log "  Tareas OK." Green
}

# -------------------------------------------------------
# MAIN
# -------------------------------------------------------
try {
    Assert-Admin
    if (-not $Options.Auto) { Ask-InteractiveOptions }
    if ($Options.Tipo -notin @("nueva","actualizar")) { throw "Tipo invalido. Usa /tipo:nueva o /tipo:actualizar" }

    "============================================================" | Out-File $LogFile -Encoding UTF8
    "GRITSEE - $($Options.Tipo.ToUpper()) - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $LogFile -Append -Encoding UTF8
    "============================================================" | Out-File $LogFile -Append -Encoding UTF8

    Write-Log ""
    Write-Log "  =============================================================" Cyan
    Write-Log "         GRITSEE - PIZZA QUALITY  [$($Options.Tipo.ToUpper())]" Cyan
    Write-Log "  =============================================================" Cyan

    # === ACTUALIZAR: solo sync + limpieza ===
    if ($Options.Tipo -ieq "actualizar") {
        Ensure-Workspace
        Migrate-Legacy
        if ($Options.SkipSync) {
            Write-Log "  Sync omitido (/skip_sync)." Yellow
        } else {
            Sync-Code
        }
        Cleanup-OldRootScripts
        Save-Slug
        Configure-DeleteQuality
        Configure-Tasks   # solo si se paso /pass:
        Write-Log ""
        Write-Log "  ACTUALIZACION COMPLETADA" Green
        exit 0
    }

    # === NUEVA: sync + dependencias + camara + tareas ===
    if ([string]::IsNullOrWhiteSpace($Options.Slug))    { throw "Falta /slug:" }
    if ([string]::IsNullOrWhiteSpace($Options.PcPass))  { throw "Falta /pass: (contrasena de gritseeuser1)" }
    if ([string]::IsNullOrWhiteSpace($Options.CamMarca) -and [string]::IsNullOrWhiteSpace($Options.RtspUrl)) {
        throw "Falta configuracion de camara."
    }

    Ensure-Workspace
    Migrate-Legacy

    if ($Options.SkipSync) {
        Write-Log "  Sync omitido (/skip_sync)." Yellow
    } else {
        Sync-Code
        Cleanup-OldRootScripts
        # Re-lanzar con el codigo actualizado en disco
        Write-Log "  Relanzando con codigo actualizado..." Cyan
        & powershell -NoProfile -ExecutionPolicy Bypass `
            -File $MyInvocation.MyCommand.Path (@($args) + @('/skip_sync'))
        exit $LASTEXITCODE
    }

    Cleanup-OldRootScripts
    Save-Slug
    Install-Dependencies
    Configure-DeleteQuality
    Configure-Camera
    Configure-Tasks

    Write-Log ""
    Write-Log "  CONFIGURACION NUEVA COMPLETADA" Green
    Write-Log "  Recuerda copiar google_key.json a $PipelineDir" Yellow
    exit 0

} catch {
    Write-Log ""
    Write-Log "  ERROR: $($_.Exception.Message)" Red
    Write-Log "  Log: $LogFile" Red
    exit 1
}
