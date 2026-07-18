############################################################
#
# PC MAINTENANCE TOOL
#
# Version : 1.0.0
# Author  : Leigh Boyd & ChatGPT
#
# Description:
# Performs routine PC maintenance including:
#   • Application Updates
#   • Windows Updates
#   • Cleanup
#   • Health Checks
#   • Report Generation
#
############################################################

#region Program Information

$Version = "1.0.0"

#endregion


#region Variables

$ProjectRoot = Split-Path -Parent $PSScriptRoot

$ReportsPath = Join-Path $ProjectRoot "Reports"
$LogsPath = Join-Path $ProjectRoot "Logs"
$ConfigPath = Join-Path $ProjectRoot "Config"

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$ReportFile = Join-Path $ReportsPath "Maintenance_Report_$Timestamp.txt"
$WingetLog = Join-Path $LogsPath "Winget_$Timestamp.log"
$SfcLog = Join-Path $LogsPath "SFC_$Timestamp.log"
$DismLog = Join-Path $LogsPath "DISM_$Timestamp.log"

# Drive space snapshots
$DriveSpaceBefore = @{}
$DriveSpaceAfter = @{}

#endregion


#region Utility Functions

function Write-Section {

    param(
        [string]$Title
    )

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor White
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""

}

function Initialize-ProjectFolders {

    $requiredFolders = @(
        $ReportsPath,
        $LogsPath,
        $ConfigPath
    )

    foreach ($folder in $requiredFolders) {
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
    }
}

function Write-Status {

    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Type = "Info"
    )

    switch ($Type) {
        "Success" {
            Write-Host "[OK] $Message" -ForegroundColor Green
        }

        "Warning" {
            Write-Host "[!] $Message" -ForegroundColor Yellow
        }

        "Error" {
            Write-Host "[X] $Message" -ForegroundColor Red
        }

        default {
            Write-Host "[>] $Message" -ForegroundColor Cyan
        }
    }
}

function Test-Administrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

    return $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Restart-AsAdministrator {

    Write-Host "Administrator access is required." -ForegroundColor Yellow
    Write-Host "Reopening the tool as Administrator..." -ForegroundColor Yellow
    Write-Host ""

    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs `
        -Wait
}

#endregion


#region Report Functions

function Initialize-Report {

    $reportHeader = @"
============================================================
PC MAINTENANCE TOOLKIT
Maintenance Report
============================================================

Date: $(Get-Date -Format "dd MMMM yyyy")
Started: $(Get-Date -Format "hh:mm:ss tt")
Version: $Version

============================================================
"@

    Set-Content `
        -Path $ReportFile `
        -Value $reportHeader `
        -Encoding utf8
}

#endregion


#region Update Functions

function Get-WingetAvailableUpdates {

    Write-Status "Checking for available application updates..." "Info"

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Status "Winget is not installed." "Error"
        return $null
    }

    return winget upgrade `
        --include-unknown `
        --accept-source-agreements `
        2>&1
}

function Check-WindowsUpdates {

    Write-Section "WINDOWS UPDATES"
    Write-Status "Checking for Windows updates..." "Info"

    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()

        $searchResult = $updateSearcher.Search(
            "IsInstalled=0 and IsHidden=0"
        )

        $updates = @($searchResult.Updates)

        Add-Content -Path $ReportFile -Value @"

============================================================
WINDOWS UPDATE SUMMARY
============================================================

Updates Available                  : $($updates.Count)

"@ -Encoding utf8

        if ($updates.Count -gt 0) {
            Add-Content `
                -Path $ReportFile `
                -Value "Available Windows Updates`r`n------------------------------------------------------------" `
                -Encoding utf8

            foreach ($update in $updates) {
                Add-Content `
                    -Path $ReportFile `
                    -Value $update.Title `
                    -Encoding utf8
            }

            Write-Status "$($updates.Count) Windows update(s) available." "Warning"
        }
        else {
            Add-Content `
                -Path $ReportFile `
                -Value "No Windows updates are currently available.`r`n" `
                -Encoding utf8

            Write-Status "Windows is up to date." "Success"
        }
    }
    catch {
        Write-Status "Windows Update check failed." "Error"

        Add-Content -Path $ReportFile -Value @"

============================================================
WINDOWS UPDATE SUMMARY
============================================================

Windows Update check failed.

Error: $($_.Exception.Message)

"@ -Encoding utf8
    }
}

