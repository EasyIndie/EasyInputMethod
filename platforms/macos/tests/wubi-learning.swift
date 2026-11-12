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
let me = WubiLearning.lookup("我")
require(me?.code == "trnt" && me?.characters.first?.roots.map(\.text) == ["丿", "扌", "斜钩", "末撇"], "verified special last-stroke roots")
require(me?.characters.first?.recognition == nil, "four-root code has no invented recognition")
for text in ["我们", "我国", "特别", "特点", "突然", "投入"] {
    require(WubiLearning.lookup(text)?.characters.allSatisfy { !$0.roots.isEmpty } == true, "feedback phrase coverage " + text)
}
// ADR-311 v2：学习区资源按需解析（只建索引，不预先解析 3,000 条）。
require(LearningHints.indexedCount >= 3000, "学习区索引应覆盖 3,000 字，实际 \(LearningHints.indexedCount)")
require(LearningHints.materializedCount == 0, "加载时应零解析")
require(LearningHints.hint(for: "和")?.recognition?.letter == "G", "按需解析能取到识别码")
require(LearningHints.materializedCount == 1, "只解析被查询的那一条")
require(LearningHints.hint(for: "我")?.roots.count == 3, "位次不符的条目已截断")
// ADR-313 练习：只出 full 题、判分与识别码表正确、进度有界。
let codeBank = Practice.bank(kind: .code)
let recogBank = Practice.bank(kind: .recognition)
require(codeBank.count > 500 && recogBank.count > 500, "题库应有足够 full 题")
require(codeBank.allSatisfy { LearningHints.hint(for: $0.char)?.quality == "full" }, "只出 full 题")
let sample = codeBank.first { $0.char == "和" } ?? codeBank[0]
require(Practice.judgeCode(sample.code, question: sample), "正确码判对")
require(Practice.judgeCode(sample.code.uppercased() + " ", question: sample), "大小写与空白不敏感")
require(!Practice.judgeCode("zzzz", question: sample), "错误码判错")
require(Practice.recognitionLetter(stroke: "横", structure: "左右") == "G", "识别码表 横/左右 → G")
require(Practice.recognitionLetter(stroke: "折", structure: "杂合") == "V", "识别码表 折/杂合 → V")
// ADR-313 练习流程（自动化）：答题 → 判分 → 进度增长；识别码说明用正确答案。
let flowDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lampyris-practice-flow")
try? FileManager.default.removeItem(at: flowDir)
try? FileManager.default.createDirectory(at: flowDir, withIntermediateDirectories: true)
let flowProgress = PracticeProgress(url: flowDir.appendingPathComponent("flow.tsv"))
let flow = PracticeSession(kind: .code, progress: flowProgress)
guard let firstQuestion = flow.question else { exit(1) }
let before = flow.summary
guard let okResult = flow.submitCode(firstQuestion.code) else { exit(1) }
require(okResult.correct, "正确码应判对")
require(flow.summary != before, "作答后进度摘要应变化")
require(flowProgress.rows.values.reduce(0) { $0 + $1.attempts } == 1, "应记录 1 次作答")
require(flowProgress.rows.values.reduce(0) { $0 + $1.correct } == 1, "应记录 1 次正确")
_ = flow.submitCode("zzzz")
require(flowProgress.rows.values.reduce(0) { $0 + $1.attempts } == 2, "错误作答也应计数")
// ADR-332：字根题——看字根打所在键；键名与其余字根各一题，Z 不出题，答案是 1 位键位。
let rootBank = Practice.bank(kind: .roots)
require(rootBank.count > 100, "应读到完整字根表而不是只有键名的兜底：\(rootBank.count)")
require(Practice.rootBank(layout: .wubi86).count == 25, "资源缺失时退回 25 个键名字根")
require(rootBank.count >= 25, "字根题库至少覆盖 25 个键名字根：\(rootBank.count)")
require(rootBank.allSatisfy { $0.code.count == 1 && $0.code != "z" && $0.roots.count == 1 }, "字根题答案是 1 位键位且不含 Z")
require(Set(rootBank.map(\.char)).count == rootBank.count, "同一个字根只出一题")
require(rootBank.first(where: { $0.char == "金" })?.code == "q", "键名字根 金 在 Q")
require(PracticeKind.allCases.first == .roots, "字根排在题型最前（入门第一步）")
if let rootQuestion = rootBank.first {
    require(PracticeKind.roots.answer(for: rootQuestion) == rootQuestion.code, "字根题答案取键位")
    require(Practice.judgeCode(rootQuestion.code.uppercased(), question: rootQuestion), "字根题大小写不敏感")
    require(!Practice.judgeCode("z", question: rootQuestion), "错键判错")
}
// ADR-334：词组题——取随包码表最常用的 2–4 字词，讲解按取码规则拆到每个字。
let phraseSample = "# c\nwqvb\t你好\t50\nwqvb\t你好\t40\nkwwl\t中华人民共和国\t99\nwgkl\t全国\t70\nabc\t短码\t90\nyygk\t计算机\t60\nwwwl\t从众如流\t5\nggll\t一\t999\n"
let phrases = Practice.phraseBank(tsv: phraseSample, limit: 3)
require(phrases.map(\.char) == ["全国", "计算机", "你好"], "按权重取前 3 个 2–4 字词，去重、跳过单字/长词/短码：\(phrases.map(\.char))")
require(Practice.phraseParts(word: "你好", code: "wqvb").map { "\($0.glyph)\($0.key)" } == ["你WQ", "好VB"], "两字词各取前两码")
require(Practice.phraseParts(word: "计算机", code: "yygk").map(\.key) == ["Y", "Y", "GK"], "三字词 1+1+2")
require(Practice.phraseParts(word: "从众如流", code: "wwwl").map(\.key) == ["W", "W", "W", "L"], "四字词各取首码")
require(Practice.phraseParts(word: "中华人民共和国", code: "kwwl").isEmpty, "规则外的长度不乱讲")
require(Practice.bank(kind: .phrase).count == Practice.phraseLimit, "随包码表应出满词组题：\(Practice.bank(kind: .phrase).count)")
// ADR-335：薄弱字清单——只收单个汉字、有界、可重载、可清空；只给「完整码」题型加权。
let weakURL = flowDir.appendingPathComponent("weak-chars.tsv")
try? FileManager.default.removeItem(at: weakURL)
let weakChars = WeakChars(url: weakURL)
for rejected in ["你好", "a", "", "1"] { weakChars.record(rejected) }
require(weakChars.rows.isEmpty, "只收单个汉字")
weakChars.record("慧", now: 10)
weakChars.record("慧", now: 20)
require(weakChars.rows["慧"]?.count == 2 && weakChars.contains("慧") && !weakChars.contains("你"), "计数与查询")
require(WeakChars(url: weakURL).rows["慧"]?.count == 2, "可重载")
for scalar in 0x4E00..<(0x4E00 + WeakChars.maxRows + 20) {
    weakChars.record(String(UnicodeScalar(scalar)!), now: scalar)
}
require(weakChars.rows.count == WeakChars.maxRows && weakChars.contains("慧"), "有界，且次数多的留下")
weakChars.reset()
require(weakChars.rows.isEmpty && !FileManager.default.fileExists(atPath: weakURL.path), "清空即删文件")
let weakTarget = Practice.bank(kind: .code)[3].char
weakChars.record(weakTarget)
let weakProgress = PracticeProgress(url: flowDir.appendingPathComponent("weak-progress.tsv"))
let weakSession = PracticeSession(kind: .code, progress: weakProgress, weak: weakChars)
// 权重轴：前 3 个字各占 2（0..<6），薄弱字占 2 + 8（6..<16）。
_ = weakSession.next(pick: { $0 - 1 })
require(weakSession.next(pick: { _ in 15 })?.char == weakTarget, "薄弱字在完整码题型里加权")
weakSession.switchKind(.code2)
_ = weakSession.next(pick: { $0 - 1 })
let secondBank = weakSession.bank
if let index = secondBank.firstIndex(where: { $0.char == weakTarget }), index > 0 {
    require(weakSession.next(pick: { _ in index * 2 + 2 })?.char != weakTarget, "其它题型不加权")
}
weakChars.reset()
// ADR-328：出题按错题加权——没练过 2、错一次 9、错一次后连对两次回到 1；且不连出同一个字。
typealias Row = PracticeProgress.Row
require(PracticeSession.weight(for: nil) == 2, "没练过的字权重 2")
require(PracticeSession.weight(for: Row(attempts: 3, correct: 3, lastSeen: 0)) == 1, "全对的字权重 1")
require(PracticeSession.weight(for: Row(attempts: 1, correct: 0, lastSeen: 0)) == 9, "错一次权重 9")
require(PracticeSession.weight(for: Row(attempts: 3, correct: 2, lastSeen: 0)) == 1, "错一次后连对两次还清")
require(PracticeSession.weight(for: Row(attempts: 9, correct: 0, lastSeen: 0)) == 17, "欠账封顶")
let weightedProgress = PracticeProgress(url: flowDir.appendingPathComponent("weighted.tsv"))
let weighted = PracticeSession(kind: .code, progress: weightedProgress)
require(weighted.bank.count > 10, "加权测试需要真实题库")
let missed = weighted.bank[5].char
weightedProgress.record(char: missed, kind: .code, correct: false)
// 权重轴：前 5 个没练过的字各占 2（0..<10），错过的第 6 个字占 9（10..<19），第 7 个字从 19 开始。
for offset in 10..<19 {
    _ = weighted.next(pick: { $0 - 1 })   // 先跳到题库末尾，避免「不连出同一个字」把目标排除
    require(weighted.next(pick: { _ in offset })?.char == missed, "权重轴 \(offset) 应落在错题上")
}
_ = weighted.next(pick: { $0 - 1 })
require(weighted.next(pick: { _ in 19 })?.char == weighted.bank[6].char, "错题之后是下一个字")
// 不连出同一个字：上一题是错题时，同一位置抽到的是别的字。
_ = weighted.next(pick: { _ in 10 })
require(weighted.question?.char == missed, "回到错题")
require(weighted.next(pick: { _ in 10 })?.char != missed, "不应连出同一个字")
let recognitionSession = PracticeSession(kind: .recognition, progress: flowProgress)
guard let recognitionQuestion = recognitionSession.question, let expected = recognitionQuestion.recognition else { exit(1) }
guard let recognitionResult = recognitionSession.submitRecognition(stroke: expected.stroke,
                                                                  structure: expected.structure) else { exit(1) }
