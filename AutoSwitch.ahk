#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
; ==================== AutoSwitch v2.0 ====================
; Auto-switch IME based on active window process name
; Dev tools -> English, other apps -> Chinese
; Uses Windows IME API for direct state query/set; Shift toggle as fallback

; ==================== ImeManager ====================
; Queries and sets IME state via Windows Imm32 API.
; Primary: IMC_GETCONVERSIONMODE / IMC_SETCONVERSIONMODE via SendMessage
; Fallback: Shift key toggle with internal state tracking
; Timeouts prevent SendMessage from blocking the thread on unresponsive windows.

class ImeManager {
    static MODE_ENGLISH := 0
    static MODE_CHINESE := 1025
    static WM_IME_CONTROL := 0x283
    static IMC_GETCONVERSIONMODE := 0x001
    static IMC_SETCONVERSIONMODE := 0x002
    static SEND_TIMEOUT := 200
    static QUERY_TIMEOUT := 50

    fallbackEnglish := false

    ; Sets IME to targetMode (0=EN, 1025=ZH) if not already there.
    ; Returns true if a switch was performed.
    EnsureMode(targetMode) {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        if !hwnd
            return false

        hIMC := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        if !hIMC {
            this._ShiftTo(targetMode)
            return true
        }

        ; Quick pre-check: if already in target mode, skip
        current := SendMessage(
            ImeManager.WM_IME_CONTROL,
            ImeManager.IMC_GETCONVERSIONMODE,
            0,
            ,
            "ahk_id " hIMC,
            , , ,
            ImeManager.QUERY_TIMEOUT
        )

        ; If query succeeded and already in target mode, no action needed
        if current != "" && current = targetMode {
            this.fallbackEnglish := targetMode = ImeManager.MODE_ENGLISH
            return false
        }

        ; Set target mode
        result := SendMessage(
            ImeManager.WM_IME_CONTROL,
            ImeManager.IMC_SETCONVERSIONMODE,
            targetMode,
            ,
            "ahk_id " hIMC,
            , , ,
            ImeManager.SEND_TIMEOUT
        )

        ; If SendMessage timed out, try fire-and-forget PostMessage
        if result = ""
            PostMessage(ImeManager.WM_IME_CONTROL, ImeManager.IMC_SETCONVERSIONMODE,
                         targetMode, , "ahk_id " hIMC)

        ; If both API methods failed, fall back to Shift toggle
        if result != 0 && result != "" {
            this._ShiftTo(targetMode)
        }

        this.fallbackEnglish := targetMode = ImeManager.MODE_ENGLISH
        return true
    }

    SwitchToEnglish() {
        return this.EnsureMode(ImeManager.MODE_ENGLISH)
    }

    SwitchToChinese() {
        return this.EnsureMode(ImeManager.MODE_CHINESE)
    }

    ; Lightweight query for Status display (100ms timeout)
    IsEnglish() {
        return this.IsMode(ImeManager.MODE_ENGLISH)
    }

    IsMode(targetMode) {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        if !hwnd
            return this.fallbackEnglish = (targetMode = ImeManager.MODE_ENGLISH)
        hIMC := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        if !hIMC
            return this.fallbackEnglish = (targetMode = ImeManager.MODE_ENGLISH)
        mode := SendMessage(
            ImeManager.WM_IME_CONTROL,
            ImeManager.IMC_GETCONVERSIONMODE,
            0,
            ,
            "ahk_id " hIMC,
            , , ,
            100
        )
        if mode = ""
            return this.fallbackEnglish = (targetMode = ImeManager.MODE_ENGLISH)
        return mode = targetMode
    }

    _ShiftTo(targetMode) {
        wantEnglish := targetMode = ImeManager.MODE_ENGLISH
        if this.fallbackEnglish != wantEnglish {
            Send "{LShift}"
            this.fallbackEnglish := wantEnglish
        }
    }

    ; Returns the low word of the current keyboard layout HKL.
    GetKeyboardLayout() {
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        if !hwnd
            return 0
        threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", 0, "UInt")
        return DllCall("GetKeyboardLayout", "UInt", threadId, "UInt") & 0xFFFF
    }
}

; ==================== ConfigManager ====================

class ConfigManager {
    iniPath := ""
    enList := []
    zhList := []
    enTitleList := []
    zhTitleList := []
    pollInterval := 300
    cooldownMs := 500
    useWildcard := false

