#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true              ; catch F6/F9/Home even while the game has focus
; InfestationHop - opens the map on each server, drags it around looking for an
; Infestation cloud (cloudscan.py), and server hops when there isn't one.
;
; Loop (start it while you're loaded into a server with the HUD showing):
;   1. Esc       - open the map
;   2. Drag the map to its top-left corner, then sweep it in a grid, checking each view
;      for the dark grey cloud (input is blocked while it does this)
;   3. Cloud found?  -> three beeps, map left on the cloud, switch you back and wait:
;                       Home = hop anyway, F6 = stop
;      No cloud?     -> Esc to close the map, Ctrl+Tab, PgUp to server hop
;   4. Wait for the HUD (HP/AP bars) on the new server, then back to step 1
;   With AUTO_SCAN := false it skips step 2 and waits for you to check the map and press Home.
;
;   F6   = start / stop
;   Home = "OK, hop" (only while it's waiting for you - otherwise Home works as normal)
;   F9   = exit script
;   (different keys from EventHop / HeadHuntHop, so they can all run at once)
;
; Screen checks use colours from a 1920x1080 screenshot and scale to the window size.

; ---- settings -------------------------------------------------------------
MAP_KEY           := "{Esc}"
HOP_KEY           := "{PgUp}"
CLOSE_MAP_FIRST   := true  ; press Esc to close the map before opening the mod menu (false if you close it yourself)
MAP_CLOSE_SEC     := 1     ; pause after closing the map before Ctrl+Tab
MENU_OPEN_SEC     := 1.5   ; (fallback if the menu can't be detected) pause after Ctrl+Tab before PgUp
HOP_LEAVE_SEC     := 10    ; after PgUp, wait this long for the old server to disconnect before looking for the new one
HUD_BACK_TIMEOUT  := 300   ; max wait for the HUD on the new server
HUD_SETTLE_SEC    := 3     ; extra pause once the HUD is back, before opening the map
MAX_HOPS          := 100   ; safety stop
IDLE_MS           := 500   ; background use: wait until you stop typing/moving the mouse this long before switching to the game
IDLE_MAX_WAIT_SEC := 3     ; ...but take focus anyway after this long
FOCUS_SETTLE_MS   := 800   ; after switching to the game, wait this long before pressing keys (raise if keys get ignored)
PEEK_EVERY_SEC    := 10    ; while a new server loads in the background, switch to the game this often to check for the HUD
PEEK_SEC          := 2     ; how long each check looks for the HUD before switching back
BLOCK_INPUT       := true  ; block your mouse/keyboard while the script is switched into the game
MAX_BLOCK_SEC     := 45    ; safety: never block input longer than this (Ctrl+Alt+Del also unblocks) - the map scan takes ~25s
GAME              := "ahk_exe Fallout76.exe"
; map scan
AUTO_SCAN         := true  ; scan the map for the cloud and hop by itself when there isn't one
MAP_OPEN_SEC      := 1.5   ; wait after Esc for the map to open
CORNER_DRAGS      := 5     ; drags towards the top-left to start the sweep from the map's corner
SCAN_COLS         := 4     ; views across (map is ~2 screens wide)
SCAN_ROWS         := 4     ; views down (map is ~3 screens tall)
STEP_X            := 700   ; how far each sideways drag moves (pixels at 1920x1080, max 750)
STEP_Y            := 700   ; how far each downward drag moves (max 700)
DRAG_SETTLE_MS    := 350   ; wait after a drag before checking the view
PYTHON            := "python"
SAVE_ALL_SCANS    := false ; true = save every view to cloudshots\ (views with a cloud are always saved)
; ---------------------------------------------------------------------------

; BlockInput needs admin: relaunch elevated (if you decline, it runs without blocking)
if BLOCK_INPUT && !A_IsAdmin {
    try {
        Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
        ExitApp
    }
}

SendMode "Event"
SetKeyDelay 50, 80         ; hold keys briefly so the game registers them
CoordMode "Pixel", "Client"

running := false
waitingForOk := false     ; true while the map is open and it's waiting for you to press Home
menuCheck := ""           ; "" = not tested yet, true = can see the mod menu, false = can't (fixed timing)
borrowed := false, prevWin := 0, prevX := 0, prevY := 0
TrayTip "Loaded. Press F6 in game to start/stop, Home to hop after checking the map, F9 to exit.", "InfestationHop"

F6:: {
    global running, waitingForOk
    running := !running
    waitingForOk := false
    if running {
        SoundBeep 800, 150     ; one beep = started
        SetTimer HopLoop, -300
    } else {
        SoundBeep 500, 150     ; low beep = stopped
        SoundBeep 400, 150
        UnblockUser()
        Status("InfestationHop stopped")
    }
}

F9::ExitApp

#HotIf waitingForOk
Home:: {
    global waitingForOk
    waitingForOk := false
    SoundBeep 1000, 80
}
#HotIf

HopLoop() {
    HopLoopRun()
    ReturnFocus()   ; if it was stopped while switched into the game, switch back
}

HopLoopRun() {
    global running, waitingForOk
    hops := 0
    loop {
        if !running
            return

        ; 1. open the map
        if !BorrowFocus()
            return Stop("Fallout 76 window not found")
        Status("Server " hops + 1 ": opening map (Esc)")
        Send MAP_KEY
        if !Pause(MAP_OPEN_SEC)
            return

        ; 2. scan it for a cloud - or, if there is one / scanning is off, wait for your OK
        result := AUTO_SCAN ? ScanMap("Server " hops + 1) : "manual"
        if result = "stopped" || !running
            return
        if result != "none" {
            ReturnFocus()
            if result = "found" {
                SoundBeep 1500, 150
                SoundBeep 1500, 150
                SoundBeep 1500, 150
                TrayTip "Infestation cloud on server " hops + 1 "! Home = hop anyway, F6 = stop", "InfestationHop"
            } else if result = "error" {
                SoundBeep 400, 300
                TrayTip "Couldn't scan the map (see cloudscan.py) - check it yourself, Home to hop", "InfestationHop"
            } else
                SoundBeep 1200, 150    ; map is up - have a look
            waitingForOk := true
            while running && waitingForOk {
                Status("Server " hops + 1 ": " (result = "found" ? "cloud found" : "check the map") " - Home to hop, F6 to stop")
                Sleep 250
            }
            waitingForOk := false
            if !running
                return
        }
        if hops >= MAX_HOPS
            return Stop("Gave up after " MAX_HOPS " hops")
        hops++

        ; 3. close the map, open the mod menu, hop
        if !BorrowFocus()
            return Stop("Fallout 76 window not found")
        if CLOSE_MAP_FIRST {
            Status("Hop " hops ": closing map (Esc)")
            Send MAP_KEY
            if !Pause(MAP_CLOSE_SEC)
                return
        }
        Status("Hop " hops ": opening mod menu")
        if !OpenMenu()
            return
        Status("Hop " hops ": server hopping (PgUp)")
        Send HOP_KEY
        Sleep 200
        ReturnFocus()   ; you get your mouse/keyboard back while the hop happens

        ; 4. wait for the new server
        if !Pause(HOP_LEAVE_SEC)
            return
        if !WaitForHud(HUD_BACK_TIMEOUT, "Hop " hops ": loading new server")
            return running ? Stop("New server never loaded (no HUD after " HUD_BACK_TIMEOUT "s)") : ""
        if !Pause(HUD_SETTLE_SEC)
            return
    }
}

; ---- map scan -------------------------------------------------------------

; Drags the map to its top-left corner, then sweeps it row by row (zig-zag), checking
; each view with cloudscan.py. Returns "found", "none", "error" or "stopped".
; Leaves the map on the cloud when it finds one.
ScanMap(label) {
    WinGetClientPos &cx, &cy, &cw, &ch, GAME
    if !cw
        return "error"
    Status(label ": moving map to the top-left corner")
    loop CORNER_DRAGS {
        if !running
            return "stopped"
        DragMap(750, 700)
    }
    loop SCAN_ROWS {
        row := A_Index
        loop SCAN_COLS {
            if !running
                return "stopped"
            Status(label ": scanning map " row "," A_Index)
            res := CheckForCloud(cx, cy, cw, ch)
            if res != "none"
                return res
            if A_Index < SCAN_COLS
                DragMap(Mod(row, 2) ? -STEP_X : STEP_X, 0)   ; zig-zag across
        }
        if row < SCAN_ROWS
            DragMap(0, -STEP_Y)                              ; next row down
    }
    return "none"
}

; Runs cloudscan.py on the game window: exit code 2 = cloud, 0 = none, anything else = error.
CheckForCloud(cx, cy, cw, ch) {
    Sleep DRAG_SETTLE_MS
    try code := RunWait('"' PYTHON '" "' A_ScriptDir '\cloudscan.py" ' cx ' ' cy ' ' cw ' ' ch (SAVE_ALL_SCANS ? " --save-all" : ""), A_ScriptDir, "Hide")
    catch
        return "error"
    return code = 2 ? "found" : code = 0 ? "none" : "error"
}

; Left-click drags the map by dx,dy (1920x1080 pixels; the map follows the mouse, so a
; negative dx shows more of the map to the right). Moves in small relative steps so the
; game sees a real drag. Starts where the whole drag stays on open map, clear of panels.
DragMap(dx, dy) {
    WinGetClientPos &cx, &cy, &cw, &ch, GAME
    sx := cw / 1920, sy := ch / 1080
    x0 := dx > 0 ? 450 : dx < 0 ? 1200 : 800
    y0 := dy > 0 ? 250 : dy < 0 ? 950 : 600
    CoordMode "Mouse", "Client"
    MouseMove Round(x0 * sx), Round(y0 * sy), 0
    Sleep 60
    Click "Down"
    Sleep 60
    steps := 15
    loop steps {
        MouseMove Round(dx * sx / steps), Round(dy * sy / steps), 0, "R"
        Sleep 12
    }
    Sleep 60
    Click "Up"
    Sleep 60
}

; ---- screen checks --------------------------------------------------------

; Mod menu is open if the Pip-Boy green box borders show on the left edge (Friends box).
IsMenuOpen() {
    WinGetClientPos , , &w, &h, GAME
    if !w
        return false
    return PixelSearch(&fx, &fy, 0, Round(90 * h / 1080), Round(30 * w / 1920), Round(210 * h / 1080), 0x1AFF80, 60)
}

; Opens the mod menu with Ctrl+Tab and waits until it's showing. The first time, checks
; whether the menu can be seen at all; if not, falls back to a fixed wait from then on.
OpenMenu() {
    global menuCheck
    if menuCheck = true && IsMenuOpen()
        return true
    PressCtrlTab()
    if menuCheck = false
        return Pause(MENU_OPEN_SEC)
    if WaitFor(IsMenuOpen, 2.5, "Waiting for mod menu") {
        menuCheck := true
        return Pause(0.3)
    }
    if !running
        return false
    if menuCheck = ""
        menuCheck := false   ; can't see the menu on this setup - use fixed timing
    return true
}

; HUD is showing if the AP bar is solid cream, or the HP bar is cream/red.
IsHudVisible() {
    ap := 0, hp := 0, n := 0
    x := 1500
    while x <= 1790 {
        ap += IsColor(Px(x, 1006), 0xFFFFCB, 30)
        n++
        x += 15
    }
    x := 125, m := 0
    while x <= 420 {
        c := Px(x, 1006)
        hp += IsColor(c, 0xFFFFCB, 30) || IsColor(c, 0xF5725A, 35)
        m++
        x += 15
    }
    return ap / n >= 0.7 || hp / m >= 0.7
}

; Loading screen: gold spinning "76" gear bottom-right + dark tip banner along the bottom.
IsLoadingScreen() {
    gold := 0, g := 0
    y := 960
    while y <= 1040 {
        x := 1790
        while x <= 1870 {
            gold += IsColor(Px(x, y), 0xF3CA5A, 40)
            g++
            x += 16
        }
        y += 16
    }
    dark := 0, d := 0
    x := 250
    while x <= 1300 {
        dark += Brightness(Px(x, 1037)) < 45
        d++
        x += 75
    }
    return gold / g >= 0.2 && dark / d >= 0.8
}

; Colour of a 1920x1080 reference point, scaled to the game window.
Px(x, y) {
    WinGetClientPos , , &w, &h, GAME
    return Integer(PixelGetColor(Round(x * w / 1920), Round(y * h / 1080)))
}

IsColor(c, ref, tol) {
    return Abs(((c >> 16) & 0xFF) - ((ref >> 16) & 0xFF)) <= tol
        && Abs(((c >> 8) & 0xFF) - ((ref >> 8) & 0xFF)) <= tol
        && Abs((c & 0xFF) - (ref & 0xFF)) <= tol
}

Brightness(c) => (((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF)) / 3

; ---- helpers --------------------------------------------------------------

; Polls check() until it's true (returns true) or the timeout / F6 stop (returns false).
WaitFor(check, sec, label) {
    global running
    end := A_TickCount + sec * 1000
    while A_TickCount < end {
        if !running || !WinExist(GAME)
            return false
        if check()
            return true
        Status(label " (" Ceil((end - A_TickCount) / 1000) "s)")
        Sleep 400
    }
    return false
}

; Waits for the HUD on a new server. Checks in the background, and every PEEK_EVERY_SEC
; switches to the game briefly in case the HUD can't be seen while you're in another
; window. If the HUD is there it stays in the game (the next step needs it anyway).
WaitForHud(sec, label) {
    global running
    end := A_TickCount + sec * 1000
    nextPeek := A_TickCount + PEEK_EVERY_SEC * 1000
    while A_TickCount < end {
        if !running || !WinExist(GAME)
            return false
        if IsHudVisible()
            return true
        if !WinActive(GAME) && A_TickCount >= nextPeek {
            if BorrowFocus() {
                if WaitFor(IsHudVisible, PEEK_SEC, label " - checking game")
                    return true
                ReturnFocus()
            }
            nextPeek := A_TickCount + PEEK_EVERY_SEC * 1000
        }
        Status(label " (" Ceil((end - A_TickCount) / 1000) "s)")
        Sleep 400
    }
    return false
}

Pause(sec) {
    global running
    end := A_TickCount + sec * 1000
    while A_TickCount < end {
        if !running
            return false
        Sleep 100
    }
    return true
}

PressCtrlTab() {
    Send "{Ctrl down}"
    Sleep 80
    Send "{Tab}"
    Sleep 80
    Send "{Ctrl up}"
}

; Switches to the game to press keys. If you're using another window, waits for a
; pause in your typing/mouse use, and remembers the window and mouse position.
BorrowFocus() {
    global borrowed, prevWin, prevX, prevY
    if !WinExist(GAME)
        return false
    if WinActive(GAME)
        return true
    borrowed := false
    end := A_TickCount + IDLE_MAX_WAIT_SEC * 1000
    while running && A_TimeIdlePhysical < IDLE_MS && A_TickCount < end {
        Status("Waiting for you to pause before switching to the game")
        Sleep 100
    }
    prevWin := WinExist("A")
    CoordMode "Mouse", "Screen"
    MouseGetPos &prevX, &prevY
    if !FocusGame()
        return false
    borrowed := true
    BlockUser(true)
    Sleep FOCUS_SETTLE_MS   ; let the game notice it has focus before sending keys
    return true
}

; Switches back to the window you were using, if BorrowFocus took focus.
ReturnFocus() {
    global borrowed
    if !borrowed
        return
    borrowed := false
    try WinActivate "ahk_id " prevWin
    CoordMode "Mouse", "Screen"
    MouseMove prevX, prevY, 0
    BlockUser(false)
}

; Blocks/unblocks your physical mouse and keyboard (the script's own keypresses still work).
BlockUser(on) {
    if !BLOCK_INPUT || !A_IsAdmin
        return
    if on {
        BlockInput true
        SetTimer UnblockUser, -MAX_BLOCK_SEC * 1000   ; safety release
    } else
        UnblockUser()
}

UnblockUser() {
    SetTimer UnblockUser, 0
    BlockInput false
}

FocusGame() {
    if !WinExist(GAME)
        return false
    if !WinActive(GAME) {
        WinActivate GAME
        WinWaitActive GAME, , 3
    }
    return WinActive(GAME)
}

Stop(msg) {
    global running
    running := false
    UnblockUser()
    Status(msg)
    TrayTip msg, "InfestationHop"
}

Status(msg) {
    ToolTip msg, 10, 10
    SetTimer ClearTip, -8000
}

ClearTip() => ToolTip()
