@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

:: Scrapitor launcher bootstrap.
:: Keep this file ASCII-only; the PowerShell UI owns the styled output.

:: Silent git update (if available)
where git >nul 2>nul && if exist ".git" (
    git fetch --all --tags --prune >nul 2>nul
    git pull --rebase --autostash >nul 2>nul
)

:: Find PowerShell 7
set "PS="
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PS=%ProgramFiles%\PowerShell\7\pwsh.exe"
) else if exist "%ProgramFiles%\PowerShell\7-preview\pwsh.exe" (
    set "PS=%ProgramFiles%\PowerShell\7-preview\pwsh.exe"
) else (
    where pwsh.exe >nul 2>nul && set "PS=pwsh.exe"
)

if not defined PS goto :no_pwsh

:: Launch Scrapitor
start "" "%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\scripts\run_proxy.ps1"
exit /b 0

:no_pwsh
cls
echo.
echo   ============================================================
echo.
echo     PowerShell 7 is required but was not found.
echo.
echo     Install it with:
echo       winget install Microsoft.PowerShell
echo.
echo     Then re-run this script.
echo.
echo   ============================================================
echo.
pause
exit /b 1