    __New(iniPath) {
        this.iniPath := iniPath
        this.Load()
    }

    Load() {
        if !FileExist(this.iniPath) {
            this.CreateDefault()
            return
        }
        this.enList := this._ReadList("EN", "list")
        this.zhList := this._ReadList("ZH", "list")
        this.enTitleList := this._ReadList("EN_Title", "list")
        this.zhTitleList := this._ReadList("ZH_Title", "list")
        this.pollInterval := Integer(IniRead(this.iniPath, "Settings", "poll_interval", "300"))
        this.cooldownMs := Integer(IniRead(this.iniPath, "Settings", "cooldown", "500"))
        this.useWildcard := Integer(IniRead(this.iniPath, "Settings", "use_wildcard", "0")) = 1
    }

    _ReadList(section, key) {
        raw := IniRead(this.iniPath, section, key, "")
        result := []
        if raw = ""
            return result
        for item in StrSplit(raw, "|") {
            trimmed := Trim(item)
            if trimmed != ""
                result.Push(trimmed)
        }
        return result
    }

    _WriteList(section, key, arr) {
        IniWrite(this._Join(arr, "|"), this.iniPath, section, key)
    }

    _Join(arr, delim) {
        s := ""
        for i, v in arr
            s .= (i > 1 ? delim : "") . v
        return s
    }

    Save() {
        this._WriteList("EN", "list", this.enList)
        this._WriteList("ZH", "list", this.zhList)
        this._WriteList("EN_Title", "list", this.enTitleList)
        this._WriteList("ZH_Title", "list", this.zhTitleList)
        IniWrite(this.pollInterval, this.iniPath, "Settings", "poll_interval")
        IniWrite(this.cooldownMs, this.iniPath, "Settings", "cooldown")
        IniWrite(this.useWildcard ? 1 : 0, this.iniPath, "Settings", "use_wildcard")
    }

    CreateDefault() {
        defaultIni := '
(
[EN]
; Pipe-delimited list of processes that auto-switch to English
list=WindowsTerminal.exe|powershell.exe|pwsh.exe|Code.exe|idea64.exe

[ZH]
; Pipe-delimited list of processes that force Chinese
; list=notepad.exe

[EN_Title]
; Window titles (substring match) that switch to English
; list=

[ZH_Title]
; Window titles (substring match) that force Chinese
; list=

[Settings]
; Polling fallback interval in ms (when event hook unavailable)
poll_interval=300
; Cooldown: minimum ms between switches to prevent flicker
cooldown=500
; Enable wildcard/glob matching for rules (* = any chars)
use_wildcard=0
)'
        FileAppend(defaultIni, this.iniPath)
        this.Load()
    }

    AddRule(section, value) {
        switch section {
        case "EN":   this.enList.Push(value), this._WriteList("EN", "list", this.enList)
        case "ZH":   this.zhList.Push(value), this._WriteList("ZH", "list", this.zhList)
        case "EN_Title": this.enTitleList.Push(value), this._WriteList("EN_Title", "list", this.enTitleList)
        case "ZH_Title": this.zhTitleList.Push(value), this._WriteList("ZH_Title", "list", this.zhTitleList)
        }
    }

    RemoveRule(section, index) {
        switch section {
        case "EN":   this.enList.RemoveAt(index), this._WriteList("EN", "list", this.enList)
        case "ZH":   this.zhList.RemoveAt(index), this._WriteList("ZH", "list", this.zhList)
        case "EN_Title": this.enTitleList.RemoveAt(index), this._WriteList("EN_Title", "list", this.enTitleList)
        case "ZH_Title": this.zhTitleList.RemoveAt(index), this._WriteList("ZH_Title", "list", this.zhTitleList)
        }
    }
}

; ==================== RuleEngine ====================

class RuleEngine {
    config := ""

    __New(configMgr) {
        this.config := configMgr
    }

    ; Returns "EN", "ZH", or "" (no rule matches).
    Match(processName, windowTitle) {
        ; Title-based rules (higher priority)
        if this.config.enTitleList.Length > 0 {
            for pattern in this.config.enTitleList {
                if this._MatchStr(windowTitle, pattern)
                    return "EN"
            }
        }
        if this.config.zhTitleList.Length > 0 {
            for pattern in this.config.zhTitleList {
                if this._MatchStr(windowTitle, pattern)
                    return "ZH"
            }
        }
        ; Process name rules
        for exe in this.config.enList {
            if this._MatchStr(processName, exe)
                return "EN"
        }
        for exe in this.config.zhList {
            if this._MatchStr(processName, exe)
                return "ZH"
        }
        ; Default: if EN list has entries and no ZH match, treat as ZH
        if this.config.enList.Length > 0 || this.config.zhList.Length > 0
            return "ZH"
        return ""
    }

