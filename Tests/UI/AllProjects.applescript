-- Only changes report selection; never starts timers or edits recorded time.
tell application "System Events" to tell process "FocusNest"
    set frontmost to true
    if not (exists window "Time Micromanager") then
        click button 3 of group 1 of window "Session Clock"
        delay 2
    end if
    if (count of sheets of window "Time Micromanager") > 0 then return "SKIP: existing dialog preserved."
    set sidebarList to outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window "Time Micromanager"
    set detailPane to group 2 of splitter group 1 of group 1 of window "Time Micromanager"
    if (count of rows of sidebarList) < 3 then return "SKIP: needs an existing project."
    set projectName to value of static text 1 of UI element 1 of row 3 of sidebarList
    click UI element 1 of row 3 of sidebarList
    delay 0.5
    if value of static text 1 of detailPane is not projectName then error "Project row did not open its report." number 1
    click UI element 1 of row 1 of sidebarList
    delay 0.5
    set reportTitle to value of static text 1 of detailPane
    if reportTitle is not "All projects" then error "All projects did not clear the project filter; still showing " & reportTitle number 1
    if selected of row 1 of sidebarList is not true then error "All projects row is not selected." number 1
    return "PASS: project report switches back to selected All projects report."
end tell
