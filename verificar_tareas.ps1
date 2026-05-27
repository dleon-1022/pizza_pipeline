# verificar_tareas.ps1
# Verifica que las 3 tareas de Gritsee existen y estan bien configuradas.
# Muestra estado, horario, ultimo resultado y proxima ejecucion.

$tareaEsperadas = @(
    @{
        Nombre   = "Daily Pizza Pipeline"
        Carpeta  = "\Gritsee\Daily Pizza Pipeline"
        Comando  = 'C:\pizza_pipeline\run_pipeline.bat'
        Hora     = "03:00"
        Desc     = "Pipeline de analisis (3:00 AM diario)"
    },
    @{
        Nombre   = "Quality run"
        Carpeta  = "\Gritsee\Quality run"
        Comando  = 'C:\Users\gritseeuser1\Documents\qualityrun.bat'
        Hora     = "10:21"
        Desc     = "Grabacion de video (cada 15 min desde 10:21, 13 horas)"
    },
    @{
        Nombre   = "Quality delete"
        Carpeta  = "\Gritsee\Quality delete"
        Comando  = 'C:\Users\gritseeuser1\Documents\deletequality.bat'
        Hora     = "08:20"
        Desc     = "Limpieza de videos (8:20 AM diario)"
    }
)

$errores  = 0
$ok       = 0

Write-Host ""
Write-Host "  ============================================================="
Write-Host "    GRITSEE - VERIFICACION DE TAREAS PROGRAMADAS"
Write-Host "  ============================================================="
Write-Host ""

# Leer slug de esta PC
$slugFile = "C:\pizza_pipeline\location_slug.txt"
if (Test-Path $slugFile) {
    $slug = (Get-Content $slugFile -Raw).Trim()
    Write-Host "  Locacion: $slug"
} else {
    Write-Host "  Locacion: NO ENCONTRADA (falta location_slug.txt)"
}
Write-Host ""

foreach ($t in $tareaEsperadas) {

    Write-Host "  ----------------------------------------------------------"
    Write-Host "  Tarea : $($t.Nombre)"
    Write-Host "  Desc  : $($t.Desc)"
    Write-Host ""

    $tarea = Get-ScheduledTask -TaskPath "\Gritsee\" -TaskName $t.Nombre -ErrorAction SilentlyContinue

    if (-not $tarea) {
        Write-Host "  [ERROR] NO EXISTE la tarea en \Gritsee\$($t.Nombre)" -ForegroundColor Red
        Write-Host "          Ejecuta configuracion.bat para crearla." -ForegroundColor Yellow
        $errores++
        Write-Host ""
        continue
    }

    # Estado habilitado
    $estadoStr = if ($tarea.Settings.Enabled) { "Habilitada" } else { "DESHABILITADA" }
    $estadoColor = if ($tarea.Settings.Enabled) { "Green" } else { "Red" }
    Write-Host "  Estado    : $estadoStr" -ForegroundColor $estadoColor

    # Informacion de ejecucion
    $info = Get-ScheduledTaskInfo -TaskName $t.Nombre -TaskPath "\Gritsee\" -ErrorAction SilentlyContinue
    if ($info) {
        $ultimaEjecucion  = if ($info.LastRunTime  -and $info.LastRunTime  -ne [datetime]::MinValue) { $info.LastRunTime.ToString("yyyy-MM-dd HH:mm:ss")  } else { "Nunca" }
        $proximaEjecucion = if ($info.NextRunTime  -and $info.NextRunTime  -ne [datetime]::MinValue) { $info.NextRunTime.ToString("yyyy-MM-dd HH:mm:ss")  } else { "No programada" }
        $ultimoResultado  = "0x{0:X8}" -f [uint32]$info.LastTaskResult

        $resultColor = if ($info.LastTaskResult -eq 0 -or $info.LastTaskResult -eq 267009) { "Green" } else { "Yellow" }

        Write-Host "  Ultimo run: $ultimaEjecucion"
        Write-Host "  Resultado : $ultimoResultado" -ForegroundColor $resultColor
        Write-Host "  Proximo   : $proximaEjecucion"
    }

    # Verificar trigger (hora de inicio)
    $trigger = $tarea.Triggers | Select-Object -First 1
    if ($trigger) {
        $startStr = $trigger.StartBoundary
        Write-Host "  Trigger   : $startStr"
    }

    # Verificar comando
    $accion = $tarea.Actions | Select-Object -First 1
    $comandoReal = ""
    if ($accion.Execute -and $accion.Arguments) {
        $comandoReal = "$($accion.Execute) $($accion.Arguments)"
    } elseif ($accion.Execute) {
        $comandoReal = $accion.Execute
    }

    $comandoOk = $comandoReal -like "*$($t.Comando)*"
    if ($comandoOk) {
        Write-Host "  Comando   : OK -$comandoReal" -ForegroundColor Green
    } else {
        Write-Host "  Comando   : DIFERENTE" -ForegroundColor Yellow
        Write-Host "              Esperado : $($t.Comando)"
        Write-Host "              Real     : $comandoReal"
    }

    # Verificar usuario
    $principal = $tarea.Principal
    if ($principal.UserId -eq "gritseeuser1") {
        Write-Host "  Usuario   : OK -gritseeuser1" -ForegroundColor Green
    } else {
        Write-Host "  Usuario   : DIFERENTE -$($principal.UserId)" -ForegroundColor Yellow
    }

    if ($tarea.Settings.Enabled -and $comandoOk -and $principal.UserId -eq "gritseeuser1") {
        $ok++
    } else {
        $errores++
    }

    Write-Host ""
}

# Verificar archivos que las tareas necesitan
Write-Host "  ============================================================="
Write-Host "  ARCHIVOS NECESARIOS"
Write-Host "  ============================================================="
Write-Host ""

$archivos = @(
    "C:\pizza_pipeline\run_pipeline.bat",
    "C:\pizza_pipeline\location_slug.txt",
    "C:\pizza_pipeline\google_key.json",
    "C:\pizza_pipeline\best.pt",
    "C:\pizza_pipeline\frame_classifier.pth",
    "C:\Users\gritseeuser1\Documents\qualityrun.bat",
    "C:\Users\gritseeuser1\Documents\deletequality.bat"
)

foreach ($archivo in $archivos) {
    if (Test-Path $archivo) {
        Write-Host "  [OK]      $archivo" -ForegroundColor Green
    } else {
        Write-Host "  [FALTA]   $archivo" -ForegroundColor Red
        $errores++
    }
}

# Resumen final
Write-Host ""
Write-Host "  ============================================================="
if ($errores -eq 0) {
    Write-Host "  RESULTADO: TODO CORRECTO -$ok de 3 tareas OK" -ForegroundColor Green
} else {
    Write-Host "  RESULTADO: $errores PROBLEMAS ENCONTRADOS" -ForegroundColor Red
    Write-Host "  Revisa los puntos marcados en rojo arriba." -ForegroundColor Yellow
}
Write-Host "  ============================================================="
Write-Host ""

Read-Host "  Presiona Enter para cerrar"