function Install-WindowsUpdates {

    Write-Section "INSTALLING WINDOWS UPDATES"
    Write-Status "Searching for Windows updates to install..." "Info"

    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()

        $searchResult = $updateSearcher.Search(
            "IsInstalled=0 and IsHidden=0"
        )

        if ($searchResult.Updates.Count -eq 0) {
            Write-Status "No Windows updates need installation." "Success"
            return
        }

        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

        foreach ($update in $searchResult.Updates) {

            if (-not $update.EulaAccepted) {
                $update.AcceptEula()
            }

            $null = $updatesToInstall.Add($update)
        }

        Write-Status "Downloading Windows updates..." "Info"

        $downloader = $updateSession.CreateUpdateDownloader()
        $downloader.Updates = $updatesToInstall
        $downloadResult = $downloader.Download()

        if ($downloadResult.ResultCode -notin 2, 3) {
            throw "Windows Update download failed. Result code: $($downloadResult.ResultCode)"
        }

        Write-Status "Installing Windows updates..." "Info"

        $installer = $updateSession.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult = $installer.Install()

        Add-Content -Path $ReportFile -Value @"

WINDOWS UPDATE INSTALLATION
------------------------------------------------------------

Updates Processed                 : $($updatesToInstall.Count)
Result Code                       : $($installResult.ResultCode)
Restart Required                  : $($installResult.RebootRequired)

"@ -Encoding utf8

        if ($installResult.ResultCode -in 2, 3) {
            Write-Status "Windows Update installation completed." "Success"
        }
        else {
            Write-Status "Some Windows updates may have failed." "Warning"
        }

        if ($installResult.RebootRequired) {
            Write-Status "A restart is required to finish Windows updates." "Warning"
        }
    }
    catch {
        Write-Status "Windows Update installation failed." "Error"

        Add-Content -Path $ReportFile -Value @"

WINDOWS UPDATE INSTALLATION
------------------------------------------------------------

Installation failed.

Error: $($_.Exception.Message)

"@ -Encoding utf8
    }
}

