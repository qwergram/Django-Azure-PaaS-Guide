# Deploying Django Projects on Azure Cloud Services

In IIS, the "right" approach would be configuring [fcgi to work with Django](https://pypi.org/project/wfastcgi/). 
Another approach would be to do a [reverse proxy](https://www.nginx.com/resources/admin-guide/reverse-proxy/), which requires a little more
work in IIS than nginx. 

First of all, note that the scripts that Visual Studio generates (as of Sept 2016) are all "suggestions" and don't
work as of right now. Therefore under `DjangoWebRole\bin\` you'll find `ps.cmd` and `ConfigureCloudService.ps1`. 
Open up the powershell script and delete everything inside of it.

## Write Deployment Script for webrole

You can then copy the following powershell script and place it in `DjangoWebRole\bin\ConfigureCloudService.ps1`.

### Download Python
### Install Web Package Installer
### Install ARR with Web Package Installer
ARR is what allows a reverse proxy, which allows us to run the django server on
`localhost` and we can serve it to the public with a stronger web server, much like nginx.
### Create a new Task with `schtasks`
You'll want your local django server to run on boot up. So we'll schedule a task to do it.


### Get location of approot
Whenever you push your code to Azure via webdeploy, Azure will put all your files on a vhd and swap
the existing vhd on that machine with the new code. Therefore your code's location will alternate
between `E:\` and `F:\`. With the following script:

```powershell
# ConfigureCloudService.ps1
if (Test-Path "E:\approot\") {
    $approot = "E:\approot"
} elseif (Test-Path "F:\approot\") {
    $approot = "F:\approot"
} else {
    throw "approot not found"
}
```

### Get Task XML
This big blob of xml is what's used to create the Scheduled Task.
I just stored in the powershell script for simplicity's sake.

```powershell
# ConfigureCloudService.ps1
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
      <Arguments>$approot\manage.py runserver 127.0.0.1:8080</Arguments>
    </Exec>
  </Actions>
</Task>"
```

### Install Python if it's missing
Windows machines, unlike every other Unix machine, don't come pre-installed with Python.
So we'll have to install it manually. This script will also append it to the system path.

```powershell
try {
    Start-Process -FilePath "python" -ArgumentList "-c `"print('hello world')`"" -ErrorAction Stop -Wait
} catch {
    Invoke-WebRequest "https://www.python.org/ftp/python/3.5.2/python-3.5.2.exe" -OutFile "$approot\install_python.exe"
    Start-Process -FilePath "$approot\install_python.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 DefaultAllUsersTargetDir=`"C:\\python\\`"" -Wait
    Start-Process -FilePath "C:\python\Scripts\pip.exe" -ArgumentList "install -r $approot\requirements.txt" -Wait
}

```

### Install Reverse Proxy
ARR by default isn't installed on IIS 8, so we'll need to download it and install it.
This code will invoke WebPIC, and install ARR with it. If WebPIC doesn't exist, it will
download it as well.

```powershell
if (Test-Path "$env:ProgramFiles\microsoft\web platform installer\WebpiCmd-x64.exe") {
    Start-Process -FilePath "$env:ProgramFiles\microsoft\web platform installer\WebpiCmd-x64.exe" -ArgumentList "/Install /Products:ARR /accepteula" -Wait
} else {
    # Install webpi
    Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=226239" -OutFile "$approot\install_webpi.msi"
    Start-Process -FilePath "msiexec" -ArgumentList "/i install_webpi.msi /quiet ADDLOCAL=ALL" -Wait
    # Install ARR
    Start-Process -FilePath "$env:ProgramFiles\microsoft\web platform installer\WebpiCmd-x64.exe" -ArgumentList "/Install /Products:ARR /accepteula" -Wait
}
```

### Create Scheduled Task    
Using the xml blob that was defined earlier, we can now write that out to a file.

```powershell
$scheduled_task | Out-File "$approot\schedule.xml" -Encoding ascii
```

### Delete old task
Delete the old schedule task and also kill any running python tasks to prevent two servers running at once.

```powershell
Start-Process -FilePath "schtasks" -ArgumentList "-Delete -TN `"WebServer`" /F" -Wait
Start-Process -FilePath "taskkill" -ArgumentList "/IM python.exe /F" -Wait
```

### Create new task
Use the xml to populate a new task and run it.

```powershell
Start-Process -FilePath "schtasks" -ArgumentList "-Create -XML `"$approot\schedule.xml`" -TN `"WebServer`"" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Run -TN `"WebServer`"" -Wait
```

## Write Deployment Script for Worker role

### Get location of approot
Much like the webrole, we'll need to walk through retrieving the approot location and setting the XML blob again.

```powershell
# ConfigureCloudService.ps1
if (Test-Path "E:\approot\") {
    $approot = "E:\approot"
} elseif (Test-Path "F:\approot\") {
    $approot = "F:\approot"
} else {
    throw "approot not found"
}
```

### Get Task XML
The only difference here is the `<Arguments>$approot\worker.py</Arguments>` line.

```powershell
# ConfigureCloudService.ps1
$scheduled_task = "<?xml version=`"1.0`" encoding=`"UTF-16`"?>
  ... same lines from webrole ...
  <Actions Context=`"Author`">
    <Exec>
      <Command>C:\python\python.exe</Command>
      <Arguments>$approot\worker.py</Arguments>
    </Exec>
  </Actions>
</Task>"
```

### Install Python if it's missing
Again, like the Webrole machine, windows machines don't come pre-installed with Python.
So we'll have to install it manually. This script will also append it to the system path.

```powershell
# ConfigureCloudService.ps1
try {
    Start-Process -FilePath "python" -ArgumentList "-c `"print('hello world')`"" -ErrorAction Stop -Wait
} catch {
    Invoke-WebRequest "https://www.python.org/ftp/python/3.5.2/python-3.5.2.exe" -OutFile "$approot\install_python.exe"
    Start-Process -FilePath "$approot\install_python.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 DefaultAllUsersTargetDir=`"C:\\python\\`"" -Wait
    Start-Process -FilePath "C:\python\Scripts\pip.exe" -ArgumentList "install -r $approot\requirements.txt" -Wait
}
```

### Schedule a task
We're going to schedule a task again using the xml we defined above.

```powershell
# Launch workerrole everytime on boot up
$scheduled_task | Out-File "C:\schedule.xml" -Encoding ascii
Start-Process -FilePath "schtasks" -ArgumentList "-Delete -TN `"WebServer`" /F" -Wait
Start-Process -FilePath "taskkill" -ArgumentList "/IM python.exe /F" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Create -XML `"$approot\schedule.xml`" -TN `"WebServer`"" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Run -TN `"WebServer`"" -Wait
```

## Conclusion
You should have two powershell files for the [worker role]() and [web role](). Run through the usual 
