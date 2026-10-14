import Cocoa
import ime
func require(_ condition: Bool, _ name: String) {
    if !condition { FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8)); exit(1) }
}
let single = WubiLearning.lookup("你")
require(single?.code == "wqiy", "full code rather than short input")
require(single?.characters.first?.roots.map(\.text) == ["亻", "⺈", "小"], "readable actual roots")
require(single?.characters.first?.roots.map(\.key) == ["W", "Q", "I"], "aligned root codes")
require(single?.characters.first?.recognition?.key == "Y", "separate recognition")
let phrase = WubiLearning.lookup("中华人民共和国")
require(phrase?.code == "kwwl" && phrase?.characters.count == 7, "long phrase summary and every character")
require(phrase?.characters[3].code == "nav" && phrase?.characters[3].roots.isEmpty == true, "unknown decomposition preserves full code")
require(WubiLearning.lookup("你好")?.code == "wqvb", "phrase code")
require(WubiLearning.lookup("😀")?.code == nil, "missing code")
require(WubiLearning.lookup("人")?.characters[0].category == "key_name", "key-name category")
for input in ["", "你\t好", String(repeating: "你", count: 33)] {
    require(WubiLearning.lookup(input) == nil, "bounded invalid input")
}
print("PASS wubi-learning: real Rust ABI, ownership, full codes, readable roots, long words, missing data and bounds")
