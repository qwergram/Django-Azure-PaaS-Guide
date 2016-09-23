if (Test-Path "E:\approot\") {
    $approot = "E:\approot"
} elseif (Test-Path "F:\approot\") {
    $approot = "F:\approot"
} else {
    throw "approot not found"
}

Invoke-WebRequest "https://raw.githubusercontent.com/qwergram/Django-Azure-PaaS-Guide/master/resources/schtask_workrole.xml" -OutFile "$approot\schedule.xml"
(Get-Content "$approot\schedule.xml") | Foreach-Object {$_ -replace "{{approot}}", $approot} | Out-File "$approot\schedule.xml" -Encoding ascii

try { 
    # First Test if python is already installed
    Start-Process -FilePath "python" -ArgumentList "-c `"print('hello world')`"" -ErrorAction Stop -Wait
} catch {
    # Download it if it doesn't
    Invoke-WebRequest "https://www.python.org/ftp/python/3.5.2/python-3.5.2.exe" -OutFile "$approot\install_python.exe"
    Start-Process -FilePath "$approot\install_python.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 DefaultAllUsersTargetDir=`"C:\\python\\`"" -Wait
}
Start-Process -FilePath "C:\python\Scripts\pip.exe" -ArgumentList "install -r $approot\requirements.txt" -Wait

if (Test-Path "$env:ProgramFiles\microsoft\web platform installer\WebpiCmd-x64.exe") {
    Start-Process -FilePath "$env:ProgramFiles\microsoft\web platform installer\WebpiCmd-x64.exe" -ArgumentList "/Install /Products:ARR /accepteula" -Wait
} else {
    # Install webpi
    Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=226239" -OutFile "$approot\install_webpi.msi"
    Start-Process -FilePath "msiexec" -ArgumentList "/i install_webpi.msi /quiet ADDLOCAL=ALL" -Wait
    # Install ARR
    Start-Process -FilePath "$env:ProgramFiles\microsoft\web platform installer\WebpiCmd-x64.exe" -ArgumentList "/Install /Products:ARR /accepteula" -Wait
}

Start-Process -FilePath "schtasks" -ArgumentList "-Delete -TN `"WorkerRole`" /F" -Wait
Start-Process -FilePath "taskkill" -ArgumentList "/IM python.exe /F" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Create -XML `"$approot\schedule.xml`" -TN `"WorkerRole`"" -Wait
Start-Process -FilePath "schtasks" -ArgumentList "-Run -TN `"WorkerRole`"" -Wait