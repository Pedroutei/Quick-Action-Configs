#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true              ; catch F6/F9 even while the game has focus
; InfestationHop - server hops until an Infestation is running (needs a team to join).
;
; Loop (start it while you're loaded into a server with the HUD showing):
;   1. Ctrl+Tab  - open the mod menu
;   2. Home      - quick join a casual team, then wait a few seconds
;   3. F1        - join Infestation
;   4. Loading screen appears?  -> infestation found: beep and stop
;      No loading screen?       -> PgUp to server hop, wait for the HUD (HP/AP bars)
;                                  on the new server, then back to step 1
;
;   F6  = start / stop
;   F9  = exit script
;   (different keys from EventHop / HeadHuntHop, so they can all run at once)
;
; Screen checks use colours from a 1920x1080 screenshot and scale to the window size.

; ---- settings -------------------------------------------------------------
TEAM_KEY          := "{Home}"
EVENT_KEY         := "{F1}"
HOP_KEY           := "{PgUp}"
MENU_OPEN_SEC     := 1.5   ; pause after Ctrl+Tab before pressing Home
TEAM_JOIN_SEC     := 4     ; wait after quick-joining a team before pressing F1
LOAD_CHECK_SEC    := 5     ; how long to watch for a loading screen after F1
HUD_GONE_TIMEOUT  := 60    ; after PgUp, max wait for the old server's HUD to disappear
HUD_BACK_TIMEOUT  := 300   ; max wait for the HUD on the new server
HUD_SETTLE_SEC    := 3     ; extra pause once the HUD is back
MAX_HOPS          := 50    ; safety stop
GAME              := "ahk_exe Fallout76.exe"
; ---------------------------------------------------------------------------

SendMode "Event"
SetKeyDelay 50, 80         ; hold keys briefly so the game registers them
CoordMode "Pixel", "Client"

running := false
TrayTip "Loaded. Press F6 in game to start/stop, F9 to exit.", "InfestationHop"

F6:: {
    global running
    running := !running
    if running {
        SoundBeep 800, 150     ; one beep = started
        SetTimer HopLoop, -300
    } else {
        SoundBeep 500, 150     ; low beep = stopped
        SoundBeep 400, 150
        Status("InfestationHop stopped")
    }
}

F9::ExitApp

HopLoop() {
    global running
    hops := 0
    loop {
        if !running
            return
        if !FocusGame()
            return Stop("Fallout 76 window not found")

        Status("Server " hops + 1 ": opening mod menu")
        PressCtrlTab()
        if !Pause(MENU_OPEN_SEC)
            return

        Status("Server " hops + 1 ": quick joining casual team (Home)")
        Send TEAM_KEY
        if !Pause(TEAM_JOIN_SEC)
            return

        Status("Server " hops + 1 ": trying to join Infestation (F1)")
        Send EVENT_KEY
        if WaitFor(IsLoadingScreen, LOAD_CHECK_SEC, "Server " hops + 1 ": watching for loading screen") {
            SoundBeep 1000, 300
            SoundBeep 1500, 300
            return Stop("Infestation found on server " hops + 1 "! Fast travelling.")
        }
        if !running
            return

        if hops >= MAX_HOPS
            return Stop("Gave up after " MAX_HOPS " hops")
        hops++
        FocusGame()
        Status("Hop " hops ": server hopping (PgUp)")
        Send HOP_KEY

        if !WaitFor(() => !IsHudVisible(), HUD_GONE_TIMEOUT, "Hop " hops ": leaving server") {
            if !running
                return
            continue   ; hop didn't start - try the event key / hop again
        }
        if !WaitFor(IsHudVisible, HUD_BACK_TIMEOUT, "Hop " hops ": loading new server")
            return running ? Stop("New server never loaded (no HUD after " HUD_BACK_TIMEOUT "s)") : ""
        if !Pause(HUD_SETTLE_SEC)
            return
    }
}

; ---- screen checks --------------------------------------------------------

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
    Status(msg)
    TrayTip msg, "InfestationHop"
}

Status(msg) {
    ToolTip msg, 10, 10
    SetTimer ClearTip, -8000
}

ClearTip() => ToolTip()
