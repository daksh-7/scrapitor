#Requires -Version 7.0
Set-StrictMode -Version Latest

# ══════════════════════════════════════════════════════════════════════════════
#  UI.psm1 - Terminal UI components for Scrapitor
# ══════════════════════════════════════════════════════════════════════════════

# ── Terminal Capabilities ────────────────────────────────────────────────────
$script:Capabilities = @{
    Unicode   = $false
    Width     = 80
    Initialized = $false
}

function Initialize-TerminalCapabilities {
    [CmdletBinding()]
    param()
    
    if ($script:Capabilities.Initialized) { return }
    
    # Detect Unicode support (Windows Terminal, ConEmu, VS Code, modern terminals)
    $script:Capabilities.Unicode = (
        $env:WT_SESSION -or                          # Windows Terminal
        $env:ConEmuANSI -eq 'ON' -or                 # ConEmu
        $env:TERM_PROGRAM -eq 'vscode' -or           # VS Code integrated terminal
        $env:TERMINAL_EMULATOR -match 'JetBrains' -or # JetBrains IDEs
        $env:ALACRITTY_WINDOW_ID -or                 # Alacritty
        $env:KITTY_WINDOW_ID                         # Kitty
    )
    
    # Get terminal width
    try { 
        $script:Capabilities.Width = [Math]::Max(60, [Console]::WindowWidth)
    } catch {
        $script:Capabilities.Width = 80
    }
    
    $script:Capabilities.Initialized = $true
    
    # Initialize icons based on capabilities
    Initialize-Icons
}