require(recognitionResult.correct, "正确末笔/结构应判对")
// 码值/识别码统一在答案区展示，判分结果只回对错
require(recognitionResult.explanation.isEmpty, "判分说明不再重复答案（答案区展示）")

// 练习字根行与学习区同样式：字形上、键位下（大写）。
let explanationView = PracticeExplanationView(frame: NSRect(x: 0, y: 0, width: 400, height: PracticeExplanationView.height))
explanationView.show(char: "老", roots: [("土", "F"), ("丿", "T"), ("匕", "X")],
                     recognition: ("B", "折", "上下"), code: "ftxb",
                     short1: nil, short2: "ft", revealsAnswer: true)
let explanationLabel = explanationView.accessibilityLabel() ?? ""
require(explanationLabel.contains("完整码 FTXB"), "整体展示应包含完整码")
require(explanationLabel.contains("识别码 B"), "整体展示应包含识别码")

// 题型：一级/二级简码只出有对应简码的字；答案取自简码而不是完整码
for kind in PracticeKind.allCases {
    let bank = Practice.bank(kind: kind, limit: 300)
    require(!bank.isEmpty, "\(kind.title) 应有题")
    for question in bank.prefix(50) {
        switch kind {
        case .roots: require(question.code.count == 1, "字根题答案是 1 位键位")
        case .code1: require(question.short1?.count == 1, "一级简码题必须有一级简码")
        case .code2: require(question.short2?.count == 2, "二级简码题必须有二级简码")
        case .code: require(!question.code.isEmpty, "完整码题必须有码")
        case .phrase: require(question.code.count == 4 && (2...4).contains(question.char.count), "词组题是 2–4 字、4 位码")
        case .recognition: require(question.recognition != nil, "识别码题必须有识别码")
        }
    }
}
if let sample = Practice.bank(kind: .code1, limit: 200).first, let short = sample.short1 {
    require(Practice.judgeCode(short.uppercased(), question: sample), "一级简码应判对")
    require(!Practice.judgeCode(sample.code, question: sample), "完整码不应算作一级简码答案")
}
if let sample = Practice.bank(kind: .code2, limit: 200).first, let short = sample.short2 {
    require(Practice.judgeCode(short, question: sample), "二级简码应判对")
}

