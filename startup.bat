@echo off
:: AutoSwitch — Register to Windows Startup
:: Right-click → Run as Administrator if prompted
:: Creates a shortcut in the current user's Startup folder

set "SCRIPT_DIR=%~dp0"
set "AHK_PATH=%SCRIPT_DIR%AutoSwitch.ahk"
set "STARTUP_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "SHORTCUT=%STARTUP_FOLDER%\AutoSwitch.lnk"

if not exist "%AHK_PATH%" (
    echo [ERROR] AutoSwitch.ahk not found at: %AHK_PATH%
    pause
    exit /b 1
)

echo Creating AutoSwitch startup shortcut...
echo   From: %AHK_PATH%
echo   To:   %SHORTCUT%

powershell -Command ^
    "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%SHORTCUT%'); $s.TargetPath = '%AHK_PATH%'; $s.WorkingDirectory = '%SCRIPT_DIR%'; $s.Save()"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [OK] AutoSwitch will now start automatically when you log in.
    echo.
    echo To remove: delete the shortcut from:
    echo   %STARTUP_FOLDER%
) else (
    echo [ERROR] Failed to create shortcut. Try running as Administrator.
)

pause