function Initialize-Icons {
    [CmdletBinding()]
    param()
    
    if ($script:Capabilities.Unicode) {
        $script:Icons = @{
            Success  = [string][char]0x2713  # ✓
            Error    = [string][char]0x2717  # ✗
            Warning  = [string][char]0x25C6  # ◆
            Info     = [string][char]0x25CB  # ○
            Pending  = [string][char]0x2026  # …
            Arrow    = [string][char]0x25B6  # ▶
            Bullet   = [string][char]0x2022  # •
        }
        $script:SpinnerFrames = @(
            [string][char]0x280B, [string][char]0x2819, [string][char]0x2839, [string][char]0x2838,
            [string][char]0x283C, [string][char]0x2834, [string][char]0x2826, [string][char]0x2827,
            [string][char]0x2807, [string][char]0x280F  # ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏
        )
        $script:BoxChars = @{
            TopLeft     = [string][char]0x250C  # ┌
            TopRight    = [string][char]0x2510  # ┐
            BottomLeft  = [string][char]0x2514  # └
            BottomRight = [string][char]0x2518  # ┘
            Horizontal  = [string][char]0x2500  # ─
            Vertical    = [string][char]0x2502  # │
            TeeLeft     = [string][char]0x251C  # ├
            TeeRight    = [string][char]0x2524  # ┤
            DoubleLine  = [string][char]0x2550  # ═
        }
    } else {
        $script:Icons = @{
            Success  = '+'
            Error    = 'x'
            Warning  = '!'
            Info     = 'o'
            Pending  = '.'
            Arrow    = '>'
            Bullet   = '*'
        }
        $script:SpinnerFrames = @('|', '/', '-', '\')
        $script:BoxChars = @{
            TopLeft     = '+'
            TopRight    = '+'
            BottomLeft  = '+'
            BottomRight = '+'
            Horizontal  = '-'
            Vertical    = '|'
            TeeLeft     = '+'
            TeeRight    = '+'
            DoubleLine  = '='
        }
    }
}

# ── Layout Constants ─────────────────────────────────────────────────────────
$script:Layout = @{
    MaxWidth    = 78
    Indent      = 2
    SpinnerPad  = 68
    BoxMinWidth = 50
}

# ── Theme ─────────────────────────────────────────────────────────────────────
$script:Theme = @{
    Primary   = 'Cyan'
    Success   = 'Green'
    Warning   = 'Yellow'
    Error     = 'Red'
    Muted     = 'DarkGray'
    Accent    = 'Magenta'
}

# ── ASCII Art Banner ──────────────────────────────────────────────────────────
$script:Banner = @'

███████╗ ██████╗██████╗  █████╗ ██████╗ ██╗████████╗ ██████╗ ██████╗ 
██╔════╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██║╚══██╔══╝██╔═══██╗██╔══██╗
███████╗██║     ██████╔╝███████║██████╔╝██║   ██║   ██║   ██║██████╔╝
╚════██║██║     ██╔══██╗██╔══██║██╔═══╝ ██║   ██║   ██║   ██║██╔══██╗
███████║╚██████╗██║  ██║██║  ██║██║     ██║   ██║   ╚██████╔╝██║  ██║
╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝

'@

$script:BannerCompact = @'
 ___  ___ _ __ __ _ _ __ (_) |_ ___  _ __ 
/ __|/ __| '__/ _` | '_ \| | __/ _ \| '__|
\__ \ (__| | | (_| | |_) | | || (_) | |   
|___/\___|_|  \__,_| .__/|_|\__\___/|_|   
                   |_|                    
'@

# ── Spinner State ────────────────────────────────────────────────────────────
$script:SpinnerIndex = 0

# ── Startup Time (for live status) ───────────────────────────────────────────
$script:StartupTime = $null

# ── Functions ─────────────────────────────────────────────────────────────────

function Show-Banner {
    [CmdletBinding()]
    param(
        [switch]$Compact
    )
    
    # Initialize capabilities on first UI call
    Initialize-TerminalCapabilities
    $script:StartupTime = Get-Date
    
    try { Clear-Host } catch { }
    
    # Select banner based on terminal width
    $art = if ($Compact -or $script:Capabilities.Width -lt 60) {
        $script:BannerCompact
    } else {
        $script:Banner
    }
    
    Write-Host $art -ForegroundColor $script:Theme.Primary
    Write-Host ""
}

function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Success', 'Error', 'Warning', 'Info', 'Pending')]
        [string]$Type = 'Info',
        [switch]$NoNewline
    )
    
    # Ensure capabilities are initialized (for icons)
    if (-not $script:Capabilities.Initialized) { Initialize-TerminalCapabilities }
    
    $icon = $script:Icons[$Type]
    $color = switch ($Type) {
        'Success' { $script:Theme.Success }
        'Error'   { $script:Theme.Error }
        'Warning' { $script:Theme.Warning }
        default   { $script:Theme.Muted }
    }
    
    $params = @{
        NoNewline = $NoNewline
    }
    
    $indent = " " * $script:Layout.Indent
    Write-Host "$indent[" -NoNewline
    Write-Host $icon -ForegroundColor $color -NoNewline
    Write-Host "] " -NoNewline
    Write-Host $Message @params
}

function Write-Spinner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )
    
    # Ensure capabilities are initialized
    if (-not $script:Capabilities.Initialized) { Initialize-TerminalCapabilities }
    
    $frame = $script:SpinnerFrames[$script:SpinnerIndex]
    $script:SpinnerIndex = ($script:SpinnerIndex + 1) % $script:SpinnerFrames.Count
    
    $indent = " " * $script:Layout.Indent
    $line = "$indent[$frame] $Message"
    Write-Host "`r$($line.PadRight($script:Layout.SpinnerPad))" -NoNewline -ForegroundColor $script:Theme.Primary
}

function Clear-SpinnerLine {
    $clearWidth = $script:Layout.SpinnerPad + 2
    Write-Host "`r$(' ' * $clearWidth)" -NoNewline
    Write-Host "`r" -NoNewline
}

function Get-LanIPAddress {
    [CmdletBinding()]
    param()

    # Method 1: Socket connect to public IP - most reliable way to find the real LAN IP
    try {
        $socket = [System.Net.Sockets.Socket]::new(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp
        )
        $socket.Connect("8.8.8.8", 53)
        $ip = ($socket.LocalEndPoint -as [System.Net.IPEndPoint]).Address.ToString()
        $socket.Close()
        if ($ip -and $ip -ne '127.0.0.1') { return $ip }
    }
    catch { }

    # Method 2: Find adapter with default gateway (0.0.0.0/0 route)
    try {
        $defaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Where-Object { $_.NextHop -ne '0.0.0.0' } |
            Select-Object -First 1

        if ($defaultRoute) {
            $ip = Get-NetIPAddress -InterfaceIndex $defaultRoute.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty IPAddress
            if ($ip) { return $ip }
        }
    }
    catch { }

    return $null
}

