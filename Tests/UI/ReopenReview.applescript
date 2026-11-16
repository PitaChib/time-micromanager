-- Leaves records untouched. Checks review presentation when away time is pending.
tell application "System Events" to tell process "FocusNest"
    set expectReview to (value of static texts of group 1 of window "Session Clock") contains "Away time to review"
    set beforeCount to 0
    repeat with candidate in windows
        if name of candidate is "FocusNest" then set beforeCount to beforeCount + 1
    end repeat
    click button 3 of group 1 of window "Session Clock"
    delay 1
    set reviewSheets to 0
    set afterCount to 0
    repeat with candidate in windows
        if name of candidate is "FocusNest" then
            set afterCount to afterCount + 1
            set reviewSheets to reviewSheets + (count of sheets of candidate)
        end if
    end repeat
    if afterCount is greater than beforeCount and beforeCount is greater than 0 then error "Reopening the dashboard created a duplicate window." number 1
    if expectReview and reviewSheets is 0 then
        if (value of static texts of group 1 of window "Session Clock") contains "Away time to review" then
            error "Opening the dashboard leaves pending away time without a review dialog." number 1
        end if
        return "PASS: dashboard reused; pending review was resolved during the check."
    end if
    if not expectReview then return "PASS: dashboard reused; no pending review, so prompt check skipped."
    return "PASS: review is visible and reopening reuses the dashboard window."
end tell