// 作答框：4 格上限、z 只点亮不入答案、退格/Esc 清空
let answerField = PracticeAnswerView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
var lit: [Character] = []
answerField.onLetter = { lit.append($0) }
func type(_ text: String) {
    for character in text {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: 0, windowNumber: 0, context: nil,
                                     characters: String(character), charactersIgnoringModifiers: String(character),
                                     isARepeat: false, keyCode: 0)
        if let event { answerField.keyDown(with: event) }
    }
}
type("bnhyz")
require(answerField.text == "bnhy", "最多 4 位，z 不进答案")
require(lit.contains("Z"), "z 也应点亮键位图")
answerField.clear()
require(answerField.text.isEmpty, "clear 应清空")
// 位数跟随题型：一级 1 格、二级 2 格
answerField.capacity = 1
type("bn")
require(answerField.text == "b", "一级简码只接受 1 位")
answerField.capacity = 2
answerField.clear()
type("bnhy")
require(answerField.text.count == 2, "二级简码只接受 2 位")

// 25 键字根分布图：数据来自方案、键名字根齐全、分区正确、敲键点亮、答完描边
let keyboard = KeyboardMapView(layout: .wubi86)
keyboard.frame = NSRect(x: 0, y: 0, width: 400, height: KeyboardMapView.totalHeight)
require(keyboard.schemeID == "wubi86", "默认方案为五笔 86")
require(keyboard.entries.count == 26, "25 个键名 + 万能键 Z")
for (letter, root) in [("G", "王"), ("F", "土"), ("K", "口"), ("W", "人"), ("X", "纟"), ("N", "已")] {
    require(keyboard.entries[Character(letter)]?.keyName == root, "键 \(letter) 应挂在字根 \(root)")
}
require(keyboard.entries["Z"]?.zone == 0, "Z 是万能键，不属于五区")
// 口诀：默认不显示，数据按五个区整理
require(KeyRootLayout.wubi86.entries.values.allSatisfy { $0.mnemonic.isEmpty },
        "内置兜底表不含口诀（口诀来自数据文件）")
