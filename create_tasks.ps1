param(
    [Parameter(Mandatory)][string]$PasswordFile
)

$user = 'gritseeuser1'
$pass = [System.IO.File]::ReadAllText($PasswordFile).Trim()

function Register-GritseeTask {
    param($Name, $Action, $Trigger, $Settings, $Principal)
    try {
        Register-ScheduledTask `
            -TaskName $Name `
            -TaskPath '\Gritsee\' `
            -Action $Action `
            -Trigger $Trigger `
            -Settings $Settings `
            -Principal $Principal `
            -Password $pass `
            -Force | Out-Null
        Write-Host "  [OK] $Name"
    } catch {
        Write-Host "  [ERROR] ${Name}: $_"
    }
}

# -------------------------------------------------------
# 1. Daily Pizza Pipeline — todos los dias a las 3:00 AM
# -------------------------------------------------------
$a1 = New-ScheduledTaskAction `
    -Execute 'cmd.exe' `
    -Argument '/c "C:\pizza_pipeline\run_pipeline.bat"' `
    -WorkingDirectory 'C:\pizza_pipeline'

$t1 = New-ScheduledTaskTrigger -Daily -At '03:00'

$s1 = New-ScheduledTaskSettingsSet `
    -MultipleInstances StopExisting `
    -WakeToRun `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 72) `
    -RestartCount 5 `
    -RestartInterval (New-TimeSpan -Minutes 15) `
    -DisallowStartIfOnBatteries:$false `
    -StopIfGoingOnBatteries:$false

$p1 = New-ScheduledTaskPrincipal -UserId $user -LogonType Password -RunLevel Highest

Register-GritseeTask 'Daily Pizza Pipeline' $a1 $t1 $s1 $p1

# -------------------------------------------------------
# 2. Quality run — cada 15 min, de 10:21 AM, durante 13h
# -------------------------------------------------------
$a2 = New-ScheduledTaskAction `
    -Execute 'C:\Users\gritseeuser1\Documents\qualityrun.bat'

$t2 = New-ScheduledTaskTrigger `
    -Daily -At '10:21' `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
    -RepetitionDuration (New-TimeSpan -Hours 13) `
    -StopAtDurationEnd

$s2 = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
    -DisallowStartIfOnBatteries:$false `
    -StopIfGoingOnBatteries:$false

$p2 = New-ScheduledTaskPrincipal -UserId $user -LogonType Password -RunLevel Limited

Register-GritseeTask 'Quality run' $a2 $t2 $s2 $p2

# -------------------------------------------------------
# 3. Quality delete — todos los dias a las 8:20 AM
# -------------------------------------------------------
$a3 = New-ScheduledTaskAction `
    -Execute 'C:\Users\gritseeuser1\Documents\deletequality.bat'

$t3 = New-ScheduledTaskTrigger -Daily -At '08:20'

$s3 = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 72) `
    -DisallowStartIfOnBatteries:$false `
    -StopIfGoingOnBatteries:$false

$p3 = New-ScheduledTaskPrincipal -UserId $user -LogonType Password -RunLevel Limited

Register-GritseeTask 'Quality delete' $a3 $t3 $s3 $p3
