param(
    [string]$PipelineDir = "C:\pizza_pipeline",
    [string]$DocumentsDir = "C:\Users\gritseeuser1\Documents",
    [string]$LogFile = "C:\pizza_pipeline\verify_pipeline.log",
    [switch]$TestRtsp,
    [switch]$RunPipeline
)

$ErrorActionPreference = "Continue"
$issues = New-Object System.Collections.Generic.List[string]

function Write-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Detail = ""
    )

    $status = if ($Ok) { "OK" } else { "ERROR" }
    $line = "[{0}] {1}{2}" -f $status, $Name, $(if ($Detail) { " - $Detail" } else { "" })
    Write-Host $line
    $line | Out-File $LogFile -Append -Encoding UTF8
    if (-not $Ok) { $issues.Add($line) | Out-Null }
}

function Test-PathOk {
    param([string]$Name, [string]$Path)
    Write-Check $Name (Test-Path -LiteralPath $Path) $Path
}

function Test-CommandOk {
    param([string]$Name, [string]$Command)
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    Write-Check $Name ($null -ne $cmd) $(if ($cmd) { $cmd.Source } else { $Command })
    return $cmd
}

function Invoke-Check {
    param([string]$Name, [scriptblock]$Block)

    try {
        & $Block
        Write-Check $Name ($LASTEXITCODE -eq 0)
    } catch {
        Write-Check $Name $false $_.Exception.Message
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $LogFile) -Force | Out-Null
"============================================================" | Out-File $LogFile -Encoding UTF8
"GRITSEE - VERIFY PIPELINE $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $LogFile -Append -Encoding UTF8
"============================================================" | Out-File $LogFile -Append -Encoding UTF8

Test-PathOk "Pipeline dir" $PipelineDir
Test-PathOk "run_pipeline.bat" (Join-Path $PipelineDir "run_pipeline.bat")
Test-PathOk "extract_frames.py" (Join-Path $PipelineDir "extract_frames.py")
Test-PathOk "classify_frames.py" (Join-Path $PipelineDir "classify_frames.py")
Test-PathOk "crop_pizza_images.py" (Join-Path $PipelineDir "crop_pizza_images.py")
Test-PathOk "mark_processed_videos.py" (Join-Path $PipelineDir "mark_processed_videos.py")
Test-PathOk "YOLO model" (Join-Path $PipelineDir "models\best.pt")
Test-PathOk "Frame classifier" (Join-Path $PipelineDir "models\frame_classifier.pth")
Test-PathOk "location_slug.txt" (Join-Path $PipelineDir "location_slug.txt")
Test-PathOk "google_key.json" (Join-Path $PipelineDir "google_key.json")
Test-PathOk "qualityrun.bat" (Join-Path $DocumentsDir "qualityrun.bat")
Test-PathOk "deletequality.bat" (Join-Path $DocumentsDir "deletequality.bat")

$python = Test-CommandOk "python command" "python"
$node = Test-CommandOk "node command" "node"
$npm = Test-CommandOk "npm.cmd command" "npm.cmd"
Test-CommandOk "ffmpeg command" "ffmpeg" | Out-Null
Test-CommandOk "aws command" "aws" | Out-Null

if ($python) {
    Invoke-Check "Python imports" {
        & $python.Source -c "import torch, torchvision, cv2, PIL, ultralytics; print('python deps ok')" > $null 2>&1
    }
}

if ($node) {
    Invoke-Check "Node googleapis import" {
        & $node.Source -e "require('googleapis'); console.log('node deps ok')" > $null 2>&1
    }
}

if ($TestRtsp) {
    $qualityRunPath = Join-Path $DocumentsDir "qualityrun.bat"
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue

    if (-not $ffmpeg) {
        Write-Check "RTSP test" $false "ffmpeg no esta disponible"
    } elseif (-not (Test-Path -LiteralPath $qualityRunPath)) {
        Write-Check "RTSP test" $false "No existe qualityrun.bat"
    } else {
        $qualityRun = Get-Content -Raw -LiteralPath $qualityRunPath
        $match = [regex]::Match($qualityRun, '-i\s+"(?<url>rtsp://[^"]+)"')

        if (-not $match.Success) {
            Write-Check "RTSP test" $false "No se pudo leer URL RTSP desde qualityrun.bat"
        } else {
            $rtspUrl = $match.Groups["url"].Value
            $safeUrl = $rtspUrl -replace '://([^:]+):([^@]+)@', '://$1:***@'
            try {
                $p = Start-Process -FilePath $ffmpeg.Source -ArgumentList @(
                    "-v", "error",
                    "-rtsp_transport", "tcp",
                    "-stimeout", "5000000",
                    "-i", $rtspUrl,
                    "-t", "5",
                    "-f", "null",
                    "NUL"
                ) -Wait -PassThru -NoNewWindow
                Write-Check "RTSP test" ($p.ExitCode -eq 0) $safeUrl
            } catch {
                Write-Check "RTSP test" $false $_.Exception.Message
            }
        }
    }
}

$expectedTasks = @(
    @{ Name = "Daily Pizza Pipeline"; Action = "C:\pizza_pipeline\run_pipeline.bat" },
    @{ Name = "Quality run"; Action = "C:\Users\gritseeuser1\Documents\qualityrun.bat" },
    @{ Name = "Quality delete"; Action = "C:\Users\gritseeuser1\Documents\deletequality.bat" }
)

foreach ($taskInfo in $expectedTasks) {
    try {
        $task = Get-ScheduledTask -TaskPath "\Gritsee\" -TaskName $taskInfo.Name -ErrorAction Stop
        $actionText = ($task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " "
        $enabled = $task.State -ne "Disabled"
        $pointsToExpected = $actionText -like "*$($taskInfo.Action)*"
        Write-Check "Task $($taskInfo.Name)" ($enabled -and $pointsToExpected) $actionText
    } catch {
        Write-Check "Task $($taskInfo.Name)" $false $_.Exception.Message
    }
}

if ($RunPipeline) {
    Invoke-Check "run_pipeline.bat execution" {
        Push-Location $PipelineDir
        try {
            & cmd.exe /c (Join-Path $PipelineDir "run_pipeline.bat")
        } finally {
            Pop-Location
        }
    }
}

if ($issues.Count -gt 0) {
    ""
    "Verificacion con errores:"
    $issues | ForEach-Object { "  $_" }
    exit 1
}

"Verificacion OK."
exit 0