let loadedLayout = KeyRootLayout.load()
require(loadedLayout.entries["G"]?.mnemonic.hasPrefix("王旁青头戋") == true, "G 键应带助记口诀")
require(loadedLayout.mnemonicsByZone.map(\.zone) == [1, 2, 3, 4, 5], "口诀应覆盖五个区")
require(loadedLayout.mnemonicsByZone.allSatisfy { !$0.text.isEmpty }, "每个区都应有口诀")
require(KeyRootLayout.wubi86.rows.map(\.count) == [10, 9, 7], "物理排布 10/9/7 键")
// 数据化：真实字根分布来自 TSV，缺失时回落到只有键名
let loaded = KeyRootLayout.load()
require(loaded.schemeID == "wubi86", "默认加载五笔 86 键位表")
require((loaded.entries["G"]?.roots.count ?? 0) > 0, "数据文件应在时给出每键的真实字根分布")
require(loaded.entries["G"]?.roots.contains("王") == false, "字根列表不重复键名字根")
require(KeyRootLayout.parse(tsv: "bad", schemeID: "wubi86", displayName: "x") == nil, "残缺 TSV 应被拒绝")
// 口诀与字根都按区位号排序（11→15 …），与主流教程一致
let zones = loaded.mnemonicsByZone
require(zones.first?.text.hasPrefix("王旁青头") == true, "横区口诀应从 11 G 开始")
require(zones.last?.text.hasPrefix("已半巳满") == true, "折区口诀应从 51 N 开始")
require(loaded.entries["G"]?.position == 11 && loaded.entries["A"]?.position == 15, "区位号 11/15")
let gRoots = loaded.entries["G"]?.roots ?? []
if let wu = gRoots.firstIndex(of: "五"), let yi = gRoots.firstIndex(of: "一") {
    require(wu < yi, "字根顺序应跟随口诀（五在一前）")
}
for (row, expected) in zip(KeyRootLayout.wubi86.rows, [[10], [9], [7]]) {
    require(row.count == expected[0], "每排键数正确")
}
// 字根显示：过滤字体缺字形（否则渲染成 ?），并受网格容量约束
let mixedRoots = ["一", "\u{2E88}", "\u{3105}", "二"]
require(KeyboardMapView.displayableRoots(mixedRoots) == ["一", "二"], "康熙部首与注音符号应被筛掉")
let many = Array(repeating: "一", count: 30)
require(KeyboardMapView.visibleRoots(many).count == KeyboardMapView.rootColumns * KeyboardMapView.rootRows,
        "字根网格容量应封顶")
require(KeyboardMapView.visibleRoots(many).last == "…", "超出容量的字根以省略号收尾")
keyboard.flash("F")
keyboard.markAnswer("ftxb")
require(keyboard.pressedLetterForTesting == "F", "敲键后键位图应点亮该键")
require(keyboard.markedLettersForTesting == Set(["F", "T", "X", "B"]), "答完应描出答案用到的键位")
// 重复码位：同一个键要能显示多个位次，而不是把 4 位压成 1 个键
keyboard.markAnswer("qqqq")
require(keyboard.markedPositionsForTesting.map(\.position) == [1, 2, 3, 4],
        "重复码位应保留四位位次")
