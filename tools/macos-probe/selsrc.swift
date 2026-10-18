import Carbon
import Foundation
func id(_ s: TISInputSource) -> String { guard let p=TISGetInputSourceProperty(s,kTISPropertyInputSourceID) else { return "?" }; return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String }
// 无参数时只读：打印当前输入源，供交接/验收采集状态。
if CommandLine.arguments.count < 2 {
    let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    print("current", id(current))
    exit(0)
}
let want=CommandLine.arguments[1]
let list=TISCreateInputSourceList(nil,false).takeRetainedValue() as! [TISInputSource]
guard let s=list.first(where:{id($0)==want}) else { print("missing",want); exit(1) }
print("select", id(s), TISSelectInputSource(s))
Thread.sleep(forTimeInterval:0.8)
print("current", id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
