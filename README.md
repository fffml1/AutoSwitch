# AutoSwitch

AutoSwitch 是一个基于 AutoHotkey v2 的 Windows 输入法自动切换工具。它会监听当前活动窗口，在终端、编辑器、IDE 等开发工具中自动切换到英文输入，在其他应用中恢复中文输入。

当前版本使用 Windows IME API 直接查询和设置输入法状态，并保留 Shift 按键切换作为兼容性回退。

## 功能特性

- 自动将 Windows Terminal、VS Code、IDE 等指定进程切换到英文输入。
- 当配置了规则且当前应用未命中规则时，默认切回中文输入。
- 使用 `SetWinEventHook` 监听前台窗口变化，响应更快；同时保留定时轮询作为回退。
- 使用 `IMC_GETCONVERSIONMODE` 和 `IMC_SETCONVERSIONMODE` 控制 IME 状态，不依赖盲目模拟按键。
- 进入窗口时自动切换，但在同一个窗口内尊重用户手动切换的输入法状态。
- 支持按进程名匹配规则。
- 支持按窗口标题匹配规则。
- 可选支持 `*` 和 `?` 通配符匹配。
- 提供托盘菜单，可查看状态、暂停/恢复、打开设置、重载配置和查看日志。
- 自动写入并轮转 `AutoSwitch.log`，保留最近 500 行日志。

## 环境要求

- Windows
- [AutoHotkey v2](https://www.autohotkey.com/)
- 支持 Windows IME conversion mode API 的中文输入法

## 快速开始

1. 安装 AutoHotkey v2。
2. 下载或克隆本仓库。
3. 双击运行 `AutoSwitch.ahk`。
4. 通过托盘图标打开 **Settings...** 修改规则，或选择 **Reload Config** 重载配置。

如需开机自启动，运行：

```bat
startup.bat
```

该脚本会在当前用户的 Windows 启动目录中创建 `AutoSwitch.ahk` 的快捷方式。

## 配置说明

AutoSwitch 从 `AutoSwitch.ini` 读取规则。

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

### 配置分区

| 分区 | 说明 |
| --- | --- |
| `[EN]` | 命中后切换到英文输入的进程名列表。 |
| `[ZH]` | 命中后强制切换到中文输入的进程名列表。 |
| `[EN_Title]` | 命中后切换到英文输入的窗口标题规则。 |
| `[ZH_Title]` | 命中后强制切换到中文输入的窗口标题规则。 |
| `[Settings]` | 运行参数。 |

列表使用竖线 `|` 分隔：

```ini
list=WindowsTerminal.exe|Code.exe|idea64.exe
```

当 `use_wildcard=1` 时，规则支持通配符：

- `*` 匹配任意数量字符
- `?` 匹配单个字符

示例：

```ini
list=*term*.exe|Code.exe
```

## 规则优先级

规则按以下顺序匹配：

1. 英文窗口标题规则
2. 中文窗口标题规则
3. 英文进程名规则
4. 中文进程名规则
5. 如果配置了任意进程规则但当前窗口未命中，则默认切回中文

AutoSwitch 只会在焦点切换到不同窗口或进程时执行自动切换。进入同一个窗口后，如果你手动切换输入法，AutoSwitch 会保留你的手动选择；切换到其他窗口再切回来时，才会重新应用自动规则。

## 托盘菜单

| 菜单项 | 说明 |
| --- | --- |
| Status | 显示当前进程、窗口标题、输入法状态、命中规则和暂停状态。 |
| Pause / Resume | 暂停或恢复自动切换。 |
| Settings... | 打开图形化规则编辑窗口。 |
| Open Log File | 打开 `AutoSwitch.log`。 |
| Open Config File | 打开 `AutoSwitch.ini`。 |
| Reload Config | 无需重启脚本，重新加载配置。 |
| Exit AutoSwitch | 退出脚本。 |

## 日志

运行事件会写入 `AutoSwitch.log`。

示例：

```text
[2026-05-31 22:15:03] INFO ======== AutoSwitch v2.0 ========
[2026-05-31 22:15:03] INFO WinEventHook installed for foreground changes
[2026-05-31 22:15:05] INFO EN <- WindowsTerminal.exe
[2026-05-31 22:15:10] INFO ZH <- chrome.exe
```

日志会自动轮转，仅保留最近 500 行。

## 常见问题

### 输入法没有切换

- 确认已安装 AutoHotkey v2。
- 检查托盘菜单中 AutoSwitch 是否处于暂停状态。
- 打开 `AutoSwitch.log`，确认目标进程是否被检测到。
- 在任务管理器中确认进程名是否和 `AutoSwitch.ini` 中的规则一致。

### Windows Terminal 切换慢或偶尔不切换

AutoSwitch 会在前台窗口变化后短暂延迟处理，让 Windows Terminal 有时间完成 IME 上下文附加。如果你的系统仍然偶发漏切，可以在 `AutoSwitch.ahk` 中适当增大延迟：

```ahk
SetTimer(this.focusTimer, -30)
```

例如将 `-30` 改为 `-50`。

### 在终端里手动切到中文后，为什么不会立刻切回英文？

这是预期行为。AutoSwitch 会尊重同一窗口内的手动输入法切换。切换到其他窗口再回到终端时，英文规则会再次生效。

## 项目文件

| 文件 | 说明 |
| --- | --- |
| `AutoSwitch.ahk` | AutoHotkey v2 主脚本。 |
| `AutoSwitch.ini` | 输入法切换规则和运行配置。 |
| `startup.bat` | 创建 Windows 开机启动快捷方式。 |
| `README.md` | 项目说明文档。 |

## 许可证

暂未指定许可证。