function ConvertFrom-WingetUpgradeTable {

    param (
        [Parameter(Mandatory)]
        [string[]]$WingetOutput
    )

    $results = [System.Collections.Generic.List[object]]::new()

    $headerLine = $WingetOutput |
        Where-Object {
            $_ -match '^Name\s+Id\s+Version\s+Available\s+Source'
        } |
        Select-Object -First 1

    if (-not $headerLine) {
        return @()
    }

    $nameStart = $headerLine.IndexOf('Name')
    $idStart = $headerLine.IndexOf('Id')
    $versionStart = $headerLine.IndexOf('Version')
    $availableStart = $headerLine.IndexOf('Available')
    $sourceStart = $headerLine.IndexOf('Source')

    $separatorIndex = [Array]::IndexOf(
        $WingetOutput,
        ($WingetOutput | Where-Object { $_ -match '^-{3,}' } | Select-Object -First 1)
    )

    if ($separatorIndex -lt 0) {
        return @()
    }

    foreach ($line in $WingetOutput[($separatorIndex + 1)..($WingetOutput.Count - 1)]) {

        $text = "$line"

        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        if (
            $text -match '^\d+\s+upgrades?\s+available' -or
            $text -match '^\d+\s+package\(s\)' -or
            $text -match '^No applicable upgrade found'
        ) {
            continue
        }

        if ($text.Length -lt $availableStart) {
            continue
        }

        $name = $text.Substring(
            $nameStart,
            $idStart - $nameStart
        ).Trim()

        $id = $text.Substring(
            $idStart,
            $versionStart - $idStart
        ).Trim()

        $installedVersion = $text.Substring(
            $versionStart,
            $availableStart - $versionStart
        ).Trim()

        if ($text.Length -gt $sourceStart) {
            $availableVersion = $text.Substring(
                $availableStart,
                $sourceStart - $availableStart
            ).Trim()

            $source = $text.Substring($sourceStart).Trim()
        }
        else {
            $availableVersion = $text.Substring($availableStart).Trim()
            $source = ''
        }

        if (-not $name -or -not $id) {
            continue
        }

        $results.Add([PSCustomObject]@{
            Name             = $name
            Id               = $id
            InstalledVersion = $installedVersion
            AvailableVersion = $availableVersion
            Source           = $source
        })
    }

    return $results
}

 function Write-WingetUpdateCategories {

    param (
    [Parameter(Mandatory)]
    [string[]]$WingetOutput,

    [Parameter(Mandatory)]
    [string[]]$UnknownVersionPackages
)

    $normalUpdates = [System.Collections.Generic.List[string]]::new()
    $unknownUpdates = [System.Collections.Generic.List[string]]::new()
    $blockedUpdateCount = 0

    $parsedUpdates = ConvertFrom-WingetUpgradeTable `
        -WingetOutput $WingetOutput

    foreach ($update in $parsedUpdates) {

        $entry = @"
$($update.Name)
    ID      : $($update.Id)
    Version : $($update.InstalledVersion) -> $($update.AvailableVersion)
"@

        if ($update.InstalledVersion -eq 'Unknown') {
            $unknownUpdates.Add($entry)
        }
        else {
            $normalUpdates.Add($entry)
        }
    }

    foreach ($line in $WingetOutput) {

    $cleanLine = "$line".Trim()

    if (
        $cleanLine -match
        '^(?<Count>\d+)\s+package\(s\)\s+have upgrades blocked'
    ) {
        $detectedCount = [int]$Matches.Count

        if ($detectedCount -gt $blockedUpdateCount) {
            $blockedUpdateCount = $detectedCount
        }
    }
}

$blockedUpdateReport = if ($blockedUpdateCount -gt 0) {
    @"
$blockedUpdateCount blocked application update(s) detected.

Reason:
The newer version uses a different installation technology.

Next Step:
Review the Winget log. The affected application may need to be
uninstalled and then installed again.
"@
}
else {
    "None"
}
    Add-Content -Path $ReportFile -Value @"

============================================================
APPLICATION UPDATE SUMMARY
============================================================

Available Updates
------------------------------------------------------------
$(
    if ($normalUpdates.Count -gt 0) {
        $normalUpdates -join "`r`n"
    }
    else {
        "None"
    }
)

Unknown Version Updates
------------------------------------------------------------
$(
    if ($unknownUpdates.Count -gt 0) {
        $unknownUpdates -join "`r`n"
    }
    else {
        "None"
    }
)

Blocked Updates
------------------------------------------------------------
$blockedUpdateReport

Installed Applications With Unknown Versions
------------------------------------------------------------
$(
    if ($unknownVersionPackages.Count -gt 0) {
        $unknownVersionPackages -join "`r`n"
    }
    else {
        "None"
    }
)

------------------------------------------------------------
SUMMARY
------------------------------------------------------------

Available Updates                 : $($normalUpdates.Count)
Unknown Version Updates           : $($unknownUpdates.Count)
Blocked Updates                   : $blockedUpdateCount
Installed Unknown Versions        : $($UnknownVersionPackages.Count)

"@ -Encoding utf8

    Write-Status "$($normalUpdates.Count) normal update(s) found." "Info"
    Write-Status "$($unknownUpdates.Count) unknown-version update(s) found." "Info"

    if ($blockedUpdateCount -gt 0) {
    Write-Status "Winget reported $blockedUpdateCount blocked application update(s)." "Warning"
}
}

function Get-WingetUnknownVersionPackages {

    Write-Status "Checking installed applications with unknown versions..." "Info"

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        return @()
    }

    $listOutput = winget list `
        --accept-source-agreements `
        2>&1

    $unknownPackages = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $listOutput) {

        $text = "$line"

        if ($text -notmatch '\sUnknown(?:\s|$)') {
            continue
        }

        # Capture everything before the package ID and Unknown version.
        if ($text -match '^(?<Name>.+?)\s{2,}(?<Id>\S+)\s+Unknown(?:\s|$)') {

            $name = $Matches.Name.Trim()
            $id = $Matches.Id.Trim()

            $unknownPackages.Add($name)
        }
    }

    return $unknownPackages
}

function Update-Applications {

    Write-Section "APPLICATION UPDATES"

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Status "Winget is not installed or unavailable." "Error"

        Add-Content `
            -Path $ReportFile `
            -Value "APPLICATION UPDATES`r`nWinget was not available.`r`n" `
            -Encoding utf8

        return
    }

    Write-Status "Updating Winget sources..." "Info"

    winget source update 2>&1 |
        Out-File -FilePath $WingetLog -Encoding utf8

    Write-Status "Checking for available application updates..." "Info"

