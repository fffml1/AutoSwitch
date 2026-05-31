# AutoSwitch

AutoSwitch is a lightweight Windows IME auto-switcher built with AutoHotkey v2. It watches the active window and switches development tools to English input while returning other apps to Chinese input.

The current version uses Windows IME APIs for direct state control and keeps a Shift-key fallback for apps where the IME API is unavailable.

## Features

- Switches selected processes, such as Windows Terminal and VS Code, to English automatically.
- Returns unmatched apps to Chinese when rules are configured.
- Uses `SetWinEventHook` for fast foreground-window detection, with timer polling as a fallback.
- Uses `IMC_GETCONVERSIONMODE` and `IMC_SETCONVERSIONMODE` instead of blind key toggles.
- Respects manual IME changes inside the same window after the initial automatic switch.
- Supports process-name rules and optional window-title rules.
- Supports optional wildcard matching with `*` and `?`.
- Provides a tray menu for status, pause/resume, settings, config reload, and log access.
- Keeps a rotating `AutoSwitch.log` with recent switch events.

## Requirements

- Windows
- [AutoHotkey v2](https://www.autohotkey.com/)
- A Chinese IME that responds to the Windows IME conversion-mode APIs

## Quick Start

1. Install AutoHotkey v2.
2. Download or clone this repository.
3. Double-click `AutoSwitch.ahk`.
4. Use the tray icon to open **Settings...** or reload the config.

To start AutoSwitch automatically after login, run:

```bat
startup.bat
```

The startup script creates a shortcut in the current user's Windows Startup folder.

## Configuration

AutoSwitch reads rules from `AutoSwitch.ini`.

```ini
[EN]
list=WindowsTerminal.exe|powershell.exe|pwsh.exe|Code.exe|idea64.exe

[ZH]
; list=notepad.exe

[EN_Title]
; list=

[ZH_Title]
; list=

[Settings]
poll_interval=300
cooldown=500
use_wildcard=0
```

### Rule Sections

| Section | Purpose |
| --- | --- |
| `[EN]` | Process names that should switch to English. |
| `[ZH]` | Process names that should force Chinese. |
| `[EN_Title]` | Window-title patterns that should switch to English. |
| `[ZH_Title]` | Window-title patterns that should force Chinese. |
| `[Settings]` | Runtime settings. |

Lists are pipe-delimited. For example:

```ini
list=WindowsTerminal.exe|Code.exe|idea64.exe
```

When `use_wildcard=1`, rules may use:

- `*` to match any number of characters
- `?` to match one character

Example:

```ini
list=*term*.exe|Code.exe
```

## Rule Priority

Rules are evaluated in this order:

1. English title rules
2. Chinese title rules
3. English process rules
4. Chinese process rules
5. Default Chinese mode when any process rule exists but nothing matches

AutoSwitch only applies the automatic switch when focus moves to a different window or process. If you manually change IME mode while staying in the same window, AutoSwitch leaves that manual choice alone until you switch away and back.

## Tray Menu

| Menu Item | Description |
| --- | --- |
| Status | Shows the active process, title, IME mode, matched rule, and pause state. |
| Pause / Resume | Temporarily disables or enables automatic switching. |
| Settings... | Opens the GUI rule editor. |
| Open Log File | Opens `AutoSwitch.log`. |
| Open Config File | Opens `AutoSwitch.ini`. |
| Reload Config | Reloads rules without restarting the script. |
| Exit AutoSwitch | Stops the script. |

## Logs

Runtime events are written to `AutoSwitch.log`.

Example:

```text
[2026-05-31 22:15:03] INFO ======== AutoSwitch v2.0 ========
[2026-05-31 22:15:03] INFO WinEventHook installed for foreground changes
[2026-05-31 22:15:05] INFO EN <- WindowsTerminal.exe
[2026-05-31 22:15:10] INFO ZH <- chrome.exe
```

The log is rotated automatically and keeps the latest 500 lines.

## Troubleshooting

### The IME does not switch

- Confirm that AutoHotkey v2 is installed.
- Check whether AutoSwitch is paused from the tray menu.
- Open `AutoSwitch.log` and confirm that the target process is detected.
- Confirm the process name in Task Manager matches the rule in `AutoSwitch.ini`.

### Windows Terminal switches too slowly or not every time

AutoSwitch delays focus handling briefly so Windows Terminal can finish attaching its IME context. If your system still misses switches, try increasing the delay in `AutoSwitch.ahk`:

```ahk
SetTimer(this.focusTimer, -30)
```

For example, change `-30` to `-50`.

### I manually switch to Chinese in the terminal and it stays Chinese

That is intentional. AutoSwitch respects manual IME changes inside the same window. Switch away and back to the terminal to apply the automatic English rule again.

## Project Files

| File | Description |
| --- | --- |
| `AutoSwitch.ahk` | Main AutoHotkey v2 script. |
| `AutoSwitch.ini` | Rule and runtime configuration. |
| `startup.bat` | Creates a Windows Startup shortcut. |
| `README.md` | Project documentation. |

## License

No license has been specified yet.