    _MatchStr(haystack, needle) {
        if this.config.useWildcard && (InStr(needle, "*") || InStr(needle, "?"))
            return this._WildcardMatch(haystack, needle)
        return haystack = needle
    }

    _WildcardMatch(str, pattern) {
        ; Convert glob pattern to regex: escape regex chars, * → .*, ? → .
        escaped := ""
        Loop Parse pattern {
            c := A_LoopField
            switch c {
            case "*": escaped .= ".*"
            case "?": escaped .= "."
            case ".", "+", "(", ")", "[", "]", "{", "}", "^", "$", "\", "|":
                escaped .= "\" . c
            default:  escaped .= c
            }
        }
        return RegExMatch(str, "i)^" escaped "$") > 0
    }
}

; ==================== Logger ====================

class Logger {
    path := ""
    maxLines := 500

    __New(path) {
        this.path := path
    }

    Log(level, msg) {
        ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        line := Format("[{1}] {2} {3}`n", ts, level, msg)
        FileAppend(line, this.path)
        this._Rotate()
    }

    _Rotate() {
        if !FileExist(this.path)
            return
        content := FileRead(this.path)
        lines := StrSplit(content, "`n")
        if lines.Length <= this.maxLines + 2
            return
        keep := ""
        start := lines.Length - this.maxLines
        Loop this.maxLines {
            idx := start + A_Index
            if idx <= lines.Length && lines[idx] != ""
                keep .= lines[idx] "`n"
        }
        FileDelete(this.path)
        FileAppend(keep, this.path)
    }
}

; ==================== SettingsGui ====================

class SettingsGui extends Gui {
    mainApp := ""

    __New(mainApp) {
        super.__New("+Resize +MinSize600x400", "AutoSwitch Settings", this)
        this.mainApp := mainApp
        this.OnEvent("Close", "OnClose")
        this.OnEvent("Escape", "OnClose")
        this._Build()
    }

    _Build() {
        this.SetFont("s9", "Segoe UI")
        Tab := this.Add("Tab3", "w580 h340", ["EN Rules", "ZH Rules", "Title Rules", "Settings"])
        this.Tab := Tab

        ; --- EN Rules tab ---
        Tab.UseTab(1)
        this.Add("Text", "xm+10 y+10", "Process names that switch to English:")
        this.EnLV := this.Add("ListView", "xm+10 r12 w540 -Multi", ["#", "Process Name"])
        this.EnLV.ModifyCol(1, "Integer 30")
        this.EnLV.ModifyCol(2, "AutoHdr 500")
        this.EnAdd := this.Add("Edit", "xm+10 w400 vEnAdd")
        this.Add("Button", "x+m w60 Default", "&Add").OnEvent("Click", "OnEnAdd")
        this.Add("Button", "x+m w60", "&Remove").OnEvent("Click", "OnEnRemove")

        ; --- ZH Rules tab ---
        Tab.UseTab(2)
        this.Add("Text", "xm+10 y+10", "Process names that force Chinese:")
        this.ZhLV := this.Add("ListView", "xm+10 r12 w540 -Multi", ["#", "Process Name"])
        this.ZhLV.ModifyCol(1, "Integer 30")
        this.ZhLV.ModifyCol(2, "AutoHdr 500")
        this.ZhAdd := this.Add("Edit", "xm+10 w400 vZhAdd")
        this.Add("Button", "x+m w60", "&Add").OnEvent("Click", "OnZhAdd")
        this.Add("Button", "x+m w60", "&Remove").OnEvent("Click", "OnZhRemove")

        ; --- Title Rules tab ---
        Tab.UseTab(3)
        this.Add("Text", "xm+10 y+10", "Window titles (substring) that switch to English:")
        this.EnTiLV := this.Add("ListView", "xm+10 r5 w540 -Multi", ["#", "Title Pattern"])
        this.EnTiLV.ModifyCol(1, "Integer 30")
        this.EnTiLV.ModifyCol(2, "AutoHdr 500")
        this.EnTiAdd := this.Add("Edit", "xm+10 w400 vEnTiAdd")
        this.Add("Button", "x+m w60", "&Add").OnEvent("Click", "OnEnTiAdd")
        this.Add("Button", "x+m w60", "&Remove").OnEvent("Click", "OnEnTiRemove")
        this.Add("Text", "xm+10 y+5", "Window titles (substring) that force Chinese:")
        this.ZhTiLV := this.Add("ListView", "xm+10 r5 w540 -Multi", ["#", "Title Pattern"])
        this.ZhTiLV.ModifyCol(1, "Integer 30")
        this.ZhTiLV.ModifyCol(2, "AutoHdr 500")
        this.ZhTiAdd := this.Add("Edit", "xm+10 w400 vZhTiAdd")
        this.Add("Button", "x+m w60", "&Add").OnEvent("Click", "OnZhTiAdd")
        this.Add("Button", "x+m w60", "&Remove").OnEvent("Click", "OnZhTiRemove")

        ; --- Settings tab ---
        Tab.UseTab(4)
        this.Add("Text", "xm+10 y+10", "Polling fallback interval (ms):")
        this.PollEdit := this.Add("Edit", "xm+10 w80 Number")
        this.Add("Text", "xm+10 y+5", "Cooldown (ms):")
        this.CoolEdit := this.Add("Edit", "xm+10 w80 Number")
        this.WildCheck := this.Add("Checkbox", "xm+10 y+10", "Enable wildcard matching (*, ?)")
        this.Add("Button", "xm+10 y+20 w100", "&Save").OnEvent("Click", "OnSaveSettings")

        this._RefreshLists()
        this.PollEdit.Value := this.mainApp.config.pollInterval
        this.CoolEdit.Value := this.mainApp.config.cooldownMs
        this.WildCheck.Value := this.mainApp.config.useWildcard
    }