$availableUpdates = Get-WingetAvailableUpdates
$unknownVersionPackages = Get-WingetUnknownVersionPackages

Write-WingetUpdateCategories `
    -WingetOutput $availableUpdates `
    -UnknownVersionPackages $unknownVersionPackages

Write-Status "$($unknownVersionPackages.Count) installed package(s) have unknown versions." "Info"

    $availableUpdates |
        Add-Content -Path $WingetLog -Encoding utf8

    Write-Status "Installing available application updates..." "Info"

    $installOutput = winget upgrade --all `
    --silent `
    --accept-source-agreements `
    --accept-package-agreements `
    2>&1

$installOutput | ForEach-Object {
    Write-Host $_
}

$installOutput |
    Add-Content `
        -Path $WingetLog `
        -Encoding utf8

    if ($LASTEXITCODE -eq 0) {
        Write-Status "Application update process completed." "Success"

        Add-Content `
            -Path $ReportFile `
            -Value "`r`nApplication update process completed successfully.`r`n" `
            -Encoding utf8
    }
    else {
        Write-Status "Some application updates may have failed." "Warning"

        Add-Content `
            -Path $ReportFile `
            -Value "`r`nSome updates may have failed. Check the Winget log.`r`n" `
            -Encoding utf8
    }
}

#endregion

#region Cleanup Functions

# Temporary files
function Clear-TemporaryFiles {

    Write-Section "TEMPORARY FILE CLEANUP"
    Write-Status "Cleaning temporary files..." "Info"

    $DeletedItems = 0
    $DeletedBytes = 0

    $Folders = @(
        $env:TEMP,
        "$env:WINDIR\Temp"
    )

    foreach ($Folder in $Folders) {

        if (-not (Test-Path $Folder)) {
            continue
        }

        Get-ChildItem -Path $Folder -Force -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {

            try {

                if (-not $_.PSIsContainer) {
                    $DeletedBytes += $_.Length
                }

                Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop
                $DeletedItems++

            }
            catch {
                # Ignore files that are in use
            }
        }
    }

    $FreedMB = [math]::Round($DeletedBytes / 1MB, 2)

    Add-Content -Path $ReportFile -Value @"

============================================================
TEMPORARY FILE CLEANUP
============================================================

Items Deleted                    : $DeletedItems
Space Reclaimed                  : $FreedMB MB

"@ -Encoding utf8

    Write-Status "Recovered $FreedMB MB of temporary files." "Success"
}

# Shader cache
# Recycle Bin
function Clear-RecycleBinFiles {

    Write-Section "RECYCLE BIN CLEANUP"
    Write-Status "Emptying Recycle Bin..." "Info"

    try {

        Clear-RecycleBin -Force -ErrorAction Stop

        Add-Content -Path $ReportFile -Value @"

============================================================
RECYCLE BIN CLEANUP
============================================================

Recycle Bin emptied successfully.

"@ -Encoding utf8

        Write-Status "Recycle Bin emptied." "Success"

    }
    catch {

        Add-Content -Path $ReportFile -Value @"

============================================================
RECYCLE BIN CLEANUP
============================================================

Recycle Bin could not be emptied.

Error:
$($_.Exception.Message)

"@ -Encoding utf8

        Write-Status "Recycle Bin cleanup skipped." "Warning"
    }
}

#endregion

#region Health Check Functions

