param(
    [Parameter(Mandatory)][string]$PasswordFile
)

$user = 'gritseeuser1'
$pass = [System.IO.File]::ReadAllText($PasswordFile).Trim()

# Crea la tarea escribiendo un XML temporal en UTF-16 (requerido por schtasks)
function Create-TaskFromXml {
    param([string]$TaskName, [string]$XmlContent)

    $xmlFile = "$env:TEMP\gritsee_task_temp.xml"
    try {
        [System.IO.File]::WriteAllText($xmlFile, $XmlContent, [System.Text.Encoding]::Unicode)
        $result = schtasks /Create /XML $xmlFile /TN "\Gritsee\$TaskName" /RU $user /RP $pass /F 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] $TaskName"
        } else {
            Write-Host "  [ERROR] $TaskName : $result"
        }
    } catch {
        Write-Host "  [ERROR] $TaskName : $_"
    } finally {
        if (Test-Path $xmlFile) { Remove-Item $xmlFile -Force -ErrorAction SilentlyContinue }
    }
}

# -------------------------------------------------------
# 1. Daily Pizza Pipeline — 3:00 AM diario
# -------------------------------------------------------
$xml1 = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2026-01-01T03:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>gritseeuser1</UserId>
      <LogonType>Password</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>Queue</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <WakeToRun>true</WakeToRun>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>/c "C:\pizza_pipeline\run_pipeline.bat"</Arguments>
      <WorkingDirectory>C:\pizza_pipeline</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
'@

# -------------------------------------------------------
# 2. Quality run — cada 15 min desde las 10:21, 13 horas
# -------------------------------------------------------
$xml2 = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <CalendarTrigger>
      <Repetition>
        <Interval>PT15M</Interval>
        <Duration>PT13H</Duration>
        <StopAtDurationEnd>true</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>2026-01-01T10:21:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>gritseeuser1</UserId>
      <LogonType>Password</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT4H</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Users\gritseeuser1\Documents\qualityrun.bat</Command>
    </Exec>
  </Actions>
</Task>
'@

# -------------------------------------------------------
# 3. Quality delete — 8:20 AM diario
# -------------------------------------------------------
$xml3 = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2026-01-01T08:20:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>gritseeuser1</UserId>
      <LogonType>Password</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Users\gritseeuser1\Documents\deletequality.bat</Command>
    </Exec>
  </Actions>
</Task>
'@

Create-TaskFromXml 'Daily Pizza Pipeline' $xml1
Create-TaskFromXml 'Quality run'          $xml2
Create-TaskFromXml 'Quality delete'       $xml3