    _RefreshLists() {
        cfg := this.mainApp.config
        this.EnLV.Delete(), this.ZhLV.Delete()
        this.EnTiLV.Delete(), this.ZhTiLV.Delete()
        for i, v in cfg.enList
            this.EnLV.Add(, i, v)
        for i, v in cfg.zhList
            this.ZhLV.Add(, i, v)
        for i, v in cfg.enTitleList
            this.EnTiLV.Add(, i, v)
        for i, v in cfg.zhTitleList
            this.ZhTiLV.Add(, i, v)
        this.EnLV.ModifyCol(), this.ZhLV.ModifyCol()
        this.EnTiLV.ModifyCol(), this.ZhTiLV.ModifyCol()
    }

    OnEnAdd(*) {
        val := Trim(this["EnAdd"].Value)
        if val != "" {
            this.mainApp.config.AddRule("EN", val)
            this["EnAdd"].Value := ""
            this._RefreshLists()
        }
    }

    OnEnRemove(*) {
        row := this.EnLV.GetNext()
        if row {
            this.mainApp.config.RemoveRule("EN", row)
            this._RefreshLists()
        }
    }

    OnZhAdd(*) {
        val := Trim(this["ZhAdd"].Value)
        if val != "" {
            this.mainApp.config.AddRule("ZH", val)
            this["ZhAdd"].Value := ""
            this._RefreshLists()
        }
    }

    OnZhRemove(*) {
        row := this.ZhLV.GetNext()
        if row {
            this.mainApp.config.RemoveRule("ZH", row)
            this._RefreshLists()
        }
    }

    OnEnTiAdd(*) {
        val := Trim(this["EnTiAdd"].Value)
        if val != "" {
            this.mainApp.config.AddRule("EN_Title", val)
            this["EnTiAdd"].Value := ""
            this._RefreshLists()
        }
    }

    OnEnTiRemove(*) {
        row := this.EnTiLV.GetNext()
        if row {
            this.mainApp.config.RemoveRule("EN_Title", row)
            this._RefreshLists()
        }
    }

    OnZhTiAdd(*) {
        val := Trim(this["ZhTiAdd"].Value)
        if val != "" {
            this.mainApp.config.AddRule("ZH_Title", val)
            this["ZhTiAdd"].Value := ""
            this._RefreshLists()
        }
    }

    OnZhTiRemove(*) {
        row := this.ZhTiLV.GetNext()
        if row {
            this.mainApp.config.RemoveRule("ZH_Title", row)
            this._RefreshLists()
        }
    }