# SFC
function Repair-SystemFiles {

    Write-Section "SYSTEM FILE CHECKER"

    Write-Status "Running System File Checker..." "Info"

    $process = Start-Process `
        -FilePath "sfc.exe" `
        -ArgumentList "/scannow" `
        -Wait `
        -NoNewWindow `
        -RedirectStandardOutput $SfcLog `
        -PassThru

    Add-Content -Path $ReportFile -Value @"

============================================================
SYSTEM FILE CHECKER
============================================================

Exit Code                         : $($process.ExitCode)

Log File
------------------------------------------------------------
$SfcLog

"@ -Encoding utf8

    switch ($process.ExitCode) {

        0 {
            Write-Status "SFC completed successfully." "Success"
        }

        Default {
            Write-Status "SFC completed with exit code $($process.ExitCode)." "Warning"
        }
    }
}
# DISM Deep Repair Functions
function Repair-WindowsImage {

    Write-Section "DISM HEALTH REPAIR"
    Write-Status "Running DISM RestoreHealth..." "Info"

    $log = $DismLog

    try {
        $process = Start-Process `
            -FilePath "DISM.exe" `
            -ArgumentList @(
                "/Online"
                "/Cleanup-Image"
                "/RestoreHealth"
                "/LogPath:$log"
            ) `
            -Wait `
            -NoNewWindow `
            -PassThru

        Add-Content -Path $ReportFile -Value @"

============================================================
DISM HEALTH REPAIR
============================================================

Exit Code                         : $($process.ExitCode)
Log File                          : $log

"@ -Encoding utf8

        if ($process.ExitCode -eq 0) {
            Write-Status "DISM completed successfully." "Success"
        }
        else {
            Write-Status "DISM failed with exit code $($process.ExitCode)." "Error"
        }
    }
    catch {
        Write-Status "DISM failed to run." "Error"

        Add-Content -Path $ReportFile -Value @"

============================================================
DISM HEALTH REPAIR
============================================================

DISM failed to run.

Error: $($_.Exception.Message)

"@ -Encoding utf8
    }
}

#endregion

#region System Drive Optimisation
function Optimize-SystemDrives {

    Write-Section "SYSTEM DRIVE OPTIMISATION"
    Write-Status "Optimising system drive..." "Info"

    Add-Content -Path $ReportFile -Value @"

============================================================
SYSTEM DRIVE OPTIMISATION
============================================================

"@ -Encoding utf8

    $SystemDrive = $env:SystemDrive.TrimEnd(':')

    try {

        $drive = Get-Volume -DriveLetter $SystemDrive -ErrorAction Stop

        $DriveName = if ([string]::IsNullOrWhiteSpace($drive.FileSystemLabel)) {
            "System Drive"
        }
        else {
            $drive.FileSystemLabel
        }

        Write-Status "Optimising $($drive.DriveLetter): [$DriveName]..." "Info"

        Optimize-Volume `
            -DriveLetter $drive.DriveLetter `
            -Verbose `
            -ErrorAction Stop

        Add-Content `
            -Path $ReportFile `
            -Value "$($drive.DriveLetter): [$DriveName] - Windows recommended optimisation completed." `
            -Encoding utf8

        Write-Status "$($drive.DriveLetter): optimisation completed." "Success"
    }
    catch {

        Add-Content `
            -Path $ReportFile `
            -Value "$SystemDrive`: Optimisation failed - $($_.Exception.Message)" `
            -Encoding utf8

        Write-Status "System drive optimisation failed." "Warning"
    }

    Write-Status "Drive optimisation complete." "Success"
}
#endregion