function Show-UrlBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TunnelUrl,
        [Parameter(Mandatory)][int]$Port
    )

    # Ensure capabilities are initialized
    if (-not $script:Capabilities.Initialized) { Initialize-TerminalCapabilities }

    $proxyUrl = "$TunnelUrl/openrouter-cc"
    $localUrl = "http://localhost:$Port"
    $lanIp = Get-LanIPAddress
    $lanUrl = if ($lanIp) { "http://${lanIp}:$Port" } else { $null }

    # Calculate box width based on longest content (no cap - URLs must be fully visible)
    $dashboardLine = "  Dashboard:  $localUrl"
    $lanLine = if ($lanUrl) { "  LAN:        $lanUrl" } else { $null }
    $proxyLine = "  Proxy URL:  $proxyUrl"

    $innerWidth = [Math]::Max($dashboardLine.Length, $proxyLine.Length)
    if ($lanLine) { $innerWidth = [Math]::Max($innerWidth, $lanLine.Length) }
    $innerWidth += 2

    # Box characters
    $tl = $script:BoxChars.TopLeft
    $tr = $script:BoxChars.TopRight
    $bl = $script:BoxChars.BottomLeft
    $br = $script:BoxChars.BottomRight
    $hz = $script:BoxChars.Horizontal
    $vt = $script:BoxChars.Vertical

    $indent = " " * $script:Layout.Indent
    $topBot = $hz * $innerWidth

    Write-Host ""
    # Top border
    Write-Host "$indent$tl$topBot$tr" -ForegroundColor $script:Theme.Muted

    # Dashboard line (localhost)
    Write-Host "$indent$vt" -ForegroundColor $script:Theme.Muted -NoNewline
    Write-Host "  Dashboard:  " -NoNewline
    Write-Host $localUrl -ForegroundColor $script:Theme.Primary -NoNewline
    Write-Host (" " * ($innerWidth - $dashboardLine.Length)) -NoNewline
    Write-Host "$vt" -ForegroundColor $script:Theme.Muted

    # LAN line (if available)
    if ($lanUrl) {
        Write-Host "$indent$vt" -ForegroundColor $script:Theme.Muted -NoNewline
        Write-Host "  LAN:        " -NoNewline
        Write-Host $lanUrl -ForegroundColor $script:Theme.Primary -NoNewline
        Write-Host (" " * ($innerWidth - $lanLine.Length)) -NoNewline
        Write-Host "$vt" -ForegroundColor $script:Theme.Muted
    }

    # Proxy URL line (emphasized)
    Write-Host "$indent$vt" -ForegroundColor $script:Theme.Muted -NoNewline
    Write-Host "  Proxy URL:  " -NoNewline
    Write-Host $proxyUrl -ForegroundColor $script:Theme.Success -NoNewline
    Write-Host (" " * ($innerWidth - $proxyLine.Length)) -NoNewline
    Write-Host "$vt" -ForegroundColor $script:Theme.Muted

    # Bottom border
    Write-Host "$indent$bl$topBot$br" -ForegroundColor $script:Theme.Muted

    # Hint
    Write-Host ""
    Write-Host "$indent  Copy the Proxy URL and paste it into JanitorAI" -ForegroundColor $script:Theme.Muted
    Write-Host ""
}

