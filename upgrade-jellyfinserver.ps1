#update-jellyfin
<#

1. Check processor architecture. $env:PROCESSOR_ARCHITECTURE

if x64: https://repo.jellyfin.org/?path=/server/windows/latest-stable/amd64
if ARM: https://repo.jellyfin.org/?path=/server/windows/latest-stable/arm64

This only works with amd64, because that is all that has a self-installer.  The zip-deployers will almost assuredly have a custom setup, which they will have to write their own upgrade script for.

2. Determine if the version available is higher than what's installed.

3. Get the page, and the downloader for the *.exe installer
4. Stop jellyfin server
5. Silently install the new package
6. Restart JellyFin server
#>

function log($msg, $foregroundcolor = "white")
{
    Write-Host $msg -ForegroundColor $foregroundcolor
    "$(get-date): $msg" | Out-File -FilePath (join-path -path $ENV:TEMP -childpath "JellyFinUpdater.log") -Append
}

function Check-AvailableJellyFinVersion()
{
    $updatePage = (Invoke-WebRequest -Uri "https://repo.jellyfin.org/?path=/server/windows/latest-stable/$env:PROCESSOR_ARCHITECTURE)").Content
    $currentVersion = [regex]::match($updatePage,"(?<=\(v).+(?=\))").Groups[0].Value
    return $currentVersion
}

function get-installedJellyFinVersion()
{
    $JellyFinVer = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\JellyfinServer\' -Name 'DisplayVersion').DisplayVersion
    return $JellyFinVer
}


function is-newVersionAvailable()
{
    [version]$installedVer = get-installedJellyFinVersion
    [version]$currentVersion = Check-AvailableJellyFinVersion
    if($installedVer -lt $currentVersion -and $env:PROCESSOR_ARCHITECTURE -eq "AMD64")
    {
        return $true
    }
    return $false
}

if(is-newVersionAvailable)
{
    log -msg "Attempting to stop Jellyfin Windows Service..."

    try
    {
        stop-service -force -Name JellyfinServer 
    }
    catch
    {
        log -msg "Failed to stop Jellyfin Windows Service!  Exception below:"
        log -msg $_.Message        
        exit
    }

    # Next, get our upgrade package, and run it in silent upgrade mode.
    try
    {
        Invoke-WebRequest -Uri "https://repo.jellyfin.org/?path=/server/windows/latest-stable/$env:PROCESSOR_ARCHITECTURE?path=/server/windows/latest-stable" -OutFile "$env:TEMP\JellyFinUpgrade.exe"
    }
    catch
    {
        log -msg "Failed to download JellyFin upgrade installer!  Exception below"
        log -msg $_.Message        
        exit
    }

    try
    {
        log -msg "Finished download of upgrade package - executing..."

        log -msg "Checking latest update page: `"https://repo.jellyfin.org/?path=/server/windows/latest-stable/$("$env:PROCESSOR_ARCHITECTURE".ToLower())`""
        $downloadPage =  (Invoke-WebRequest -Uri "https://repo.jellyfin.org/?path=/server/windows/latest-stable/$("$env:PROCESSOR_ARCHITECTURE".ToLower())")
        
        $downloadLink = "https://repo.jellyfin.org$(($downloadPage.Links | where-object {$_.href -notlike "*?mirrorlist" -and $_.href -like "*.exe" })[0].href)"

        log -msg "Downloading latest installer: $downloadLink"

        Invoke-WebRequest -Uri $downloadLink -OutFile "$env:TEMP\JellyFinUpdate.exe"

        log -msg "Executing update package silent command: $env:TEMP\JellyFinUpdate.exe /S"
        $process = start-process -FilePath "$env:TEMP\JellyFinUpdate.exe" -ArgumentList "/S"
        $process.WaitForExit()

        if($process.ExitCode -ne 0)
        {
            log -msg "Logged installer failure!  Exit code: $($process.ExitCode)"
            log -msg "Please check logfile: "
        }

        $service = Get-Service -Name JellyfinServer
        if($service.Status -ne 'Running')
        {
            log -msg "Post-upgrade Jellyfin Server service is not running!  Starting..."
            try
            {
                $result = start-service -Name JellyfinServer
            }
            catch
            {
                log -msg "Failed to start Jellyfin Service!  Exception: "
                log -msg $_.Message 
                Throw "Failed to start up!"
            }
        }
    }
    catch
    {
        log -msg "Failed to download / Execute JellyFin upgrade installer!  Exception below"
        log -msg $_.Message        
        exit
    }
}