require(keyboard.markedLettersForTesting == Set(["Q"]), "四个 Q 只应点亮一个键")
// 位次角标：画在键位右下角，同一键多次出现合并显示圈号
keyboard.markAnswer("mgkd")
require(keyboard.positionMarks(for: "M") == "①", "M 应是第 1 位")
require(keyboard.positionMarks(for: "D") == "④", "D 应是第 4 位")
keyboard.markAnswer("qqqq")
require(keyboard.positionMarks(for: "Q") == "①②③④", "重复码位应合并显示四个位次")
require(keyboard.positionMarks(for: "W").isEmpty, "未用到的键不应有角标")
// 输入视图只接受 a–y、退格与回车。
let answer = PracticeAnswerView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
var submitted: String?
answer.onReturn = { submitted = $0 }
func key(_ text: String) -> NSEvent? {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                     windowNumber: 0, context: nil, characters: text,
                     charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0)
}
for character in "GCft" { if let event = key(String(character)) { answer.keyDown(with: event) } }
require(answer.text == "gcft", "只接受小写字母（实际 \(answer.text)）")
if let event = key("\u{7F}") { answer.keyDown(with: event) }
require(answer.text == "gcf", "退格删除")
if let event = key("z") { answer.keyDown(with: event) }
require(answer.text == "gcf", "z 不接受")
if let event = key("\r") { answer.keyDown(with: event) }
require(submitted == "gcf", "回车提交")
// ADR-313 练习窗口：版式自检（控件不越界、不与题型控件重叠）。
// 字根题型的实拍（ADR-332）：亮/暗各一张，供人工目视。
for light in [true, false] {
    let progressURL = flowDir.appendingPathComponent("render.tsv")
    if let image = PracticeWindow.shared.renderForTesting(kind: .roots, progressURL: progressURL, light: light),
       let data = image.representation(using: .png, properties: [:]) {
        try? data.write(to: flowDir.appendingPathComponent("practice-roots-\(light ? "light" : "dark").png"))
    }
}
if let image = PracticeWindow.shared.renderForTesting(kind: .phrase, progressURL: flowDir.appendingPathComponent("render.tsv"), light: true),
   let data = image.representation(using: .png, properties: [:]) {
    try? data.write(to: flowDir.appendingPathComponent("practice-phrase-light.png"))
}
for kind in [PracticeKind.roots, .code, .phrase, .recognition] {
    let problems = PracticeWindow.shared.layoutProblemsForTesting(kind: kind)
    require(problems.isEmpty, "练习窗口版式问题：\(problems.joined(separator: "; "))")
}
let tmpProgress = PracticeProgress(url: URL(fileURLWithPath: NSTemporaryDirectory() + "lampyris-practice-test" + "/practice.tsv"))
for index in 0..<3200 { tmpProgress.record(char: "字", kind: .code, correct: index % 2 == 0, now: index) }
require(tmpProgress.rows.count <= PracticeProgress.maxRows, "进度行数有界")
let reloaded = PracticeProgress(url: URL(fileURLWithPath: NSTemporaryDirectory() + "lampyris-practice-test" + "/practice.tsv"))
require(reloaded.rows.count == tmpProgress.rows.count, "进度可重载")
let phrase = WubiLearning.lookup("中华人民共和国")
require(phrase?.code == "kwwl" && phrase?.characters.count == 7, "long phrase summary and every character")
require(phrase?.characters[3].code == "nav" && phrase?.characters[3].recognition?.key == "V", "verified long-word decomposition")
require(WubiLearning.lookup("你好")?.code == "wqvb", "phrase code")
require(WubiLearning.lookup("😀")?.code == nil, "missing code")
require(WubiLearning.lookup("是")?.characters[0].roots.isEmpty == true, "missing explanation remains explicit")
require(WubiLearning.lookup("人")?.characters[0].category == "key_name", "key-name category")
for input in ["", "你\t好", String(repeating: "你", count: 86)] {
    require(WubiLearning.lookup(input) == nil, "bounded invalid input")
}
print("PASS wubi-learning: real Rust ABI, ownership, full codes, readable roots, long words, missing data and bounds")
LocalAcceptanceEvidence.record("learning.facts", expected: "真实ABI返回完整码/字根/识别码，缺失说明不猜写", actual: ["你_code": single?.code ?? "", "你_roots": single?.characters.first?.roots.map(\.text) ?? [], "我_code": me?.code ?? "", "long_word_characters": phrase?.characters.count ?? 0])

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let privateRoot = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
require(ime_config_init(privateRoot.appendingPathComponent("config.toml").path) == IME_OK, "private config")
require(!ImeConfig.bool("candidate.show_wubi_learning"), "collapsed default from schema")
require(ImeConfig.string("hotkey.toggle_wubi_learning") == "alt+l", "learning shortcut default from schema")
require(ImeConfig.string("hotkey.open_practice") == "alt+k", "practice shortcut default from schema, actual=\(ImeConfig.string("hotkey.open_practice") ?? "nil")")
let practiceHotkey = ImeConfig.hotkey("hotkey.open_practice")
require(practiceHotkey.kind == 2, "practice hotkey parsed as chord")
if let optionK = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option],
                                  timestamp: 0, windowNumber: 0, context: nil,
                                  characters: "\u{2DA}", charactersIgnoringModifiers: "k",
                                  isARepeat: false, keyCode: 40) {
    require(practiceHotkey.matches(optionK), "⌥K 必须匹配练习热键（实际配置 \(ImeConfig.string("hotkey.open_practice") ?? "nil")）")
}
LocalAcceptanceEvidence.record("learning.defaults", expected: "Schema默认收起，学习快捷键alt+l", actual: ["shown": ImeConfig.bool("candidate.show_wubi_learning"), "shortcut": ImeConfig.string("hotkey.toggle_wubi_learning") ?? ""])
require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "save display preference")
let window = CandidateWindow()
let area = NSRect(x: 0, y: 0, width: 1000, height: 800)
let focusedValues = [ImeCandidate(text: "我们", code: "wuw", source: .codeTable, isPrefix: false),
                     ImeCandidate(text: "我国", code: "tlg", source: .codeTable, isPrefix: false)]
