
<#PSScriptInfo

.VERSION 1.0

.GUID 8b85dd83-99a4-4338-b098-834ee543104e

.AUTHOR stefa

.COMPANYNAME 

.COPYRIGHT 

.TAGS 

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES


#>

<# 

.DESCRIPTION 
 install a new JenkinsCI instance 

#> 
[cmdletBinding()]
Param(
    [ValidateNotNullOrEmpty()]
    [System.IO.FileInfo]$InstallDir = [System.IO.Path]::GetTempPath(),
    [ValidateNotNullOrEmpty()]
    [switch]$Guid = $false
)

function InstallPlugins {
    Invoke-WebRequest -Uri http://localhost:8080/jnlpJars/jenkins-cli.jar -UseBasicParsing -OutFile  $(Join-Path $localjenkinsPath 'jenkins-cli.jar') -MaximumRetryCount 180 -RetryIntervalSec 1
    $plugins = Get-Content $(Join-Path $PSScriptRoot 'plugin-list.json') | ConvertFrom-Json
    foreach ($url in $plugins.pluginUrl) {
        &java.exe @( '-jar', $(Join-Path $localjenkinsPath 'jenkins-cli.jar'), '-s', 'http://localhost:8080', 'install-plugin',$url)
    }
    # &java.exe @( '-jar', $(Join-Path $localjenkinsPath 'jenkins-cli.jar'), '-s', 'http://localhost:8080', 'restart' )
}


if (!$InstallDir | Test-Path) {
    New-Item -Path $InstallDir -ItemType Directory -force | Out-Null
}
Push-Location $InstallDir
Write-Verbose "InstallDir: $InstallDir"
Invoke-WebRequest -Uri https://get.jenkins.io/war-stable/2.263.4/jenkins.war.sha256 -UseBasicParsing -OutFile  'jenkins.war.sha256'
If (Test-Path 'jenkins.war' ) {
    $found = (Get-Content 'jenkins.war.sha256') -match '^(.*)\s'
    if ( $found -and (Get-FileHash 'jenkins.war' -Algorithm SHA256).Hash -ieq $matches[0].Trim() ) {
        write-verbose 'Jenkins.war is in install dir'
    } else {
        Invoke-WebRequest -Uri https://get.jenkins.io/war-stable/2.263.4/jenkins.war -UseBasicParsing -OutFile  'jenkins.war'
    }
} else {
    Invoke-WebRequest -Uri https://get.jenkins.io/war-stable/2.263.4/jenkins.war -UseBasicParsing -OutFile  'jenkins.war'
}
Pop-Location

$localjenkinsPath = $guid.IsPresent ? (Join-Path $InstallDir $(New-Guid).Guid) : $InstallDir
if ( ! $localjenkinsPath | Test-Path) {
    $null = New-Item -Path $localjenkinsPath -ItemType Directory -force
}
$null = New-Item -Path $( Join-Path $localjenkinsPath 'plugins' ) -ItemType Directory -force
$null = New-Item -Path $( Join-Path $localjenkinsPath 'logs' ) -ItemType Directory -force

#$env:JENKINS_HOME = $localjenkinsPath
#Push-Location $localjenkinsPath
#Invoke-Expression -command "java.exe -version"
# $jenkinsProcess = Start-Process -FilePath java.exe -ArgumentList @('-Djenkins.install.runSetupWizard=false', "-DJENKINS_HOME=$localjenkinsPath", '-jar', $(Join-Path $Installdir 'jenkins.war')) -RedirectStandardOutput $(Join-Path $localjenkinsPath 'logs' 'jenkins-firstStart.log') -RedirectStandardError $(Join-Path $localjenkinsPath 'logs' 'jenkins-firstStart-error.log') -PassThru

# $watcher = New-Object IO.FileSystemWatcher (Join-Path $localjenkinsPath 'logs'), 'jenkins*.log' -Property @{ 
#     IncludeSubdirectories = $false 
#     EnableRaisingEvents = $true
# }
# Register-ObjectEvent -InputObject $watcher -EventName 'Changed' -SourceIdentifier FileChanged -Action {
#     $path = $Event.SourceEventArgs.FullPath
#     $name = $Event.SourceEventArgs.Name
#     $changeType = $Event.SourceEventArgs.ChangeType
#     $timeStamp = $Event.TimeGenerated
#     Write-Host "The file '$path' was $changeType at $timeStamp"
# } 


#Start-Sleep 1
#Pop-Location
#Get-Member -InputObject $jenkinsProcess -MemberType Event


$jenkinsWarFile = Join-Path $Installdir 'jenkins.war'
$jenkinsProcess = New-Object -TypeName System.Diagnostics.Process
$jenkinsProcess.StartInfo.FileName = 'java.exe'
$jenkinsProcess.StartInfo.Arguments = "-Djenkins.install.runSetupWizard=false -DJENKINS_HOME=$localjenkinsPath -jar  $jenkinsWarFile"
$jenkinsProcess.StartInfo.UseShellExecute = $false
$jenkinsProcess.StartInfo.RedirectStandardOutput = $true
$jenkinsProcess.StartInfo.RedirectStandardError = $true
$jenkinsProcess.StartInfo.CreateNoWindow = $false

$global:isJenkinsStarted = $false
$sScripBlock = {
    if (! [String]::IsNullOrEmpty($EventArgs.Data)) {
        write-host $EventArgs.Data
        if ($EventArgs.Data -match 'Jenkins is fully up and running') {
            write-host "jenkins ready"
            $Event.MessageData.CancelOutputRead()
            $Event.MessageData.CancelErrorRead()
            $global:isJenkinsStarted = $true
        }
    }
}
$global:oStdOutEvent = Register-ObjectEvent -InputObject $jenkinsProcess -Action $sScripBlock -EventName 'OutputDataReceived' -MessageData $jenkinsProcess

$global:oStdErrEvent = Register-ObjectEvent -InputObject $jenkinsProcess -Action $sScripBlock -EventName 'ErrorDataReceived' -MessageData $jenkinsProcess
$jenkinsProcess.Start()
$jenkinsProcess.BeginOutputReadLine()
$jenkinsProcess.BeginErrorReadLine()

while ($true) {
    if ($global:isJenkinsStarted) {
        InstallPlugins
        write-verbose "Plugins installed"
        $jenkinsProcess.kill()
        break
    }
    Start-Sleep -ms 100
}
$jenkinsProcess.WaitForExit()
Unregister-Event -SourceIdentifier $oStdOutEvent.Name
Unregister-Event -SourceIdentifier $oStdErrEvent.Name

write-verbose "ID: $($jenkinsProcess.ID)"
Write-Verbose "Jenkins-Home $localjenkinsPath"

$null = New-Item -Path "$localjenkinsPath\jcasc" -ItemType Directory -Force
Copy-Item -path "$PSScriptRoot\..\jcasc\*" -Destination "$localjenkinsPath\jcasc" -Force
#$env:CASC_JENKINS_CONFIG = "$localjenkinsPath\jcasc"
#[Void]$jenkinsProcess.WaitForExit()
Start-Process -FilePath java.exe -ArgumentList @('-Djenkins.install.runSetupWizard=false', "-DJENKINS_HOME=$localjenkinsPath", "-Dcasc.jenkins.config=$(Join-Path $localjenkinsPath 'jcasc' 'jenkins.yaml')", '-jar', $(Join-Path $Installdir 'jenkins.war')) 
