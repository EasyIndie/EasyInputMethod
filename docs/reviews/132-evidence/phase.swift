import Cocoa
import ime
@main
struct Probe {
 static func main() {
  let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
  let config = CommandLine.arguments[1]
  guard config.withCString({ ime_config_init($0) }) == IME_OK,
        let session = ImeSession(wubiPath: "data/generated/wubi86-core.tsv", pinyinCharsPath: "data/generated/pinyin-chars.tsv", pinyinWordsPath: "data/generated/pinyin-core.tsv") else { fatalError("private resources") }
  session.prepare()
  let window = CandidateWindow()
  let status = CandidateStatus(mode: "mixed", english: false, fullWidth: false, traditional: false, chinesePunctuation: true)
  let caret = NSRect(x: 20, y: 20, width: 1, height: 20), area = NSRect(x: 0, y: 0, width: 1200, height: 800)
  var stages = [[Double]](repeating: [], count: 3)
  for _ in 0..<10 {
   for code in ["w", "wq", "ni", "nih", "niha", "nihao"] {
    autoreleasepool {
     session.reset(); for letter in code.unicodeScalars { _ = session.feed(letter.value) }
     let candidates = session.candidates(limit: 7)
     let a = DispatchTime.now().uptimeNanoseconds
     window.updateStatus(status, relayout: false)
     let b = DispatchTime.now().uptimeNanoseconds
     window.update(candidates: candidates, input: code, showsNavigationHint: true)
     let c = DispatchTime.now().uptimeNanoseconds
     window.layout(at: caret, within: area)
     let d = DispatchTime.now().uptimeNanoseconds
     window.show(at: caret)
     _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
     window.hide()
     _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
     for (i, pair) in [(a,b),(b,c),(c,d)].enumerated() { stages[i].append(Double(pair.1-pair.0)/1e6) }
    }
   }
  }
  let rows = stages.map { v -> [String:Double] in let s=v.sorted();return ["p50":s[s.count/2],"p95":s[Int(Double(s.count-1)*0.95)],"max":s.last!] }
  let output = try! JSONSerialization.data(withJSONObject: ["stage_names":["status","candidate_update","position_layout"],"samples":60,"first_ms":stages.map { $0[0] },"milliseconds":rows],options:[.sortedKeys])
  print(String(decoding:output,as:UTF8.self))
 }
}