    OnSaveSettings(*) {
        cfg := this.mainApp.config
        cfg.pollInterval := Integer(this.PollEdit.Value)
        cfg.cooldownMs := Integer(this.CoolEdit.Value)
        cfg.useWildcard := this.WildCheck.Value = 1
        cfg.Save()
        this.mainApp.ReloadFromConfig()
        this.mainApp.logger.Log("INFO", "Settings saved via GUI")
        MsgBox("Settings saved.", "AutoSwitch", "Iconi")
    }

    OnClose(*) {
        this.Hide()
    }
}

; ==================== WinEventHook Callback ====================
; Standalone function required — ObjBindMethod is incompatible with
; CallbackCreate Fast mode in some AHK v2 builds.

_WinEventProc(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    global _AutoSwitchInstance
    Critical
    DetectHiddenWindows(true)
    try {
        _AutoSwitchInstance.QueueFocusChange(hwnd)
    }
}

; ==================== AutoSwitch ====================

class AutoSwitch {
    logger := ""
    config := ""
    ime := ""
    rules := ""
    gui := ""

    lastProcess := ""
    lastHwnd := 0
    lastTarget := ""
    lastSwitchTime := 0
    isPaused := false
    hWinEventHook := 0
    pendingHwnd := 0
    focusTimer := ""

    __New() {
        global _AutoSwitchInstance
        _AutoSwitchInstance := this

        iniPath := A_ScriptDir "\AutoSwitch.ini"
        logPath := A_ScriptDir "\AutoSwitch.log"

        this.logger := Logger(logPath)
        this.logger.Log("INFO", "======== AutoSwitch v2.0 ========")

        this.config := ConfigManager(iniPath)
        this.ime := ImeManager()
        this.rules := RuleEngine(this.config)
        this.focusTimer := ObjBindMethod(this, "ProcessPendingFocus")

        this.logger.Log("INFO", Format("Config loaded: {1} EN, {2} ZH rules, poll={3}ms, cooldown={4}ms, wildcard={5}",
            this.config.enList.Length, this.config.zhList.Length,
            this.config.pollInterval, this.config.cooldownMs,
            this.config.useWildcard ? "on" : "off"))

        this._SetupTray()
        this._InstallWinEventHook()
        SetTimer(ObjBindMethod(this, "PollCheck"), this.config.pollInterval)
    }

    _InstallWinEventHook() {
        EVENT_SYSTEM_FOREGROUND := 3
        WINEVENT_OUTOFCONTEXT := 0x0
        callback := CallbackCreate(_WinEventProc, "F")
        this.hWinEventHook := DllCall("SetWinEventHook",
            "UInt", EVENT_SYSTEM_FOREGROUND,
            "UInt", EVENT_SYSTEM_FOREGROUND,
            "Ptr", 0,
            "Ptr", callback,
            "UInt", 0,
            "UInt", 0,
            "UInt", WINEVENT_OUTOFCONTEXT,
            "Ptr")
        if this.hWinEventHook
            this.logger.Log("INFO", "WinEventHook installed for foreground changes")
        else
            this.logger.Log("WARN", "WinEventHook failed, using polling only")
    }

    ; Called by _WinEventProc (standalone callback function above)

    QueueFocusChange(hwnd) {
        this.pendingHwnd := hwnd
        ; Let the newly focused window finish attaching its IME context.
        SetTimer(this.focusTimer, -30)
    }

    ProcessPendingFocus(*) {
        hwnd := this.pendingHwnd
        if hwnd && hwnd = DllCall("GetForegroundWindow", "Ptr")
            this._HandleFocusChange(hwnd)
    }

    _HandleFocusChange(hwnd) {
        if this.isPaused
            return

        try {
            processName := WinGetProcessName("ahk_id " hwnd)
        } catch {
            return
        }

        if processName = ""
            return

        ; Auto-switch only when focus moves to a different window/process.
        ; Once the user is inside a window, manual IME changes are respected.
        if processName = this.lastProcess && hwnd = this.lastHwnd
            return

        ; Only fetch window title if title-based rules exist
        cfg := this.config
        winTitle := ""
        if cfg.enTitleList.Length > 0 || cfg.zhTitleList.Length > 0 {
            try {
                winTitle := WinGetTitle("ahk_id " hwnd)
            } catch {
            }
        }

        target := this.rules.Match(processName, winTitle)
        if target = "" {
            this.lastProcess := processName
            this.lastHwnd := hwnd
            this.lastTarget := ""
            return
        }

        targetMode := target = "EN" ? ImeManager.MODE_ENGLISH : ImeManager.MODE_CHINESE
        sameTarget := target = this.lastTarget
        if sameTarget && this.ime.IsMode(targetMode) {
            this.lastProcess := processName
            this.lastHwnd := hwnd
            return
        }

        success := false
        if target = "EN"
            success := this.ime.SwitchToEnglish()
        else
            success := this.ime.SwitchToChinese()

        if success {
            this.lastSwitchTime := A_TickCount
            this.logger.Log("INFO", target " <- " processName)
        }
        this.lastProcess := processName
        this.lastHwnd := hwnd
        this.lastTarget := target
    }

