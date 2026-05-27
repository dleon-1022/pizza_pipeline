param(
    [Parameter(Mandatory)][string]$PasswordFile
)

$user = 'gritseeuser1'
$pass = [System.IO.File]::ReadAllText($PasswordFile).Trim()

function Register-GritseeTask {
    param($Name, $Action, $Trigger, $Settings, $Principal)
    try {
        Register-ScheduledTask `
            -TaskName  $Name `
            -TaskPath  '\Gritsee\' `
            -Action    $Action `
            -Trigger   $Trigger `
            -Settings  $Settings `
            -Principal $Principal `
            -Password  $pass `
            -Force | Out-Null
        Write-Host "  [OK] $Name"
    } catch {
        Write-Host "  [ERROR] ${Name}: $_"
    }
}

# -------------------------------------------------------
# 1. Daily Pizza Pipeline — 3:00 AM diario
# -------------------------------------------------------
$a1 = New-ScheduledTaskAction `
    -Execute         'cmd.exe' `
    -Argument        '/c "C:\pizza_pipeline\run_pipeline.bat"' `
    -WorkingDirectory 'C:\pizza_pipeline'

$t1 = New-ScheduledTaskTrigger -Daily -At '03:00'

$s1 = New-ScheduledTaskSettingsSet `
    -MultipleInstances    Queue `
    -WakeToRun `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit   (New-TimeSpan -Hours 72) `
    -RestartCount         5 `
    -RestartInterval      (New-TimeSpan -Minutes 15)

$p1 = New-ScheduledTaskPrincipal -UserId $user -LogonType Password -RunLevel Highest

Register-GritseeTask 'Daily Pizza Pipeline' $a1 $t1 $s1 $p1

# -------------------------------------------------------
# 2. Quality run — cada 15 min desde las 10:21, 13 horas
#    La repeticion se configura despues de crear el trigger
# -------------------------------------------------------
$a2 = New-ScheduledTaskAction `
    -Execute 'C:\Users\gritseeuser1\Documents\qualityrun.bat'

$t2 = New-ScheduledTaskTrigger -Daily -At '10:21'
$t2.Repetition.Interval        = 'PT15M'
$t2.Repetition.Duration        = 'PT13H'
$t2.Repetition.StopAtDurationEnd = $true

$s2 = New-ScheduledTaskSettingsSet `
    -MultipleInstances  IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4)

$p2 = New-ScheduledTaskPrincipal -UserId $user -LogonType Password -RunLevel Limited

Register-GritseeTask 'Quality run' $a2 $t2 $s2 $p2

# -------------------------------------------------------
# 3. Quality delete — 8:20 AM diario
# -------------------------------------------------------
$a3 = New-ScheduledTaskAction `
    -Execute 'C:\Users\gritseeuser1\Documents\deletequality.bat'

$t3 = New-ScheduledTaskTrigger -Daily -At '08:20'

$s3 = New-ScheduledTaskSettingsSet `
    -MultipleInstances  IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 72)

$p3 = New-ScheduledTaskPrincipal -UserId $user -LogonType Password -RunLevel Limited

Register-GritseeTask 'Quality delete' $a3 $t3 $s3 $p3
