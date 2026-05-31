# deploy.ps1
# Despliega o verifica pizza-pipeline en multiples PCboxes via AnyDesk.
#
# Columnas requeridas en Excel:
# location, id, name, slug, anydesk_id, anydesk_pass, pc_user, pc_password,
# user_cam, pass_cam, marca, cam_ip, cam_port, cam_channel, tipo, accion
# Opcional: rtsp_url para camaras de tipo Manual/10.
#
# accion = "no" omite la fila
# tipo   = "nueva", "actualizar" o "verificar"

param(
    [string]$ExcelFile = "pcs.xlsx",
    [int]$BatchSize = 5,
    [int]$TimeoutSeconds = 1800,
    [switch]$DryRun,
    [switch]$VerifyOnly,
    [switch]$AllRows,
    [switch]$TestRtsp,
    [switch]$RunPipelineTest,
    [switch]$KeepLegacyFolder,
    [string]$GoogleKeyFile = ""
)

$RepoZipUrl = "https://github.com/dleon-1022/pizza-pipeline/archive/refs/heads/main.zip"

$COLOR_OK        = 0x00C00000
$COLOR_ERROR     = 0x000000FF
$COLOR_APAGADA   = 0x00808080
$COLOR_OMITIDA   = 0x00AAAAAA
$COLOR_PENDIENTE = 0x00FF8C00

$BG_OK        = 0x00E2EFDA
$BG_ERROR     = 0x00FFE7E7
$BG_APAGADA   = 0x00F2F2F2
$BG_OMITIDA   = 0x00FAFAFA
$BG_PENDIENTE = 0x00FFFACD

$marcaMap = @{
    "Hikvision" = "1"; "Dahua" = "2"; "Amcrest" = "2"
    "Anpviz"    = "3"; "Reolink" = "4"; "Uniview" = "5"
    "UNV"       = "5"; "Hanwha" = "6"; "Samsung" = "6"
    "TPLink"    = "7"; "TP-Link" = "7"; "Tapo"   = "7"
    "Axis"      = "8"; "Bosch"   = "9"; "Manual" = "10"
}

function Get-Cell {
    param($pc, [string]$Name, [string]$Default = "")
    if ($pc.ContainsKey($Name) -and $null -ne $pc[$Name]) {
        return [string]$pc[$Name]
    }
    return $Default
}

function ConvertTo-PsLiteral {
    param([string]$Value)
    if ($null -eq $Value) { return "''" }
    return "'" + ($Value -replace "'", "''") + "'"
}

function ConvertTo-EncodedCommand {
    param([string]$Script)
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
}

function Get-BrandNumber {
    param([string]$Brand)
    if ($marcaMap.ContainsKey($Brand)) { return $marcaMap[$Brand] }
    if ($Brand -match "^\d+$") { return $Brand }
    return "1"
}

$googleKeyBase64 = ""
if ($GoogleKeyFile) {
    if (-not (Test-Path -LiteralPath $GoogleKeyFile)) {
        Write-Host "[ERROR] No existe GoogleKeyFile: $GoogleKeyFile" -ForegroundColor Red
        exit 1
    }
    $googleKeyBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $GoogleKeyFile).Path))
}

$anydeskPaths = @(
    "C:\Program Files (x86)\AnyDesk\AnyDesk.exe",
    "C:\Program Files\AnyDesk\AnyDesk.exe"
)
$anydesk = $anydeskPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $anydesk) {
    Write-Host "[ERROR] AnyDesk no encontrado." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ExcelFile)) {
    Write-Host "[ERROR] No se encontro $ExcelFile" -ForegroundColor Red
    exit 1
}

$xlApp = New-Object -ComObject Excel.Application
$xlApp.Visible = $false
$xlApp.DisplayAlerts = $false

$wb = $xlApp.Workbooks.Open((Resolve-Path $ExcelFile).Path)
$ws = $wb.Sheets.Item(1)

$headers = @{}
$col = 1
while ($ws.Cells.Item(1, $col).Value2 -ne $null -and $col -le 80) {
    $headers[$ws.Cells.Item(1, $col).Value2.ToLower().Trim()] = $col
    $col++
}

$lastCol = $col
function Ensure-Col {
    param([string]$name)
    $key = $name.ToLower()
    if (-not $headers.ContainsKey($key)) {
        $headers[$key] = $script:lastCol
        $ws.Cells.Item(1, $script:lastCol).Value2 = $name.ToUpper()
        $ws.Cells.Item(1, $script:lastCol).Font.Bold = $true
        $script:lastCol++
    }
    return $headers[$key]
}

