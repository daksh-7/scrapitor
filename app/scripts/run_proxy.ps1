#Requires -Version 7.0
<#
.SYNOPSIS
    Scrapitor Local Proxy - Start Flask server with Cloudflare tunnel
.DESCRIPTION
    Launches the Scrapitor proxy server and establishes a Cloudflare tunnel
    for external access. Press Q to quit gracefully.
.PARAMETER Verbose
    Show detailed output during startup
#>
[CmdletBinding()]
param(
    [switch]$VerboseOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ══════════════════════════════════════════════════════════════════════════════
#  Bootstrap
# ══════════════════════════════════════════════════════════════════════════════

$ScriptDir = $PSScriptRoot
$AppRoot = Split-Path $ScriptDir -Parent
$RepoRoot = Split-Path $AppRoot -Parent
Set-Location -Path $RepoRoot

# Import modules
$ModulesDir = Join-Path $ScriptDir 'lib'
Import-Module (Join-Path $ModulesDir 'UI.psm1') -Force
Import-Module (Join-Path $ModulesDir 'Config.psm1') -Force
Import-Module (Join-Path $ModulesDir 'Python.psm1') -Force
Import-Module (Join-Path $ModulesDir 'Process.psm1') -Force
Import-Module (Join-Path $ModulesDir 'Tunnel.psm1') -Force

# ══════════════════════════════════════════════════════════════════════════════
#  Configuration
# ══════════════════════════════════════════════════════════════════════════════

$Config = Get-ScrapitorConfig -AppRoot $AppRoot -RepoRoot $RepoRoot
Initialize-Directories -Config $Config
Set-RuntimeEnvironment -Config $Config

# ══════════════════════════════════════════════════════════════════════════════
#  Main Flow
# ══════════════════════════════════════════════════════════════════════════════

function Main {
    try {
        # Show banner
        Show-Banner
        
        # ── Python Setup ──────────────────────────────────────────────────────
        $python = Find-UsablePython -VenvPython $Config.VenvPython
        
        if (-not $python) {
            Show-ErrorBox -Title "Python Not Found" -Details @(
                "Python 3 is required but was not found.",
                "",
                "Download: https://www.python.org/downloads/",
                "Enable 'Add python.exe to PATH' during setup."
            ) -CountdownSeconds 30
            return 1
        }
        
        Write-Status -Message "Python $($python.Version) found" -Type Success
        
        # Create venv if needed
        $venvCreated = $false
        if (-not (Test-VenvExists -VenvPath $Config.VenvPath)) {
            Write-Spinner -Message "Creating virtual environment..."
            try {
                $null = New-PythonVenv -VenvPath $Config.VenvPath -PythonPath $python.Path
                Clear-SpinnerLine
                Write-Status -Message "Virtual environment created" -Type Success
                $venvCreated = $true
            }
            catch {
                Clear-SpinnerLine
                Show-ErrorBox -Title "Venv Creation Failed" -Details @(
                    "Could not create virtual environment.",
                    "",
                    $_.Exception.Message
                ) -CountdownSeconds 15
                return 1
            }
        }
        
        # Install dependencies
        $requirementsPath = Join-Path $AppRoot 'requirements.txt'
        Write-Spinner -Message "Checking dependencies..."
        $depResult = Install-PythonDependencies `
            -PythonExe $Config.VenvPython `
            -RequirementsPath $requirementsPath `
            -UpgradePip:$venvCreated
        Clear-SpinnerLine
        
        if (-not $depResult.Success) {
            Show-ErrorBox -Title "Dependency Installation Failed" -Details @(
                "Could not install Python packages.",
                "",
                $depResult.Error
            ) -CountdownSeconds 15
            return 1
        }
        
        if ($depResult.InstalledPackages -gt 0) {
            Write-Status -Message "Installed $($depResult.InstalledPackages) packages" -Type Success
        }
        else {
            Write-Status -Message "Dependencies up to date" -Type Success
        }
        
        # ── Cloudflared Setup ─────────────────────────────────────────────────
        $cloudflared = Find-Cloudflared -ScriptDir $ScriptDir
        
        if (-not $cloudflared) {
            if ($Config.AutoInstall) {
                Write-Spinner -Message "Installing cloudflared..."
                $installResult = Install-Cloudflared -TargetDir $ScriptDir -Silent
                Clear-SpinnerLine
                
                if ($installResult.Success) {
                    Write-Status -Message "Cloudflared installed via $($installResult.Method)" -Type Success
                    $cloudflared = @{ Path = $installResult.Path; Source = $installResult.Method }
                }
                else {
                    Show-ErrorBox -Title "Cloudflared Installation Failed" -Details @(
                        "Could not install cloudflared automatically.",
                        "",
                        "Manual install options:",
                        "  winget install Cloudflare.cloudflared",
                        "  https://github.com/cloudflare/cloudflared/releases"
                    ) -CountdownSeconds 20
                    return 1
                }
            }
            else {
                Show-ErrorBox -Title "Cloudflared Not Found" -Details @(
                    "cloudflared is required but not installed.",
                    "",
                    "Install with: winget install Cloudflare.cloudflared"
                ) -CountdownSeconds 15
                return 1
            }
        }
        else {
            Write-Status -Message "Cloudflared ready" -Type Success
        }
        
        # ── Frontend Build ────────────────────────────────────────────────────
        $spaIndex = Join-Path $Config.SpaDistDir 'index.html'
        $frontendSrc = Join-Path $Config.FrontendDir 'src'
        $needsBuild = $false
        
        if (-not (Test-Path $spaIndex)) {
            $needsBuild = $true
        }
        elseif (Test-Path $frontendSrc) {
            $newestSrc = Get-ChildItem -Path $frontendSrc -Recurse -File | 
                Sort-Object LastWriteTime -Descending | 
                Select-Object -First 1
            if ($newestSrc -and $newestSrc.LastWriteTime -gt (Get-Item $spaIndex).LastWriteTime) {
                $needsBuild = $true
            }
        }
        
        if ($needsBuild -and (Get-Command npm -ErrorAction SilentlyContinue)) {
            $nodeModules = Join-Path $Config.FrontendDir 'node_modules'
            Push-Location $Config.FrontendDir
            try {
                if (-not (Test-Path $nodeModules)) {
                    Write-Spinner -Message "Installing frontend dependencies..."
                    $null = npm install --silent 2>$null
                    Clear-SpinnerLine
                }
                
                Write-Spinner -Message "Building frontend..."
                $null = npm run build 2>$null
                Clear-SpinnerLine
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Status -Message "Frontend built" -Type Success
                }
            }
            finally {
                Pop-Location
            }
        }
        
        # ── Stop Stale Processes ──────────────────────────────────────────────
        $null = Stop-StaleProcesses `
            -Port $Config.Port `
            -VenvPython $Config.VenvPython `
            -VenvPythonW $Config.VenvPythonW `
            -PidFile $Config.PidFile

        $requestedPort = $Config.Port
        $portSelection = Resolve-AvailablePort -PreferredPort $requestedPort
        if (-not $portSelection.Success) {
            Show-ErrorBox -Title "Port Selection Failed" -Details @(
                "Could not find an available TCP port to start Scrapitor.",
                "",
                $portSelection.Error
            ) -CountdownSeconds 20
            return 1
        }

        if ($portSelection.WasFallback) {
            $Config.Port = $portSelection.Port
            Set-RuntimeEnvironment -Config $Config

            Write-Status -Message "Port $requestedPort in use, using :$($Config.Port)" -Type Warning
        }
        
        # ── Start Flask ───────────────────────────────────────────────────────
        Write-Section -Title "Starting Services"
        
        $flaskOut = Join-Path $Config.LogsDir 'flask.stdout.log'
        $flaskErr = Join-Path $Config.LogsDir 'flask.stderr.log'
        
        $flaskProcess = Start-ManagedProcess `
            -Name 'flask' `
            -FilePath $Config.VenvPython `
            -Arguments @('-m', 'app.server') `
            -LogOut $flaskOut `
            -LogErr $flaskErr `
            -AttachToConsole:$Config.AttachConsole
        
        # Wait for health with spinner
        $healthOk = $false
        $healthStart = Get-Date
        while (-not $healthOk -and ((Get-Date) - $healthStart).TotalSeconds -lt $Config.HealthTimeout) {
            Write-Spinner -Message "Flask starting on port $($Config.Port)..."
            Start-Sleep -Milliseconds 300
            
            if ($flaskProcess.HasExited) {
                Clear-SpinnerLine
                $flaskLogs = Get-LogContent -Path $flaskErr -TailLines 10
                Show-ErrorBox -Title "Flask Failed to Start" -Details @(
                    "The server exited unexpectedly.",
                    "",
                    "Check logs: $flaskErr"
                ) -CountdownSeconds 15
                return 1
            }
            
            $healthResult = Wait-ForHealth -Port $Config.Port -TimeoutSeconds 1 -Process $flaskProcess
            $healthOk = $healthResult.Success
        }
        Clear-SpinnerLine
        
        if (-not $healthOk) {
            $portConflicts = @(Get-PortListeners -Port $Config.Port -ExcludeProcessIds @($flaskProcess.Id))
            $flaskLogs = Get-LogContent -Path $flaskErr -TailLines 10
            $details = @(
                "Server did not respond within $($Config.HealthTimeout) seconds.",
                "",
                "Port $($Config.Port) may be in use."
            )

            foreach ($listener in $portConflicts | Select-Object -First 3) {
                $command = if ($listener.CommandLine) { $listener.CommandLine } elseif ($listener.ExecutablePath) { $listener.ExecutablePath } else { $listener.Name }
                $details += "[$($listener.LocalAddress):$($listener.LocalPort)] PID $($listener.ProcessId) - $command"
            }

            Show-ErrorBox -Title "Flask Health Check Failed" -Details $details -CountdownSeconds 15
            Stop-AllManagedProcesses
            return 1
        }
        
        Write-Status -Message "Flask healthy on :$($Config.Port)" -Type Success
        
        # ── Start Tunnel ──────────────────────────────────────────────────────
        $tunnelOut = Join-Path $Config.LogsDir 'cloudflared.stdout.log'
        $tunnelErr = Join-Path $Config.LogsDir 'cloudflared.stderr.log'
        $cfArgs = Get-CloudflaredArgs -Port $Config.Port -CustomFlags $env:CLOUDFLARED_FLAGS
        
        $maxAttempts = 2
        $tunnelUrl = $null
        
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            if ($attempt -gt 1) {
                Write-Subtle -Message "Retrying tunnel (attempt $attempt/$maxAttempts)..."
            }
            
            $cfProcess = Start-ManagedProcess `
                -Name 'cloudflared' `
                -FilePath $cloudflared.Path `
                -Arguments $cfArgs `
                -LogOut $tunnelOut `
                -LogErr $tunnelErr `
                -AttachToConsole:$Config.AttachConsole
            
            # Wait for URL with spinner
            $urlStart = Get-Date
            while (((Get-Date) - $urlStart).TotalSeconds -lt $Config.TunnelTimeout) {
                $elapsed = [math]::Round(((Get-Date) - $urlStart).TotalSeconds)
                Write-Spinner -Message "Establishing tunnel... ${elapsed}s"
                Start-Sleep -Milliseconds 200
                
                if ($cfProcess.HasExited) {
                    break
                }
                
                $urlResult = Wait-ForTunnelUrl -LogOut $tunnelOut -LogErr $tunnelErr -TimeoutSeconds 1 -Process $cfProcess
                if ($urlResult.Success) {
                    $tunnelUrl = $urlResult.Url
                    break
                }
            }
            Clear-SpinnerLine
            
            if ($tunnelUrl) {
                break
            }
            
            # Clean up failed attempt
            Stop-ManagedProcess -Name 'cloudflared' -GracePeriodSeconds 1
        }
        
        if (-not $tunnelUrl) {
            Show-ErrorBox -Title "Tunnel Failed" -Details @(
                "Could not establish Cloudflare tunnel.",
                "",
                "Check your internet connection.",
                "Logs: $tunnelErr"
            ) -CountdownSeconds 15
            Stop-AllManagedProcesses
            return 1
        }
        
        Write-Status -Message "Tunnel ready" -Type Success
        
        # ── Success! ──────────────────────────────────────────────────────────
        Save-TunnelUrl -Path $Config.TunnelUrlFile -Url $tunnelUrl | Out-Null
        Save-PidFile -Path $Config.PidFile -Pids @($flaskProcess.Id, $cfProcess.Id) | Out-Null
        
        Show-UrlBox -TunnelUrl $tunnelUrl -Port $Config.Port
        Show-QuickHelp -Port $Config.Port
        
        # ── Main Loop ─────────────────────────────────────────────────────────
        $exitReason = Wait-ForQuitKey -ShowLiveStatus -OnTick {
            $flaskOk = Test-ManagedProcessRunning -Name 'flask'
            $tunnelOk = Test-ManagedProcessRunning -Name 'cloudflared'
            
            if (-not $flaskOk) {
                Write-Host ""
                Write-Status -Message "Flask process died unexpectedly" -Type Error
                return 'exit'
            }
            if (-not $tunnelOk) {
                Write-Host ""
                Write-Status -Message "Cloudflared process died unexpectedly" -Type Error
                return 'exit'
            }
            return @{ FlaskOk = $flaskOk; TunnelOk = $tunnelOk }
        }
        
        return 0
    }
    catch {
        Show-ErrorBox -Title "Unexpected Error" -Details @(
            $_.Exception.Message,
            "",
            "Location: $($_.InvocationInfo.PositionMessage)"
        ) -CountdownSeconds 15
        return 1
    }
    finally {
        # Cleanup
        Write-Host ""
        Write-Subtle -Message "Shutting down..."
        Stop-AllManagedProcesses -GracePeriodSeconds 3
        Remove-PidFile -Path $Config.PidFile
        if (Test-Path $Config.TunnelUrlFile) {
            Remove-Item $Config.TunnelUrlFile -Force -ErrorAction SilentlyContinue
        }
        Write-Status -Message "Stopped" -Type Success
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  Entry Point
# ══════════════════════════════════════════════════════════════════════════════

$exitCode = Main
exit $exitCode