function Show-ErrorBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [string[]]$Details,
        [int]$CountdownSeconds = 0
    )
    
    # Ensure capabilities are initialized
    if (-not $script:Capabilities.Initialized) { Initialize-TerminalCapabilities }
    
    # Calculate width based on content
    $headerLen = "  $($script:Icons.Error) ERROR: $Title".Length
    $maxDetailLen = 0
    foreach ($line in $Details) {
        if ($line.Length -gt $maxDetailLen) { $maxDetailLen = $line.Length }
    }
    $contentWidth = [Math]::Max($headerLen, $maxDetailLen + 4)
    $boxWidth = [Math]::Min([Math]::Max($contentWidth + 4, $script:Layout.BoxMinWidth), $script:Layout.MaxWidth)
    $innerWidth = $boxWidth - 2
    
    # Box characters
    $tl = $script:BoxChars.TopLeft
    $tr = $script:BoxChars.TopRight
    $bl = $script:BoxChars.BottomLeft
    $br = $script:BoxChars.BottomRight
    $hz = $script:BoxChars.DoubleLine
    $vt = $script:BoxChars.Vertical
    $tL = $script:BoxChars.TeeLeft
    $tR = $script:BoxChars.TeeRight
    $hzThin = $script:BoxChars.Horizontal
    
    $indent = " " * $script:Layout.Indent
    $border = $hz * $innerWidth
    $divider = $hzThin * $innerWidth
    
    Write-Host ""
    Write-Host "$indent$tl$border$tr" -ForegroundColor $script:Theme.Error
    Write-Host "$indent$vt" -NoNewline -ForegroundColor $script:Theme.Error
    Write-Host "  $($script:Icons.Error) ERROR: $Title".PadRight($innerWidth) -NoNewline -ForegroundColor $script:Theme.Error
    Write-Host "$vt" -ForegroundColor $script:Theme.Error
    Write-Host "$indent$tL$divider$tR" -ForegroundColor $script:Theme.Error
    
    foreach ($line in $Details) {
        Write-Host "$indent$vt" -NoNewline -ForegroundColor $script:Theme.Error
        Write-Host "  $line".PadRight($innerWidth) -NoNewline -ForegroundColor $script:Theme.Warning
        Write-Host "$vt" -ForegroundColor $script:Theme.Error
    }
    
    Write-Host "$indent$bl$border$br" -ForegroundColor $script:Theme.Error
    Write-Host ""
    
    if ($CountdownSeconds -gt 0) {
        for ($i = $CountdownSeconds; $i -gt 0; $i--) {
            Write-Host "`r${indent}Closing in $i seconds... (press any key to close now)" -NoNewline -ForegroundColor $script:Theme.Muted
            try {
                if ([Console]::KeyAvailable) {
                    $null = [Console]::ReadKey($true)
                    break
                }
            } catch { }
            Start-Sleep -Seconds 1
        }
        Write-Host ""
    }
}

function Show-QuickHelp {
    [CmdletBinding()]
    param(
        [int]$Port = 5000
    )
    
    # Ensure capabilities are initialized
    if (-not $script:Capabilities.Initialized) { Initialize-TerminalCapabilities }
    
    $indent = " " * $script:Layout.Indent
    $bullet = $script:Icons.Bullet
    
    Write-Host ""
    Write-Host "$indent$bullet " -ForegroundColor $script:Theme.Muted -NoNewline
    Write-Host "Press " -NoNewline
    Write-Host "Q" -ForegroundColor $script:Theme.Accent -NoNewline
    Write-Host " to quit  " -NoNewline
    Write-Host "$bullet " -ForegroundColor $script:Theme.Muted -NoNewline
    Write-Host "Dashboard: " -NoNewline
    Write-Host "http://localhost:$Port" -ForegroundColor $script:Theme.Primary
    Write-Host ""
}

function Test-InteractiveConsole {
    [CmdletBinding()]
    param()
    
    try {
        # Check if we have a real console
        $null = [Console]::WindowWidth
        return $true
    }
    catch {
        return $false
    }
}

function Format-Uptime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TimeSpan]$Duration
    )
    
    if ($Duration.TotalHours -ge 1) {
        return "{0}h {1}m" -f [int]$Duration.TotalHours, $Duration.Minutes
    } elseif ($Duration.TotalMinutes -ge 1) {
        return "{0}m {1}s" -f [int]$Duration.TotalMinutes, $Duration.Seconds
    } else {
        return "{0}s" -f [int]$Duration.TotalSeconds
    }
}