window.update(candidates: focusedValues, selectedIndex: 0)
window.layout(at: .zero, within: area)
window.toggleLearningDetailsForTesting()
window.update(candidates: focusedValues, selectedIndex: 1)
window.layout(at: .zero, within: area)
require(window.learningSummaryForTesting.contains(WubiLearning.lookup("我国")?.code?.uppercased() ?? "missing"),
        "learning summary follows focused candidate")
require(window.learningDetailsExpandedForTesting, "focus change keeps learning details open")
window.update(candidates: focusedValues, selectedIndex: 999)
require(window.selectedCandidateIndexForTesting == 1, "learning focus index is clamped")
window.hide()
func snapshot(_ name: String) {
    guard let image = window.renderSnapshotForTesting(), let data = image.representation(using: .png, properties: [:]) else { exit(1) }
    do { try data.write(to: output.appendingPathComponent(name + ".png")) } catch { exit(1) }
}
for theme in ["light", "dark"] {
    require(ImeConfig.setString("appearance.theme", theme), "theme")
    for text in ["你", "我", "我们", "特点", "突然", "投入", "中华人民共和国", "😀"] {
        window.update(candidates: [ImeCandidate(text: text, code: "ni", source: .pinyin, isPrefix: false)], input: "ni")
        window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
        require(window.learningVisibleForTesting && !window.permitsKeyboardFocusForTesting && area.contains(window.frame), "mode-independent non-key bounded extension")
        snapshot(text + "-" + theme)
        if text == "中华人民共和国" {
            window.toggleLearningDetailsForTesting()
            window.toggleLearningCharacterForTesting(0)
            window.toggleLearningCharacterForTesting(3)
            require(area.contains(window.frame) && window.frame.height <= 428, "bounded long-word detail")
            snapshot("long-expanded-" + theme)
        }
    }
}
require(ImeConfig.setToml("candidate.show_wubi_learning", "false"), "hide preference")
LocalAcceptanceEvidence.record("learning.display", expected: "亮暗八类候选可显示学习区，七字逐字展开有界且不夺焦点", actual: ["visible": window.learningVisibleForTesting, "keyboard_focus": window.permitsKeyboardFocusForTesting, "frame": NSStringFromRect(window.frame)])
window.update(candidates: [ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)], input: "wq")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
require(!window.learningVisibleForTesting, "preference hides extension")
window.hide()
require(!window.learningVisibleForTesting, "hidden panel clears learning")
LocalAcceptanceEvidence.record("learning.hidden", expected: "关闭偏好/隐藏面板清理学习内容", actual: window.learningVisibleForTesting)
print("PASS wubi-learning-presentation: private schema, mode-independent extension, long-word disclosure, bounded details, light/dark and stale clearing")

// Exercise the actual default through the session, without rebinding it.
let table = privateRoot.appendingPathComponent("learning-test.tsv")
try "wq\t你\t10\nwqiy\t你\t10\n".write(to: table, atomically: true, encoding: .utf8)
guard let session = ImeSession(wubiPath: table.path, pinyinCharsPath: nil, pinyinWordsPath: nil) else { exit(1) }
session.setMode("wubi")
_ = session.feed(119); _ = session.feed(113)
let originalBuffer = session.buffer
let originalPage = session.pageIndex
let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option],
    timestamp: 0, windowNumber: 0, context: nil, characters: "L", charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37)!
