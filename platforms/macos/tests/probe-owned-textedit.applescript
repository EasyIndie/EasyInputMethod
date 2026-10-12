-- Only a uniquely named fixture file is read or closed.
on run argv
    set injectFailure to item 1 of argv is "failure"
    set fixturePath to item 2 of argv
    set fixtureName to item 3 of argv
    set fixtureFile to (POSIX file fixturePath) as alias
    with timeout of 5 seconds
        tell application "TextEdit"
            set originalIDs to id of (windows whose visible is true)
            if (count of (documents whose name is fixtureName)) is not 0 then error "测试文档名称冲突"
            open fixtureFile
            set matchingDocuments to documents whose name is fixtureName
            if (count of matchingDocuments) is not 1 then error "测试文档身份不唯一"
            set testDocument to item 1 of matchingDocuments
            set documentPath to get path of testDocument
            set documentFile to my fileAlias(documentPath)
            if (documentFile as alias) is not fixtureFile then error "测试文档路径不符"
            try
                set matchingWindows to windows whose name is fixtureName
                if (count of matchingWindows) is not 1 then error "测试窗口身份不唯一"
                set testID to id of item 1 of matchingWindows
                if testID is in originalIDs then error "测试窗口ID重复"
                if text of testDocument is not "" then error "测试文档不是空文档"
                if injectFailure then error "injected-failure" number -2701
                close testDocument saving no
            on error messageText number errorCode
                close testDocument saving no
                if errorCode is not -2701 then error messageText number errorCode
            end try
            repeat 20 times
                if not (exists document fixtureName) and not (visible of window id testID) then exit repeat
                delay 0.1
            end repeat
            if exists document fixtureName then error "测试文档未关闭"
            if visible of window id testID then error "测试窗口仍可见"
            set remainingIDs to id of (windows whose visible is true)
            if (count of remainingIDs) is not (count of originalIDs) then error ("窗口清理数量不符：原=" & (count of originalIDs) & "，余=" & (count of remainingIDs) & "，目标存在=" & (exists window id testID))
            repeat with originalID in originalIDs
                if contents of originalID is not in remainingIDs then error "已有窗口发生变化"
            end repeat
            return "PASS TextEdit窗口关联及仅清理自建文档"
        end tell
    end timeout
end run

on fileAlias(pathText)
    return (POSIX file pathText) as alias
end fileAlias