$colStatus = Ensure-Col "GRITSEE_STATUS"
$colFecha = Ensure-Col "GRITSEE_ULTIMO_INTENTO"
$colDetalle = Ensure-Col "GRITSEE_DETALLE"

function Set-RowStatus {
    param([int]$row, [string]$status, [string]$detalle, [int]$bgColor, [int]$fgColor)
    $ws.Cells.Item($row, $colStatus).Value2 = $status
    $ws.Cells.Item($row, $colFecha).Value2 = (Get-Date -Format "yyyy-MM-dd HH:mm")
    $ws.Cells.Item($row, $colDetalle).Value2 = $detalle
    foreach ($c in @($colStatus, $colFecha, $colDetalle)) {
        $ws.Cells.Item($row, $c).Interior.Color = $bgColor
        $ws.Cells.Item($row, $c).Font.Color = $fgColor
    }
    $wb.Save()
}

$row = 2
$pcs = @()
while ($ws.Cells.Item($row, 1).Value2 -ne $null) {
    $pc = @{ Row = $row }
    foreach ($h in $headers.Keys) {
        $pc[$h] = $ws.Cells.Item($row, $headers[$h]).Value2
    }
    $pcs += $pc
    $row++
}

function Get-RemoteCommand {
    param($pc)

    $tipo = if ($VerifyOnly) { "verificar" } else { (Get-Cell $pc "tipo" "auto").ToLower() }
    if ($tipo -notin @("auto", "nueva", "actualizar", "verificar")) { $tipo = "auto" }

    $slug = Get-Cell $pc "slug"
    $pcPassword = Get-Cell $pc "pc_password"
    $camUser = Get-Cell $pc "user_cam"
    $camPass = Get-Cell $pc "pass_cam"
    $camIp = Get-Cell $pc "cam_ip"
    $camPort = Get-Cell $pc "cam_port" "554"
    $camChannel = Get-Cell $pc "cam_channel" "1"
    $rtspUrl = Get-Cell $pc "rtsp_url"
    $brandNum = Get-BrandNumber (Get-Cell $pc "marca" "1")
    $cleanupLegacy = -not $KeepLegacyFolder
    $runPipeline = [bool]$RunPipelineTest

    $remoteScript = @"
`$ErrorActionPreference = 'Stop'
`$target = 'C:\pizza_pipeline'
`$legacy = 'C:\pizza-pipeline'
`$repoZipUrl = $(ConvertTo-PsLiteral $RepoZipUrl)
`$tipo = $(ConvertTo-PsLiteral $tipo)
`$slug = $(ConvertTo-PsLiteral $slug)
`$pcPassword = $(ConvertTo-PsLiteral $pcPassword)
`$camUser = $(ConvertTo-PsLiteral $camUser)
`$camPass = $(ConvertTo-PsLiteral $camPass)
`$camIp = $(ConvertTo-PsLiteral $camIp)
`$camPort = $(ConvertTo-PsLiteral $camPort)
`$camChannel = $(ConvertTo-PsLiteral $camChannel)
`$rtspUrl = $(ConvertTo-PsLiteral $rtspUrl)
`$brandNum = $(ConvertTo-PsLiteral $brandNum)
`$googleKeyBase64 = $(ConvertTo-PsLiteral $googleKeyBase64)
`$cleanupLegacy = `$$($cleanupLegacy.ToString().ToLower())
`$runPipeline = `$$($runPipeline.ToString().ToLower())
`$testRtsp = `$$($TestRtsp.ToString().ToLower())

function Copy-RuntimeFiles(`$from, `$to) {
    foreach (`$file in @('google_key.json', 'location_slug.txt', 'processed_videos.txt')) {
        `$source = Join-Path `$from `$file
        `$dest = Join-Path `$to `$file
        if ((Test-Path `$source) -and -not (Test-Path `$dest)) {
            Copy-Item -LiteralPath `$source -Destination `$dest -Force
        }
    }
}

New-Item -ItemType Directory -Path `$target -Force | Out-Null
foreach (`$dir in @('frames','cropped_frames','selected_frames','models','uploads')) {
    New-Item -ItemType Directory -Path (Join-Path `$target `$dir) -Force | Out-Null
}