require(session.shortcut(event, persistMode: true) == .handled && ImeConfig.bool("candidate.show_wubi_learning"), "shortcut toggles same persisted preference")
require(session.buffer == originalBuffer && session.pageIndex == originalPage, "shortcut preserves composition and page")
LocalAcceptanceEvidence.record("learning.shortcut", expected: "合成学习快捷键切换同一偏好，保留wq和页码；非物理键盘", actual: ["buffer": session.buffer, "page": session.pageIndex, "shown": ImeConfig.bool("candidate.show_wubi_learning")])
let oldWidth = session.isFullWidth
let oldWidthEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift],
    timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
require(session.shortcut(oldWidthEvent, persistMode: true) == .unmatched && session.isFullWidth == oldWidth, "shift-space no longer toggles by default")
let spaceEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option],
    timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
require(session.shortcut(spaceEvent, persistMode: true) == .unmatched && session.isFullWidth == oldWidth,
    "option-space no longer toggles by default (ADR-210)")
let widthEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option],
    timestamp: 0, windowNumber: 0, context: nil, characters: "F", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!
require(session.shortcut(widthEvent, persistMode: true) == .handled && session.isFullWidth != oldWidth, "new width shortcut toggles")
require(session.shortcut(widthEvent, persistMode: true) == .handled && session.isFullWidth == oldWidth, "new width shortcut restores")
LocalAcceptanceEvidence.record("learning.width-shortcut", expected: "shift-space与option-space都不切换；option-f双向切换恢复", actual: ["restored": session.isFullWidth == oldWidth, "buffer": session.buffer])

// 系统 ⌃Space 切换输入法时，仍按住的空格会被重投向新输入法，而修饰键已是“切完再按 Shift”的状态。
// 这类时间戳早于最近修饰键变化的旧事件不能当成 ⌃⇧Space，否则单按 Shift 会误切全/半角（报告 074）。
func syntheticKey(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags, _ stamp: TimeInterval,
                  _ code: UInt16, _ chars: String) -> NSEvent {
    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: stamp, windowNumber: 0,
        context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
}
let widthBeforeReplay = session.isFullWidth
session.noteModifierChange(syntheticKey(.flagsChanged, [.option], 1000.0, 58, ""))
let replayedF = syntheticKey(.keyDown, [.option], 999.94, 3, "f")
require(session.shortcut(replayedF, persistMode: true) == .unmatched && session.isFullWidth == widthBeforeReplay,
    "f replayed from before the modifier change is not a chord")
let settledF = syntheticKey(.keyDown, [.option], 1000.05, 3, "f")
require(session.shortcut(settledF, persistMode: true) == .handled && session.isFullWidth != widthBeforeReplay,
    "f pressed after the modifiers still fires the chord")
require(session.shortcut(settledF, persistMode: true) == .handled && session.isFullWidth == widthBeforeReplay,
    "width restored after the settled chord")
LocalAcceptanceEvidence.record("learning.stale-chord", expected: "系统切换后重投递的旧事件不触发⌥F；修饰键先到位时仍生效", actual: ["ignored_replay": session.isFullWidth == widthBeforeReplay])

require(!ImeConfig.setString("hotkey.toggle_wubi_learning", "alt+m"), "shortcut collision rejected")
LocalAcceptanceEvidence.record("learning.conflict", expected: "拒绝与模式快捷键冲突的学习绑定", actual: ImeConfig.string("hotkey.toggle_wubi_learning") ?? "missing")
print("PASS learning shortcut: same preference, composition preserved, conflict rejected")

require(ImeConfig.setToml("candidate.show_wubi_learning", "false"), "matched collapsed")
let matched = ["你", "你好", "您", "拟"].map { ImeCandidate(text: $0, code: "wq", source: .codeTable, isPrefix: false) }
require(ImeConfig.setString("appearance.theme", "light"), "matched theme")
window.update(candidates: matched, pageIndex: 0, pageCount: 12, input: "wq")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
let stableWidth = window.frame.width
require(stableWidth == 400, "reviewed standard candidate width")
snapshot("matched-collapsed-light")
require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "show stable learning")
window.update(candidates: matched, pageIndex: 0, pageCount: 12, input: "wq")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
require(window.frame.width == stableWidth, "learning preserves candidate body width")
LocalAcceptanceEvidence.record("learning.body-width", expected: "开关学习区不改变400pt候选主体宽度", actual: ["before": stableWidth, "after": window.frame.width])
snapshot("matched-learning-light")
window.hide()

