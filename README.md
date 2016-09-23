# Deploying Django Projects on Azure Cloud Services

In this topic, we will be covering on how to deploy Python Django projects to Azure Cloud Services. These docs assume that you are familiar with Python, 
Powershell, Azure's Dashboard and Windows. These docs also assume that you are using Visual Studio on Windows 10.

In IIS, the "right" approach would be configuring [fcgi to work with Django](https://pypi.org/project/wfastcgi/). However for nginx users that aren't used to that approach,
they'll be happy to know that another approach would be to do a [reverse proxy](https://www.nginx.com/resources/admin-guide/reverse-proxy/). In this walk through, we will
go over automating as much as possible.

To begin, open up your Python Cloud Service App in Visual Studio and navigate the `bin` directory of each role. 
Locate `ConfigureCloudService.ps1` and clear their contents. We will build a custom script.

## Write Deployment Script for webrole
We will begin with writing the script for installing the webrole on the server.

### 1. Get location of approot
Whenever you push your code to Azure via webdeploy, Azure will put all your files on a vhd and swap
the existing vhd on that machine with the newly pushed code. Therefore your code's location will alternate
between `E:\` and `F:\`; with the following snippet we are able to find the current location of the project on the remote VM.

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

### 2. Install Python and Required Packages
Windows machines, unlike their Unix counterparts, don't come pre-installed with Python.
Requiring us to download and to install it. In addition, we will also need to append it to the system path.
Once we have confirmed that Python exists on the remote VM, we'll run `pip install` and install the required packages for your project.

```powershell
# ConfigureCloudService.ps1
try { 
    # First Test if python is already installed
    Start-Process -FilePath "python" -ArgumentList "-c `"print('hello world')`"" -ErrorAction Stop -Wait
} catch {
    # Download it if it doesn't
    Invoke-WebRequest "https://www.python.org/ftp/python/3.5.2/python-3.5.2.exe" -OutFile "$approot\install_python.exe"
    Start-Process -FilePath "$approot\install_python.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 DefaultAllUsersTargetDir=`"C:\\python\\`"" -Wait
}
Start-Process -FilePath "C:\python\Scripts\pip.exe" -ArgumentList "install -r $approot\requirements.txt" -Wait
```

Note that this installs Python 3.5.2, however you are free to install whatever version you want.


### 3. Install Reverse Proxy
ARR by default isn't installed on IIS 8, so we'll need to download it and install it.
This code will invoke WebPIC, and install ARR with it. If WebPIC doesn't exist, it will
download it as well.

```powershell
# ConfigureCloudService.ps1
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

__Note__: You are accepting ARR's EULA with these lines of code.


### 4. Get Task XML
This XML blob is the format of what the `schtask` command will read when building a new task. 

```xml
<?xml version=`"1.0`" encoding=`"UTF-16`"?>
<Task version=`"1.4`" xmlns=`"http://schemas.microsoft.com/windows/2004/02/mit/task`">
  <RegistrationInfo>
    ...
  </RegistrationInfo>
  <Triggers>
    ...
  </Triggers>
  <Principals>
    ...
  </Principals>
  <Settings>
    ...
  </Settings>
  <Actions Context=`"Author`">
    ...
  </Actions>
</Task>
```

For convenience, this xml blob has been [uploaded](https://raw.githubusercontent.com/qwergram/Django-Azure-PaaS-Guide/master/resources/schtask_webrole.xml).
This allows us to call `Invoke-WebRequest`, write the contents to the disk and edit the contents as neccesary. In our case, we will only need to replace `{{approot}}` with the correct value.

```powershell
Invoke-WebRequest "https://raw.githubusercontent.com/qwergram/Django-Azure-PaaS-Guide/master/resources/schtask_webrole.xml" -OutFile "$approot\schedule.xml"
(Get-Content "$approot\schedule.xml") | Foreach-Object {$_ -replace "{{approot}}", $approot} | Out-File "$approot\schedule.xml" -Encoding ascii
```

### 5. Delete old task
Delete the old schedule task and also kill any running python tasks to prevent two servers running at once.

```powershell
# ConfigureCloudService.ps1
Start-Process -FilePath "schtasks" -ArgumentList "-Delete -TN `"WebServer`" /F" -Wait
Start-Process -FilePath "taskkill" -ArgumentList "/IM python.exe /F" -Wait
```

### 6. Create new task
Use the xml blob that was downloaded to populate a new task and run it.

```powershell
# ConfigureCloudService.ps1
Start-Process -FilePath "schtasks" -ArgumentList "-Create -XML `"$approot\schedule.xml`" -TN `"WebServer`"" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Run -TN `"WebServer`"" -Wait
```

## Write Deployment Script for Worker role

A lot of the existing script we wrote for Webrole can be recycled, the only difference is the name and url of the xml blob.
So from the webrole's `ConfigureCloudService.ps1`, you can copy the first two steps.

### 3. Get Task XML
The only difference here is the [url](https://github.com/qwergram/Django-Azure-PaaS-Guide/blob/master/resources/schtask_workrole.xml) of the Web Request.

```powershell
# ConfigureCloudService.ps1
Invoke-WebRequest "https://raw.githubusercontent.com/qwergram/Django-Azure-PaaS-Guide/master/resources/schtask_workrole.xml" -OutFile "$approot\schedule.xml"
(Get-Content "$approot\schedule.xml") | Foreach-Object {$_ -replace "{{approot}}", $approot} | Out-File "$approot\schedule.xml" -Encoding ascii
```

### 4. Terminate old Task and Schedule a new Task
Much like the web role, use `schtask` to import our xml blob as a task.

```powershell
# ConfigureCloudService.ps1
Start-Process -FilePath "schtasks" -ArgumentList "-Delete -TN `"WorkerRole`" /F" -Wait
Start-Process -FilePath "taskkill" -ArgumentList "/IM python.exe /F" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Create -XML `"$approot\schedule.xml`" -TN `"WorkerRole`"" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Run -TN `"WorkerRole`"" -Wait
```

## Create Reverse Proxy Rules
You should have tw powershell files for the [worker role](https://github.com/qwergram/Django-Azure-PaaS-Guide/blob/master/resources/workerrolescript.ps1) and [web role](https://github.com/qwergram/Django-Azure-PaaS-Guide/blob/master/resources/webrolescript.ps1). 
Your next step is actually deploying from Visual Studio. Unfortunately, there is one step that is unable to be automated: creating the Reverse Proxy rules. You will have to RDC to your machine and
set the rules manually.


 
