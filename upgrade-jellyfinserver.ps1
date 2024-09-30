param ($register = $false, $dayofWeek = 'Monday', $timeOfDay = '2:00 AM')
#update-jellyfin
<#

1. Check processor architecture. $env:PROCESSOR_ARCHITECTURE

if x64: https://repo.jellyfin.org/?path=/server/windows/latest-stable/amd64
if ARM: https://repo.jellyfin.org/?path=/server/windows/latest-stable/arm64

2. Determine if the version available is higher than what's installed.

3. Get the page, and the downloader for the *.exe installer
4. Stop jellyfin server
5. Silently install the new package
6. Restart JellyFin server
#>

function log($msg, $foregroundcolor = "white")
{
    Write-Host $msg -ForegroundColor $foregroundcolor
    "$(get-date): $msg" | Out-File -FilePath (join-path -path $ENV:TEMP -childpath "JellyFinAutoUpdater.log") -Append
}

function Check-AvailableJellyFinVersion()
{
    try
    {
        log -msg "Checking update page: https://repo.jellyfin.org/?path=/server/windows/latest-stable/$env:PROCESSOR_ARCHITECTURE"
        $updatePage = (Invoke-WebRequest -Uri "https://repo.jellyfin.org/?path=/server/windows/latest-stable/$env:PROCESSOR_ARCHITECTURE" -UseBasicParsing).Content
        $currentVersion = [regex]::match($updatePage,"(?<=\(v).+(?=\))").Groups[0].Value
    }
    catch
    {
        log -msg "Failed to connect to update page: https://repo.jellyfin.org/?path=/server/windows/latest-stable/$env:PROCESSOR_ARCHITECTURE"
        log -msg "Exception $($Error[0])"
    }
    log -msg "Check-AvailableJellyFinVersion returning $currentVersion"
    return $currentVersion
}

function Get-InstalledJellyFinVersion()
{
    
    $JellyFinVer = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinServer\' -Name 'DisplayVersion').DisplayVersion
    log -msg "Get-InstalledJellyFinVersion returning $JellyFinVer"
    return $JellyFinVer
}


function is-newVersionAvailable()
{
    [version]$installedVer = Get-InstalledJellyFinVersion
    [version]$currentVersion = Check-AvailableJellyFinVersion
    if($installedVer -lt $currentVersion -and $env:PROCESSOR_ARCHITECTURE -eq "AMD64")
    {
        log -msg "New version appears to be available!"
        return $true
    }
    log -msg "No newer version available; exiting"
    return $false
}

if($register)
{
    log -msg "Script running in Register mode!"
    # Check for existing scheduled task
    $credential = Get-Credential -Message "Provide your local admin account credentials for Jellyfin Auto-Update Task"

    $task = Get-ScheduledTask -TaskName "UpgradeJellyFin" -ErrorAction Ignore

    # Create new task
    $action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-file `"$($MyInvocation.MyCommand.Path)`""
    $settings = New-ScheduledTaskSettingsSet
    $principal = New-ScheduledTaskPrincipal -UserId $credential.UserName -LogonType Password  -RunLevel Highest
    $trigger = New-ScheduledTaskTrigger -DaysOfWeek $dayofWeek -At $timeOfDay -Weekly
    $newTask = New-ScheduledTask -Action $action -Description "Jellyfin Windows Auto-Update script" -Principal $principal -Settings $settings -Trigger $trigger

    if($task -ne $null)
    {
        # Remove existing task and recreate it.
        Unregister-ScheduledTask -TaskName UpgradeJellyFin -Confirm:$false
    }
   
    Register-ScheduledTask -TaskName UpgradeJellyFin -InputObject $newTask -Password $credential.GetNetworkCredential().Password -User $credential.UserName
    log -msg "Successfully recreated UpgradeJellyFin scheduled task for every $dayofWeek at $timeOfDay"
    exit
}

log -msg "Begin update check!"

if(is-newVersionAvailable)
{

    # Next, get our upgrade package, and run it in silent upgrade mode.
    try
    {
        log -msg "Finished download of upgrade package - executing..."
        $arch = "$env:PROCESSOR_ARCHITECTURE".ToLower()
        log -msg "Checking latest update page: `"https://repo.jellyfin.org/?path=/server/windows/latest-stable/$arch`""
        $downloadPage =  (Invoke-WebRequest -Uri "https://repo.jellyfin.org/?path=/server/windows/latest-stable/$arch" -UseBasicParsing)
        
        $downloadLink = "https://repo.jellyfin.org$(($downloadPage.Links | where-object {$_.href -notlike "*?mirrorlist" -and $_.href -like "*.exe" })[0].href)"

        log -msg "Downloading latest installer: $downloadLink"

        Invoke-WebRequest -Uri $downloadLink -OutFile "$env:TEMP\JellyFinUpdate.exe" -UseBasicParsing
        
        log -msg "Executing update package silent command: $env:TEMP\JellyFinUpdate.exe /S"
        $process = start-process -FilePath "$env:TEMP\JellyFinUpdate.exe" -ArgumentList "/S" -PassThru
        $process.WaitForExit()
        
        if($process.ExitCode -ne 0)
        {
            log -msg "Logged installer failure!  Exit code: $($process.ExitCode)"
            # log -msg "Please check logfile: $($env:TEMP)\JellyFinInstaller.log" NSIS setup doesn't create logfile, sad...
        }

        #If service not running, try to start it.
        $service = Get-Service -Name JellyfinServer
        if($service.Status -ne 'Running' -and $service -ne $null)
        {
            log -msg "Post-upgrade Jellyfin Server service is not running!  Starting..."
            try
            {
                $result = start-service -Name JellyfinServer
            }
            catch
            {
                log -msg "Failed to start Jellyfin Service!  Exception: "
                log -msg $Error[0]
                Throw "Failed to start up!"
            }
        }
        elseif($service -eq $null)
        {
            log -msg "No JellyFin service detected to restart (Basic install possibly?)"
        }
    }
    catch
    {
        log -msg "Failed to download / Execute JellyFin upgrade installer!  Exception below"
        log -msg $Error[0]       
        exit
    }
}

log -msg "End update check!"