if (Test-Path `$legacy) {
    Copy-RuntimeFiles `$legacy `$target
}

`$zip = Join-Path `$env:TEMP 'pizza_pipeline_main.zip'
`$extract = Join-Path `$env:TEMP 'pizza_pipeline_main'
Remove-Item -LiteralPath `$zip -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath `$extract -Recurse -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -Uri `$repoZipUrl -OutFile `$zip -UseBasicParsing
Expand-Archive -LiteralPath `$zip -DestinationPath `$extract -Force
`$sourceRoot = Get-ChildItem -LiteralPath `$extract -Directory | Select-Object -First 1
if (-not `$sourceRoot) { throw 'No se pudo extraer el ZIP del repo.' }
Copy-Item -Path (Join-Path `$sourceRoot.FullName '*') -Destination `$target -Recurse -Force

if (`$googleKeyBase64) {
    [IO.File]::WriteAllBytes((Join-Path `$target 'google_key.json'), [Convert]::FromBase64String(`$googleKeyBase64))
}

if (`$cleanupLegacy -and (Test-Path `$legacy)) {
    Remove-Item -LiteralPath `$legacy -Recurse -Force
}

if (`$tipo -eq 'verificar') {
    `$verifyArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path `$target 'verify_pipeline.ps1'))
    if (`$testRtsp) { `$verifyArgs += '-TestRtsp' }
    if (`$runPipeline) { `$verifyArgs += '-RunPipeline' }
    & powershell @verifyArgs
    exit `$LASTEXITCODE
}

`$qualityRunPath = 'C:\Users\gritseeuser1\Documents\qualityrun.bat'
`$qualityVidsPath = 'C:\Users\gritseeuser1\Documents\qualityvids'
`$qualityRunTask = `$null
try { `$qualityRunTask = Get-ScheduledTask -TaskPath '\Gritsee\' -TaskName 'Quality run' -ErrorAction Stop } catch {}
`$hasQualityRun = (Test-Path `$qualityRunPath) -or (`$null -ne `$qualityRunTask)
`$hasVideos = (Test-Path `$qualityVidsPath) -and (`$null -ne (Get-ChildItem -LiteralPath `$qualityVidsPath -File -Filter '*.mp4' -ErrorAction SilentlyContinue | Select-Object -First 1))

if (`$tipo -eq 'auto') {
    if (`$hasQualityRun -or `$hasVideos) { `$tipo = 'actualizar' } else { `$tipo = 'nueva' }
}
if (`$tipo -eq 'nueva' -and `$hasQualityRun) {
    `$tipo = 'actualizar'
}

`$configArgs = @('/auto', "/tipo:`$tipo", '/skip_sync')
if (`$slug) { `$configArgs += "/slug:`$slug" }
if (`$pcPassword) { `$configArgs += "/pass:`$pcPassword" }
if (`$cleanupLegacy) { `$configArgs += '/cleanup_legacy' }

if (`$rtspUrl -and -not `$hasQualityRun) {
    `$configArgs += "/rtsp:`$rtspUrl"
}

if ((`$tipo -eq 'nueva' -or `$camIp -or `$camUser -or `$camPass -or `$rtspUrl) -and -not `$hasQualityRun) {
    `$configArgs += "/cam_user:`$camUser"
    `$configArgs += "/cam_pass:`$camPass"
    `$configArgs += "/cam_ip:`$camIp"
    `$configArgs += "/cam_port:`$camPort"
    `$configArgs += "/cam_marca:`$brandNum"
    `$configArgs += "/cam_canal:`$camChannel"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path `$target 'configure_pipeline.ps1') @configArgs
if (`$LASTEXITCODE -ne 0) { exit 20 }

`$verifyArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path `$target 'verify_pipeline.ps1'))
if (`$testRtsp) { `$verifyArgs += '-TestRtsp' }
if (`$runPipeline) { `$verifyArgs += '-RunPipeline' }
& powershell @verifyArgs
if (`$LASTEXITCODE -ne 0) { exit 30 }

exit 0
"@

    return "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $(ConvertTo-EncodedCommand $remoteScript)"
}

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "    GRITSEE - DESPLIEGUE MASIVO" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "  PCboxes en Excel : $($pcs.Count)"
Write-Host "  Lotes de         : $BatchSize"
Write-Host "  Timeout          : $TimeoutSeconds segundos"
if (-not $AllRows) { Write-Host "  Filtro           : solo STATUS = conectada" -ForegroundColor Yellow }
if ($VerifyOnly) { Write-Host "  Modo             : verificar solamente" -ForegroundColor Yellow }
if ($TestRtsp) { Write-Host "  RTSP             : prueba con ffmpeg habilitada" -ForegroundColor Yellow }
if ($DryRun) { Write-Host "  Modo             : dry run" -ForegroundColor Yellow }
if ($GoogleKeyFile) { Write-Host "  google_key.json  : se enviara desde archivo local" -ForegroundColor Yellow }
Write-Host ""

$total = 0; $ok = 0; $errores = 0; $omitidas = 0; $apagadas = 0
$jobs = @()

foreach ($pc in $pcs) {
    $total++
    $name = Get-Cell $pc "name" "(sin nombre)"
    $accion = Get-Cell $pc "accion"
    $sourceStatus = (Get-Cell $pc "status").Trim().ToLower()
    $tipo = if ($VerifyOnly) { "verificar" } else { Get-Cell $pc "tipo" "auto" }

    if ($accion -and $accion.ToLower() -eq "no") {
        Write-Host "  [OMITIDA]  $name" -ForegroundColor DarkGray
        Set-RowStatus $pc.Row "Omitida" "accion=no" $BG_OMITIDA $COLOR_OMITIDA
        $omitidas++
        continue
    }

    if (-not $AllRows -and $sourceStatus -ne "conectada") {
        Write-Host "  [OMITIDA]  $name (STATUS=$sourceStatus)" -ForegroundColor DarkGray
        Set-RowStatus $pc.Row "Omitida" "STATUS no conectada" $BG_OMITIDA $COLOR_OMITIDA
        $omitidas++
        continue
    }

    Write-Host "  [$tipo] $name ($((Get-Cell $pc 'slug')))" -ForegroundColor White
    $remoteCmd = Get-RemoteCommand $pc

    if ($DryRun) {
        Write-Host "    Comando remoto generado." -ForegroundColor DarkYellow
        continue
    }

    Set-RowStatus $pc.Row "En proceso..." "Conectando..." $BG_PENDIENTE $COLOR_PENDIENTE

    $adId = Get-Cell $pc "anydesk_id"
    $adPass = Get-Cell $pc "anydesk_pass"

    $job = Start-Job -ScriptBlock {
        param($anydesk, $id, $pass, $cmd, $timeout)
        $p = Start-Process -FilePath $anydesk -ArgumentList "$id --with-password $pass --plain -- $cmd" -PassThru -NoNewWindow
        $finished = $p.WaitForExit($timeout * 1000)
        if (-not $finished) {
            $p.Kill()
            return 99
        }
        return $p.ExitCode
    } -ArgumentList $anydesk, $adId, $adPass, $remoteCmd, $TimeoutSeconds

    $jobs += @{ Job = $job; PC = $pc }

    if ($jobs.Count -ge $BatchSize -or $total -eq $pcs.Count) {
        Write-Host ""
        Write-Host "  Esperando resultados del lote..." -ForegroundColor Yellow

        foreach ($entry in $jobs) {
            $result = Receive-Job $entry.Job -Wait
            Remove-Job $entry.Job
            $detailByCode = @{
                20 = "Fallo configuracion/instalacion. Ver log remoto: Desktop\gritsee_configuracion.log"
                30 = "Fallo verificacion. Ver log remoto: C:\pizza_pipeline\verify_pipeline.log"
                99 = "Timeout de $TimeoutSeconds segundos"
            }

            switch ($result) {
                0 {
                    Write-Host "    [OK]      $((Get-Cell $entry.PC 'name'))" -ForegroundColor Green
                    Set-RowStatus $entry.PC.Row "OK" "Completado correctamente" $BG_OK $COLOR_OK
                    $ok++
                }
                99 {
                    Write-Host "    [APAGADA] $((Get-Cell $entry.PC 'name'))" -ForegroundColor DarkGray
                    Set-RowStatus $entry.PC.Row "Apagada" $detailByCode[99] $BG_APAGADA $COLOR_APAGADA
                    $apagadas++
                }
                default {
                    Write-Host "    [ERROR]   $((Get-Cell $entry.PC 'name')) (codigo $result)" -ForegroundColor Red
                    $detail = if ($detailByCode.ContainsKey([int]$result)) { $detailByCode[[int]$result] } else { "Codigo de salida: $result" }
                    Set-RowStatus $entry.PC.Row "Error" $detail $BG_ERROR $COLOR_ERROR
                    $errores++
                }
            }
        }
        $jobs = @()
        Write-Host ""
    }
}

$wb.Save()
$xlApp.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($xlApp) | Out-Null

Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "    DESPLIEGUE COMPLETADO" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "  Total    : $total"
Write-Host "  OK       : $ok" -ForegroundColor Green
Write-Host "  Errores  : $errores" -ForegroundColor $(if ($errores -gt 0) { "Red" } else { "Green" })
Write-Host "  Apagadas : $apagadas" -ForegroundColor $(if ($apagadas -gt 0) { "DarkGray" } else { "Green" })
Write-Host "  Omitidas : $omitidas" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Resultados guardados en: $ExcelFile" -ForegroundColor Cyan
Write-Host ""
