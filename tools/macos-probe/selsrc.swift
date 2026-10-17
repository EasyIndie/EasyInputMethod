import Carbon
import Foundation
func id(_ s: TISInputSource) -> String { guard let p=TISGetInputSourceProperty(s,kTISPropertyInputSourceID) else { return "?" }; return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String }
let want=CommandLine.arguments[1]
let list=TISCreateInputSourceList(nil,false).takeRetainedValue() as! [TISInputSource]
guard let s=list.first(where:{id($0)==want}) else { print("missing",want); exit(1) }
print("select", id(s), TISSelectInputSource(s))
Thread.sleep(forTimeInterval:0.8)
print("current", id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