    PollCheck() {
        if this.isPaused
            return
        hwnd := DllCall("GetForegroundWindow", "Ptr")
        if !hwnd
            return
        try {
            this._HandleFocusChange(hwnd)
        } catch {
            return
        }
    }

    ReloadFromConfig() {
        this.lastProcess := ""
        this.lastHwnd := 0
        this.lastTarget := ""
        this.config.Load()
        SetTimer(ObjBindMethod(this, "PollCheck"), this.config.pollInterval)
    }

    ; ==================== Tray ====================

    _SetupTray() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("&Status", ObjBindMethod(this, "ShowStatus"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("&Pause / Resume", ObjBindMethod(this, "TogglePause"))
        A_TrayMenu.Default := "&Pause / Resume"
        A_TrayMenu.Add()
        A_TrayMenu.Add("&Settings...", ObjBindMethod(this, "ShowSettings"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Open &Log File", ObjBindMethod(this, "ViewLog"))
        A_TrayMenu.Add("Open &Config File", ObjBindMethod(this, "OpenConfig"))
        A_TrayMenu.Add("&Reload Config", ObjBindMethod(this, "ReloadConfigHandler"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("E&xit AutoSwitch", ObjBindMethod(this, "ExitHandler"))
        this._UpdateTrayTip()
    }

    _UpdateTrayTip() {
        A_IconTip := this.isPaused ? "AutoSwitch [PAUSED]" : "AutoSwitch [Running]"
    }

    ShowStatus(*) {
        try {
            proc := WinGetProcessName("A")
        } catch {
            proc := "(unknown)"
        }
        try {
            winTitle := WinGetTitle("A")
        } catch {
            winTitle := ""
        }
        imeMode := this.ime.IsEnglish() ? "English" : "Chinese"
        target := this.rules.Match(proc, winTitle)
        targetStr := target = "" ? "(no rule)" : target
        MsgBox(
            Format(
                "Current process: {1}`nWindow title: {2}`nIME mode: {3}`nTarget rule: {4}`nPaused: {5}",
                proc, winTitle, imeMode, targetStr, this.isPaused ? "Yes" : "No"
            ),
            "AutoSwitch Status", "Iconi"
        )
    }

    TogglePause(*) {
        this.isPaused := !this.isPaused
        this._UpdateTrayTip()
        this.logger.Log("INFO", this.isPaused ? "PAUSED" : "RESUMED")
    }

    ShowSettings(*) {
        if !this.gui {
            this.gui := SettingsGui(this)
        }
        this.gui._RefreshLists()
        this.gui.PollEdit.Value := this.config.pollInterval
        this.gui.CoolEdit.Value := this.config.cooldownMs
        this.gui.WildCheck.Value := this.config.useWildcard
        this.gui.Show()
    }

    ViewLog(*) {
        logPath := this.logger.path
        if FileExist(logPath)
            Run(logPath)
        else
            MsgBox("No log file found yet.", "AutoSwitch", "Iconi")
    }

    OpenConfig(*) {
        iniPath := this.config.iniPath
        if FileExist(iniPath)
            Run(iniPath)
        else
            MsgBox("Config file not found: " iniPath, "AutoSwitch", "Icone")
    }

    ReloadConfigHandler(*) {
        this.ReloadFromConfig()
        MsgBox(
            Format("Config reloaded.`nEN rules: {1}`nZH rules: {2}`nTitle EN: {3}`nTitle ZH: {4}",
                this.config.enList.Length, this.config.zhList.Length,
                this.config.enTitleList.Length, this.config.zhTitleList.Length),
            "AutoSwitch", "Iconi"
        )
    }

    ExitHandler(*) {
        if this.hWinEventHook
            DllCall("UnhookWinEvent", "Ptr", this.hWinEventHook)
        this.logger.Log("INFO", "AutoSwitch exited")
        ExitApp()
    }
}

; ==================== Entry Point ====================

app := AutoSwitch()
