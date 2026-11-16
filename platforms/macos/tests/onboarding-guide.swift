import Cocoa
import ime

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8)); exit(1)
}
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
guard ime_config_init(root.appendingPathComponent("config.toml").path) == IME_OK else {
    fail("private config")
}
let steps = OnboardingGuide.steps()
guard steps.count == 6 else { fail("step count \(steps.count)") }
guard steps.allSatisfy({ !$0.title.isEmpty && !$0.summary.isEmpty && !$0.body.isEmpty && !$0.symbol.isEmpty }) else {
    fail("empty step")
}
guard steps.allSatisfy({ !$0.bullets.isEmpty && $0.bullets.count <= 3 }) else {
    fail("bullets should be 1...3 short lines")
}
guard steps[1].body.contains("⌥"), steps[2].body.contains("⌥"), steps[4].body.contains("⌥") else {
    fail("dynamic hotkeys missing")
}
// 结构化：快捷键单独成键帽，不串进句子（ADR-364）。
guard steps[1].bullets.first?.keys.first?.hasPrefix("⌥") == true else { fail("mode hotkey keycap") }
guard steps[4].bullets.first?.keys.first?.hasPrefix("⌥") == true else { fail("symbols hotkey keycap") }
guard steps[0].bullets.allSatisfy({ $0.keys.isEmpty }) else { fail("welcome step has no keys") }

let guide = OnboardingWindow.shared
guide.prepareForTesting()
guard guide.stepCountForTesting == 6 else { fail("window steps") }
guide.updateForTesting()
guard guide.currentTitleForTesting == "欢迎使用萤火虫" else { fail("first title") }
guard guide.currentBodyForTesting.contains("五笔优先") else { fail("first body") }
guide.nextForTesting()
guard guide.currentTitleForTesting == "切换输入状态" else { fail("second title") }
guard guide.currentBodyForTesting.contains("混合") else { fail("second body") }
guide.nextForTesting()
guard guide.currentTitleForTesting == "学习区" else { fail("third title") }
guide.backForTesting()
guard guide.currentTitleForTesting == "切换输入状态" else { fail("back title") }
guard let panel = guide.panelForTesting else { fail("panel") }
guard panel.title.hasPrefix("萤火虫使用指南") else { fail("panel title \(panel.title)") }
print("PASS onboarding-guide: steps, dynamic hotkeys, window navigation")
