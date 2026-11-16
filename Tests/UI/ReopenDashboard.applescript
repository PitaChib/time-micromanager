-- Reopens the dashboard without starting/stopping a timer or resolving away time.
tell application "System Events" to tell process "FocusNest"
    click button 3 of group 1 of window "Session Clock"
    delay 1
    if not (exists window "Time Micromanager") then error "Dashboard did not reopen from the floating clock." number 1
    set initialWindows to count of (windows whose name is "Time Micromanager")
    click button 3 of group 1 of window "Session Clock"
    delay 1
    if (count of (windows whose name is "Time Micromanager")) is not initialWindows then error "Opening the dashboard created a duplicate." number 1
    if (count of sheets of window "Time Micromanager") is greater than 0 then return "PASS: dashboard reachable and reused; close/reopen check skipped to preserve the open dialog."
    click (first button of window "Time Micromanager" whose subrole is "AXCloseButton")
    delay 0.5
    click button 3 of group 1 of window "Session Clock"
    delay 1
    if not (exists window "Time Micromanager") then error "Closed dashboard did not reopen from the floating clock." number 1
    return "PASS: dashboard opens, reuses its window, and reopens after closing."
end tell
