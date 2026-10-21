// Read actual enabled sources without enabling, selecting, or registering anything.
import Carbon
import Foundation
func identifier(_ source: TISInputSource) -> String {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
let enabled = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
let result: [String: Any] = [
    "current": identifier(TISCopyCurrentKeyboardInputSource().takeRetainedValue()),
    "enabled": enabled.map(identifier).sorted()
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
