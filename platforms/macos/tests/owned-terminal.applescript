on run argv
    set operation to item 1 of argv
    with timeout of 5 seconds
        tell application "Terminal"
            if operation is "create" then
                set previousIDs to id of every window
                set createdTab to do script (item 2 of argv)
                set matches to {}
                repeat with candidate in windows
                    if previousIDs does not contain id of candidate then
                        if (count of tabs of candidate) is 1 then
                            if tty of selected tab of candidate is tty of createdTab then set end of matches to id of candidate
                        end if
                    end if
                end repeat
                if (count of matches) is not 1 then error "BLOCKED Terminal新窗口身份不唯一"
                set targetID to item 1 of matches
                return {targetID, tty of createdTab}
            end if
            set targetID to (item 2 of argv) as integer
            set targetTTY to item 3 of argv
            if not (exists window id targetID) then
                if operation is "close" then return "absent"
                error "BLOCKED Terminal窗口不存在"
            end if
            set targetWindow to window id targetID
            if (count of tabs of targetWindow) is not 1 then error "BLOCKED Terminal标签集合改变"
            if tty of selected tab of targetWindow is not targetTTY then error "BLOCKED Terminal TTY改变"
            if operation is "check" then return "owned"
            if operation is "close" then
                if busy of selected tab of targetWindow then error "BLOCKED Terminal仍有运行进程"
                close targetWindow
                repeat 20 times
                    if not (exists window id targetID) then return "closed"
                    delay 0.1
                end repeat
                error "BLOCKED Terminal窗口未关闭"
            end if
            if operation is not "key" and operation is not "prefix" and operation is not "focus" then error "BLOCKED 未识别Terminal动作"
            if not frontmost then error "BLOCKED Terminal非前台"
            if id of front window is not targetID then error "BLOCKED Terminal窗口焦点改变"
        end tell
        set receiverPID to (item 4 of argv) as integer
        set expectedProcess to item 5 of argv
        set actualProcess to do shell script "/bin/ps -p " & receiverPID & " -o tty= -o command="
        set actualProcess to do shell script "printf %s " & quoted form of actualProcess & " | /usr/bin/sed 's/^[ ]*//'"
        if actualProcess is not expectedProcess then error "BLOCKED 接收器进程身份改变"
        tell application "System Events" to tell process "Terminal"
            set targetArea to value of attribute "AXFocusedUIElement"
            if role of targetArea is not "AXTextArea" then error "BLOCKED Terminal非文本控件"
            if operation is "focus" then return "focused"
            if operation is "prefix" then
                set visibleText to value of targetArea
                repeat while visibleText is not ""
                    set lastCharacter to last character of visibleText
                    if lastCharacter is not return and lastCharacter is not linefeed and lastCharacter is not space then exit repeat
                    if (length of visibleText) is 1 then
                        set visibleText to ""
                    else
                        set visibleText to text 1 thru -2 of visibleText
                    end if
                end repeat
                return (visibleText ends with "wq")
            end if
            set testKey to (item 6 of argv) as integer
            if testKey is not 13 and testKey is not 12 and testKey is not 49 then error "BLOCKED 非测试键"
            key code testKey
        end tell
    end timeout
end run