function Write-LiveStatus {
    [CmdletBinding()]
    param(
        [bool]$FlaskOk = $true,
        [bool]$TunnelOk = $true
    )
    
    # Ensure capabilities are initialized
    if (-not $script:Capabilities.Initialized) { Initialize-TerminalCapabilities }
    
    $indent = " " * $script:Layout.Indent
    $uptime = if ($script:StartupTime) {
        Format-Uptime -Duration ((Get-Date) - $script:StartupTime)
    } else { "0s" }
    
    $flaskStatus = if ($FlaskOk) { 
        "$($script:Icons.Success)" 
    } else { 
        "$($script:Icons.Error)" 
    }
    $tunnelStatus = if ($TunnelOk) { 
        "$($script:Icons.Success)" 
    } else { 
        "$($script:Icons.Error)" 
    }
    
    $statusLine = "${indent}Running $uptime | Flask: $flaskStatus | Tunnel: $tunnelStatus | Press Q to quit"
    Write-Host "`r$($statusLine.PadRight($script:Layout.SpinnerPad))" -NoNewline -ForegroundColor $script:Theme.Muted
}

function Wait-ForQuitKey {
    [CmdletBinding()]
    param(
        [scriptblock]$OnTick,
        [int]$TickIntervalMs = 1000,
        [switch]$ShowLiveStatus
    )
    
    $isInteractive = Test-InteractiveConsole
    $lastTick = Get-Date
    $lastStatusUpdate = Get-Date
    $flaskOk = $true
    $tunnelOk = $true
    
    while ($true) {
        # Only check for keypress if we have an interactive console
        if ($isInteractive) {
            try {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') {
                        if ($ShowLiveStatus) { Clear-SpinnerLine }
                        return 'quit'
                    }
                }
            }
            catch {
                # Console became unavailable, switch to non-interactive mode
                $isInteractive = $false
            }
        }
        
        if ($OnTick -and ((Get-Date) - $lastTick).TotalMilliseconds -ge $TickIntervalMs) {
            $result = & $OnTick
            if ($result -eq 'exit') { 
                if ($ShowLiveStatus) { Clear-SpinnerLine }
                return 'exit' 
            }
            # Update status from callback result if it's a hashtable
            if ($result -is [hashtable]) {
                if ($result.ContainsKey('FlaskOk')) { $flaskOk = $result.FlaskOk }
                if ($result.ContainsKey('TunnelOk')) { $tunnelOk = $result.TunnelOk }
            }
            $lastTick = Get-Date
        }
        
        # Update live status every second
        if ($ShowLiveStatus -and ((Get-Date) - $lastStatusUpdate).TotalMilliseconds -ge 1000) {
            Write-LiveStatus -FlaskOk $flaskOk -TunnelOk $tunnelOk
            $lastStatusUpdate = Get-Date
        }
        
        Start-Sleep -Milliseconds 100
    }
}

function Write-Subtle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message
    )
    $indent = " " * $script:Layout.Indent
    Write-Host "$indent$Message" -ForegroundColor $script:Theme.Muted
}

function Write-Section {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title
    )
    
    # Ensure capabilities are initialized
    if (-not $script:Capabilities.Initialized) { Initialize-TerminalCapabilities }
    
    $indent = " " * $script:Layout.Indent
    $hz = $script:BoxChars.Horizontal
    $lineLen = [Math]::Max(10, 50 - $Title.Length)
    
    Write-Host ""
    Write-Host "$indent$hz$hz " -ForegroundColor $script:Theme.Primary -NoNewline
    Write-Host $Title -ForegroundColor $script:Theme.Primary -NoNewline
    Write-Host " $($hz * $lineLen)" -ForegroundColor $script:Theme.Muted
    Write-Host ""
}

# ── Export ────────────────────────────────────────────────────────────────────
Export-ModuleMember -Function @(
    'Initialize-TerminalCapabilities',
    'Show-Banner',
    'Write-Status',
    'Write-Spinner',
    'Clear-SpinnerLine',
    'Show-UrlBox',
    'Show-ErrorBox',
    'Show-QuickHelp',
    'Wait-ForQuitKey',
    'Write-LiveStatus',
    'Format-Uptime',
    'Test-InteractiveConsole',
    'Write-Subtle',
    'Write-Section'
)

