if (Test-Path "E:\approot\") {
    $approot = "E:\approot"
} elseif (Test-Path "F:\approot\") {
    $approot = "F:\approot"
} else {
    throw "approot not found"
}

$scheduled_task = "<?xml version=`"1.0`" encoding=`"UTF-16`"?>
<Task version=`"1.4`" xmlns=`"http://schemas.microsoft.com/windows/2004/02/mit/task`">
  <RegistrationInfo>
    <Date>2016-09-06T20:27:10.2939543</Date>
    <Author>Norton Pengra</Author>
  </RegistrationInfo>
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id=`"Author`">
      <UserId>S-1-5-18</UserId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>false</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context=`"Author`">
    <Exec>
      <Command>C:\python\python.exe</Command>
      <Arguments>$approot\worker.py</Arguments>
    </Exec>
  </Actions>
</Task>"

try {
    Start-Process -FilePath "python" -ArgumentList "-c `"print('hello world')`"" -ErrorAction Stop -Wait
} catch {
    Invoke-WebRequest "https://www.python.org/ftp/python/3.5.2/python-3.5.2.exe" -OutFile "$approot\install_python.exe"
    Start-Process -FilePath "$approot\install_python.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 DefaultAllUsersTargetDir=`"C:\\python\\`"" -Wait
    Start-Process -FilePath "C:\python\Scripts\pip.exe" -ArgumentList "install -r $approot\requirements.txt" -Wait
}

if (Test-Path "$env:ProgramFiles\microsoft\web platform installer\WebpiCmd-x64.exe") {
    Start-Process -FilePath "$env:ProgramFiles\microsoft\web platform installer\WebpiCmd-x64.exe" -ArgumentList "/Install /Products:ARR /accepteula" -Wait
} else {
    # Install webpi
    Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=226239" -OutFile "$approot\install_webpi.msi"
    Start-Process -FilePath "msiexec" -ArgumentList "/i install_webpi.msi /quiet ADDLOCAL=ALL" -Wait
    # Install ARR
    Start-Process -FilePath "$env:ProgramFiles\microsoft\web platform installer\WebpiCmd-x64.exe" -ArgumentList "/Install /Products:ARR /accepteula" -Wait
}

$scheduled_task | Out-File "$approot\schedule.xml" -Encoding ascii
Start-Process -FilePath "schtasks" -ArgumentList "-Delete -TN `"WebServer`" /F" -Wait
Start-Process -FilePath "taskkill" -ArgumentList "/IM python.exe /F" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Create -XML `"$approot\schedule.xml`" -TN `"WebServer`"" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Run -TN `"WebServer`"" -Wait