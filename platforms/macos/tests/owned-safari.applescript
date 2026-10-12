on run argv
    set operation to item 1 of argv
    set fixtureURL to item 2 of argv
    if fixtureURL does not start with "file:///" then error "BLOCKED 非离线页面"
    with timeout of 5 seconds
        tell application "Safari"
            if operation is "create" then
                set previousIDs to id of every window
                make new document with properties {URL:fixtureURL}
                set targetWindow to front window
                set targetID to id of targetWindow
                if previousIDs contains targetID then error "BLOCKED 未取得独有窗口"
            else
                set targetID to (item 3 of argv) as integer
                if not (exists window id targetID) then
                    if operation is "close" then return "absent"
                    error "BLOCKED 测试窗口不存在"
                end if
                set targetWindow to window id targetID
            end if
            if operation is "close" then
                if (visible of targetWindow is false) and ((count of tabs of targetWindow) is 0) then return "closed"
            end if
            if (count of tabs of targetWindow) is not 1 then error "BLOCKED 测试窗口标签集合改变"
            if URL of current tab of targetWindow is not fixtureURL then error "BLOCKED 测试页面身份改变"
            if operation is "create" then return targetID
            if operation is "check" then return "owned"
            if operation is "close" then
                close targetWindow
                repeat 20 times
                    if not (exists window id targetID) then return "closed"
                    if (visible of window id targetID is false) and ((count of tabs of window id targetID) is 0) then return "closed"
                    delay 0.1
                end repeat
                error "BLOCKED 测试窗口未关闭"
                return "closed"
            end if
            if operation is not "focus" and operation is not "read" and operation is not "key" then error "BLOCKED 未识别页面动作"
            if not frontmost then error "BLOCKED Safari非前台"
            if id of front window is not targetID then error "BLOCKED Safari窗口焦点改变"
        end tell
        set fixtureTitle to item 4 of argv
        tell application "System Events" to tell process "Safari"
            if operation is "focus" then
                set matches to {}
                set windowElements to entire contents of front window
                repeat with candidate in windowElements
                    if role of candidate is "AXTextArea" then
                        if description of candidate is fixtureTitle then set end of matches to contents of candidate
                    end if
                end repeat
                if (count of matches) is not 1 then error "BLOCKED 正文文本框身份不唯一"
                set value of attribute "AXFocused" of item 1 of matches to true
            end if
            set targetArea to value of attribute "AXFocusedUIElement"
            if role of targetArea is not "AXTextArea" then error "BLOCKED 非正文文本框"
            if description of targetArea is not fixtureTitle then error "BLOCKED 正文文本框名称不符"
            if operation is "focus" then return "focused"
            if operation is "read" then return value of targetArea
            set testKey to (item 5 of argv) as integer
            if testKey is not 13 and testKey is not 12 and testKey is not 49 then error "BLOCKED 非测试键"
            key code testKey
        end tell
    end timeout
end run