require(WubiLearning.lookup(String(repeating: "人", count: 85))?.characters.count == 85, "legal long word has teaching data")
require(WubiLearning.lookup(String(repeating: "a", count: 256))?.characters.count == 256, "legal byte boundary")
require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "lifecycle visibility")
window.update(candidates: [ImeCandidate(text: "中华人民共和国", code: "kwwl", source: .phrase, isPrefix: false)], input: "kwwl")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
guard let oldAction = window.learningActionForTesting else { exit(1) }
window.hide()
require(oldAction.target == nil && oldAction.action == nil, "old learning actions invalidated")
LocalAcceptanceEvidence.record("learning.stale", expected: "隐藏后旧学习按钮target/action失效", actual: ["target_nil": oldAction.target == nil, "action_nil": oldAction.action == nil])
for theme in ["light", "dark"] {
    require(ImeConfig.setString("appearance.theme", theme), "learning contrast theme")
    window.update(candidates: [ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)], input: "wq")
    window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
    require(window.learningTextContrastForTesting >= 4.5, "learning text contrast")
    LocalAcceptanceEvidence.record("learning.contrast." + theme, expected: "实际语义文字/背景对比度>=4.5", actual: window.learningTextContrastForTesting)
}
window.hide()

require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "stable detail preference")
window.update(candidates: [ImeCandidate(text: "中华人民共和国", code: "kwwl", source: .phrase, isPrefix: false)], input: "kwwl")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
let stableAction = window.learningActionForTesting
var selectionCalls = 0
window.onSelect = { _ in selectionCalls += 1 }
let collapsedLearningHeight = window.frame.height
window.toggleLearningDetailsForTesting()
require(window.learningActionForTesting === stableAction, "summary AX identity retained")
require(window.frame.height > collapsedLearningHeight && area.contains(window.frame),
        "disclosure immediately reflows at unchanged screen size")
window.scrollLearningForTesting(45)
let origin = window.learningScrollOriginForTesting
window.toggleLearningCharacterForTesting(5)
require(abs(window.learningScrollOriginForTesting.y - origin.y) < 1 && selectionCalls == 0, "disclosure preserves scroll without selection")
LocalAcceptanceEvidence.record("learning.scroll", expected: "逐字披露保留滚动和摘要AX对象，不触发选词", actual: ["before_y": origin.y, "after_y": window.learningScrollOriginForTesting.y, "selection_calls": selectionCalls, "same_action": window.learningActionForTesting === stableAction])
let longCandidates = (0..<9).map { _ in ImeCandidate(text: String(repeating: "中华人民共和国", count: 8), code: "kwwl", source: .phrase, isPrefix: false) }
let tight = NSRect(x: 0, y: 0, width: 500, height: 500)
require(ImeConfig.setToml("candidate.show_wubi_learning", "false"), "body baseline")
window.update(candidates: longCandidates, input: "kwwl")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: tight)
let baselineViewport = window.candidateViewportForTesting
require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "body with teaching")
window.update(candidates: longCandidates, input: "kwwl")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: tight)
window.toggleLearningDetailsForTesting()
require(window.candidateViewportForTesting == baselineViewport && tight.contains(window.frame), "teaching cannot steal candidate viewport")
LocalAcceptanceEvidence.record("learning.viewport", expected: "长候选开关学习区保持主体视口，组合/焦点及滚动约束通过", actual: ["baseline_viewport": NSStringFromSize(baselineViewport), "current_viewport": NSStringFromSize(window.candidateViewportForTesting)])
window.hide()

// Reproduce the reported seven-candidate header and teaching layout at the same time.
require(ImeConfig.setString("appearance.theme", "light"), "feedback fixture appearance")
let feedbackCandidates = ["我", "我们", "我国", "特别", "特点", "突然", "投入"].map {
    ImeCandidate(text: $0, code: "tr", source: .codeTable, isPrefix: false)
}
window.update(candidates: feedbackCandidates, pageIndex: 0, pageCount: 30, input: "tr")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
let headerFrames = window.pageFramesForTesting
require(window.learningVisibleForTesting && window.pageStateForTesting.text == "1/30"
    && abs(headerFrames[0].midY - headerFrames[1].midY) < 0.5
    && abs(headerFrames[1].midY - headerFrames[2].midY) < 0.5, "reported page header and teaching together")
snapshot("feedback-tr-light")
window.hide()
