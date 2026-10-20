-- Commands are limited to a uniquely named, path-verified test fixture.
on run argv
    set operation to item 1 of argv
    set fixturePath to item 2 of argv
    set fixtureName to item 3 of argv
    set fixtureFile to my fileAlias(fixturePath)
    with timeout of 5 seconds
        tell application "TextEdit"
            if operation is "create" then
                set originalIDs to id of every window
                if exists document fixtureName then error "BLOCKED 测试文档名称冲突"
                activate
                make new document
                set blankID to 0
                repeat 30 times
                    if exists front window then
                        set candidateID to id of front window
                        if candidateID is not in originalIDs then
                            set blankID to candidateID
                            exit repeat
                        end if
                    end if
                    delay 0.1
                end repeat
                if blankID is 0 then error "BLOCKED 未取得自有空白窗口"
                open fixtureFile
                repeat 40 times
                    if (count of (documents whose name is fixtureName)) is 1 and (count of (windows whose name is fixtureName and visible is true)) is 1 then exit repeat
                    delay 0.1
                end repeat
            else
                set testID to (item 4 of argv) as integer
                if operation is "close" and not (exists document fixtureName) then
                    if exists window id testID then
                        if visible of window id testID then error "BLOCKED 测试窗口仍可见"
                    end if
                    return "CLOSED"
                end if
            end if
            set matches to documents whose name is fixtureName
            if (count of matches) is not 1 then error "BLOCKED 测试文档身份不唯一"
            set targetDocument to item 1 of matches
            set documentPath to get path of targetDocument
            if my fileAlias(documentPath) is not fixtureFile then error "BLOCKED 测试文档路径不符"
            if operation is "create" then
                set matches to windows whose name is fixtureName and visible is true
                if (count of matches) is not 1 then error "BLOCKED 测试窗口身份不唯一"
                set testID to id of item 1 of matches
                if testID is in originalIDs then error "BLOCKED 测试窗口ID重复"
                if testID is not blankID and (exists window id blankID) then
                    set blankName to name of window id blankID
                    set blankMatches to documents whose name is blankName
                    if (count of blankMatches) is not 1 then error "BLOCKED 自有空白文档身份已变"
                    set blankDocument to item 1 of blankMatches
                    try
                        if (path of blankDocument) is not missing value then error "BLOCKED 自有空白文档路径已变"
                    on error messageText number errorCode
                        if errorCode is not -2763 then error messageText number errorCode
                    end try
                    if (text of blankDocument) is not "" then error "BLOCKED 自有空白文档内容已变"
                    close blankDocument saving no
                end if
                return testID
            end if
            if not (exists window id testID) then error "BLOCKED 测试窗口不存在"
            if name of window id testID is not fixtureName then error "BLOCKED 测试窗口名称不符"
            if operation is "close" then
                close targetDocument saving no
                repeat 20 times
                    if not (exists document fixtureName) then exit repeat
                    delay 0.1
                end repeat
                if exists document fixtureName then error "BLOCKED 测试文档未关闭"
                if exists window id testID then
                    if visible of window id testID then error "BLOCKED 测试窗口仍可见"
                end if
                return "CLOSED"
            end if
            if not frontmost then error "BLOCKED 应用焦点不符"
            if id of front window is not testID then error "BLOCKED 测试对象焦点不符"
            if operation is "read" then return text of targetDocument
            if operation is "clear" then
                set text of targetDocument to ""
                return "CLEARED"
            end if
            error "BLOCKED 未识别TextEdit动作"
        end tell
    end timeout
end run

on fileAlias(pathText)
    return (POSIX file pathText) as alias
end fileAlias
