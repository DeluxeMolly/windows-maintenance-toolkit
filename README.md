# PC Maintenance Toolkit

A modular PowerShell toolkit for Windows PC maintenance that automates application updates, Windows Updates, system health checks, cleanup, optimisation, logging, and detailed maintenance reporting.

## Features

- Application updates using Winget
- Windows Update checking and installation
- System File Checker (SFC)
- Temporary file cleanup
- Recycle Bin cleanup
- System drive optimisation
- System information collection
- Drive space monitoring
- Detailed maintenance reports
- Log file generation

## Requirements

- Windows 10/11
- PowerShell 5.1 or newer
- Administrator privileges
- Winget installed

## Usage

HOW TO START
------------
Double-click:

    Launch PC Maintenance.cmd

The launcher prefers PowerShell 7 when installed, then safely falls back
to the built-in Windows PowerShell 5.1. It opens the correct v1.1.1 script.
The two older BAT launchers now redirect to this launcher.

SETTINGS
--------
Edit Config\Settings.json before starting the toolkit.

CreateSystemRestorePoint is disabled by default.
RunDISM is disabled by default.

EXIT CODES
----------
0 = completed normally
1 = completed with warnings or an Action Centre item
2 = completed with a failure

## Roadmap

### v1.1
- Action Centre
- Before → Action → After reporting
- Restore Point support
- Configuration file
- Deep Maintenance mode
  
### WHAT CHANGED IN v1.1.1
----------------------
- Fixed the PowerShell 7 launcher and desktop shortcut.
- Added built-in Windows PowerShell 5.1 compatibility.
- Corrected the internal version from 1.1.0 to 1.1.1.
- Counts real Winget package rows instead of console output lines.
- Preserves Winget package IDs containing spaces.
- Verifies installed application updates with a second inventory check.
- Uses one Windows Update search and reports partial/failed updates correctly.
- Counts temporary-file space only after a file is successfully deleted.
- Uses safe literal paths and rejects unsafe cleanup roots.
- Reports fixed drives consistently before and after maintenance.
- Always performs restart detection and deduplicates Action Centre items.
- Shows Completed, Partial, Failed, Skipped, or No work needed for each action.
- Recovers safely from a missing or invalid Settings.json file.
- Respects report opening, report retention, verbose output, and restore-point settings.
- Adds optional DISM Windows image repair through the RunDISM setting.

### v2.0
- Live dashboard
- SMART drive health
- Event Viewer analysis
- Performance monitoring
- Advanced diagnostics

## License

MIT License
