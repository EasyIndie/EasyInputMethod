on run argv
    set operation to item 1 of argv
    set fixtureURL to item 2 of argv
    if fixtureURL does not start with "file:///" then error "BLOCKED 非离线页面"
    with timeout of 5 seconds
        tell application "Safari"
            if operation is "create" then
                -- Safari 18.6 不再给 AppleScript 投递的 file:// 授予沙箱扩展（报告 102 §5.3），
                -- 所以页面改由 LaunchServices 打开；接受的目标窗口必须是新建的那个或另一个新窗口。
                set previousIDs to id of every window
                activate
                make new document
                set targetID to 0
                repeat 30 times
                    if exists front window then
                        set candidateID to id of front window
                        if previousIDs does not contain candidateID then
                            set targetID to candidateID
                            exit repeat
                        end if
                    end if
                    delay 0.1
                end repeat
                if targetID is 0 then error "BLOCKED 未取得独有窗口"
                if previousIDs contains targetID then error "BLOCKED 未取得独有窗口"
                set targetWindow to window id targetID
                do shell script "/usr/bin/open -a Safari " & quoted form of fixtureURL
                set landedID to 0
                repeat 60 times
                    repeat with candidate in windows
                        set candidateID to id of candidate
                        try
                            if (URL of current tab of window id candidateID) is fixtureURL then
                                if (candidateID is targetID) or (previousIDs does not contain candidateID) then
                                    set landedID to candidateID
                                    exit repeat
                                end if
                            end if
                        end try
                    end repeat
                    if landedID is not 0 then exit repeat
                    delay 0.1
                end repeat
                if landedID is 0 then error "BLOCKED 未取得独有窗口"
                if landedID is not targetID then
                    -- 页面落到了另一个新窗口：关掉我们自己多建的空窗口，不留无主窗口。
                    try
                        close (window id targetID)
                    end try
                    set targetID to landedID
                end if
                set targetWindow to window id targetID
                -- LaunchServices 在已有空窗口/空标签时会在其中新开一个标签；只保留 fixture 标签。
                if (count of tabs of targetWindow) > 1 then
                    repeat with tabIndex from (count of tabs of targetWindow) to 1 by -1
                        set tabURL to missing value
                        try
                            set tabURL to URL of tab tabIndex of targetWindow
                        end try
                        if tabURL is not fixtureURL then close tab tabIndex of targetWindow
                    end repeat
                    repeat 20 times
                        if (count of tabs of targetWindow) is 1 then exit repeat
                        delay 0.1
                    end repeat
                end if
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
                repeat 20 times
                    set matches to {}
                    set windowElements to entire contents of front window
                    repeat with candidate in windowElements
                        try
                            if role of candidate is "AXTextArea" then
                                if description of candidate is fixtureTitle then set end of matches to contents of candidate
                            end if
                        end try
                    end repeat
                    if (count of matches) is 1 then exit repeat
                    if (count of matches) > 1 then error "BLOCKED 正文文本框身份不唯一"
                    delay 0.1
                end repeat
                if (count of matches) is not 1 then error "BLOCKED 正文文本框身份不唯一"
                tell application "Safari"
                    if not frontmost then error "BLOCKED Safari非前台"
                    if id of front window is not targetID then error "BLOCKED Safari窗口焦点改变"
                    if URL of current tab of front window is not fixtureURL then error "BLOCKED 测试页面身份改变"
                end tell
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
