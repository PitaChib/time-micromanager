-- Checks singleton dashboard behavior without changing time entries.
tell application "System Events" to tell process "FocusNest"
    click button 3 of group 1 of window "Session Clock"
    delay 1
    repeat 4 times
        click button 3 of group 1 of window "Session Clock"
    end repeat
    delay 1
    set dashboardCount to count of (windows whose name is "Time Micromanager")
    if dashboardCount is not 1 then error "Expected one dashboard, found " & dashboardCount number 1
    if (count of sheets of window "Time Micromanager") is greater than 0 then return "PASS: exactly one dashboard after repeated opens; modal review left untouched."
    set frontmost to true
    keystroke "n" using command down
    delay 1
    if (count of (windows whose name is "Time Micromanager")) is not 1 then error "New Window created a duplicate dashboard." number 1
    click (first button of window "Time Micromanager" whose subrole is "AXCloseButton")
    delay 0.5
    click button 3 of group 1 of window "Session Clock"
    delay 1
    if (count of (windows whose name is "Time Micromanager")) is not 1 then error "Closed singleton dashboard did not reopen exactly once." number 1
    return "PASS: repeated opens, New Window, and closing/reopening all keep exactly one dashboard."
end tell