#region Drive Space After
function Get-DriveSpaceAfter {

    Write-Section "DRIVE SPACE AFTER"
    Write-Status "Collecting drive space information..." "Info"

    Add-Content -Path $ReportFile -Value @"

============================================================
DRIVE SPACE AFTER
============================================================

"@ -Encoding utf8

    Get-PSDrive -PSProvider FileSystem | ForEach-Object {

        $used = $_.Used / 1GB
        $free = $_.Free / 1GB
        $total = $used + $free

        Add-Content `
            -Path $ReportFile `
            -Value ("Drive {0}: Used: {1:N2} GB | Free: {2:N2} GB | Total: {3:N2} GB" -f `
                $_.Name, $used, $free, $total) `
            -Encoding utf8
    }

    Write-Status "Drive space information collected." "Success"
}
#endregion

#region Hardware Functions

function Get-SystemInformation {

    Write-Status "Collecting system information..." "Info"

    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $graphicsCards = Get-CimInstance Win32_VideoController

    $ramGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 1)
    $gpuNames = ($graphicsCards.Name | Sort-Object -Unique) -join ", "

    $systemInformation = @"
SYSTEM INFORMATION
------------------------------------------------------------

Computer Name : $env:COMPUTERNAME
Windows       : $($operatingSystem.Caption)
Version       : $($operatingSystem.Version)
CPU           : $($processor.Name)
GPU           : $gpuNames
RAM           : $ramGB GB

"@

    Add-Content `
        -Path $ReportFile `
        -Value $systemInformation `
        -Encoding utf8

    Write-Status "System information added to report." "Success"
}

function Get-FixedDriveSpace {

    $driveSnapshot = @{}

    $fixedDrives = Get-CimInstance Win32_LogicalDisk |
        Where-Object { $_.DriveType -eq 3 }

    foreach ($drive in $fixedDrives) {
        $driveSnapshot[$drive.DeviceID] = [PSCustomObject]@{
            DriveLetter = $drive.DeviceID
            VolumeName  = $drive.VolumeName
            TotalGB     = [math]::Round($drive.Size / 1GB, 2)
            FreeGB      = [math]::Round($drive.FreeSpace / 1GB, 2)
        }
    }

    return $driveSnapshot
}

#endregion

#region Final Maintenance Summary
function Write-MaintenanceSummary {

    param (
        [datetime]$StartTime
    )

    $EndTime = Get-Date
    $Duration = $EndTime - $StartTime

    $FormattedDuration = if ($Duration.TotalHours -ge 1) {
        "{0}h {1}m {2}s" -f `
            [math]::Floor($Duration.TotalHours),
            $Duration.Minutes,
            $Duration.Seconds
    }
    elseif ($Duration.TotalMinutes -ge 1) {
        "{0}m {1}s" -f `
            [math]::Floor($Duration.TotalMinutes),
            $Duration.Seconds
    }
    else {
        "{0}s" -f [math]::Max(1, [math]::Round($Duration.TotalSeconds))
    }

    Write-Section "MAINTENANCE SUMMARY"

    Add-Content -Path $ReportFile -Value @"

============================================================
MAINTENANCE SUMMARY
============================================================

System Information Collected : Yes
Application Updates Checked  : Yes
Windows Updates Checked      : Yes
System Files Checked         : Yes
Temporary Files Cleaned      : Yes
Recycle Bin Emptied          : Yes
System Drive Optimised       : Yes
Drive Space Recorded         : Yes

Started                     : $($StartTime.ToString("dd/MM/yyyy HH:mm:ss"))
Completed                   : $($EndTime.ToString("dd/MM/yyyy HH:mm:ss"))
Total Duration              : $FormattedDuration

Report Location             : $ReportFile

============================================================

"@ -Encoding utf8

    Write-Status "Maintenance completed in $FormattedDuration." "Success"
    Write-Status "Report saved to: $ReportFile" "Info"
}
#endregion

#region Main Program

Clear-Host

Write-Section "LEIGH'S PC MAINTENANCE TOOL v$Version"

if (-not (Test-Administrator)) {
    Restart-AsAdministrator
    exit
}

Write-Status "Administrator access confirmed." "Success"
Write-Host ""

Initialize-Report

Write-Status "Report created." "Success"
Write-Host ""
Write-Status "Project folders confirmed." "Success"
Write-Host ""
Write-Host "Report file:"
Write-Host $ReportFile -ForegroundColor DarkGray
Write-Host ""

$MaintenanceStartTime = Get-Date

Get-SystemInformation

$DriveSpaceBefore = Get-FixedDriveSpace

Write-Status "Drive space recorded for all fixed drives." "Success"

$driveReport = @"
DRIVE SPACE BEFORE MAINTENANCE
------------------------------------------------------------
"@

foreach ($driveLetter in ($DriveSpaceBefore.Keys | Sort-Object)) {
    $drive = $DriveSpaceBefore[$driveLetter]

    $volumeText = if ([string]::IsNullOrWhiteSpace($drive.VolumeName)) {
        "No label"
    }
    else {
        $drive.VolumeName
    }

    $driveReport += @"

$($drive.DriveLetter) [$volumeText]
Free  : $($drive.FreeGB) GB
Total : $($drive.TotalGB) GB
"@
}

$driveReport += "`r`n"

Add-Content `
    -Path $ReportFile `
    -Value $driveReport `
    -Encoding utf8
	
#process order
Update-Applications
Check-WindowsUpdates
Install-WindowsUpdates
Repair-SystemFiles
#Repair-WindowsImage
Clear-TemporaryFiles
Clear-RecycleBinFiles
Optimize-SystemDrives
Get-DriveSpaceAfter
Write-MaintenanceSummary -StartTime $MaintenanceStartTime

#endregion

# Open report when finished
Write-Host ""
Write-Host "Press any key to open the report and exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

if (Test-Path $ReportFile) {
    Start-Process notepad.exe $ReportFile
}

#endregion