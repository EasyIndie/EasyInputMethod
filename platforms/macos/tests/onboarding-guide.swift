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
guard steps.count == 7 else { fail("step count \(steps.count)") }
guard steps.allSatisfy({ !$0.title.isEmpty && !$0.body.isEmpty && !$0.symbol.isEmpty }) else {
    fail("empty step")
}
guard steps[1].body.contains("⌥"), steps[2].body.contains("⌥"), steps[5].body.contains("⌥") else {
    fail("dynamic hotkeys missing")
}

let guide = OnboardingWindow.shared
guide.prepareForTesting()
guard guide.stepCountForTesting == 7 else { fail("window steps") }
guide.updateForTesting()
guard guide.currentTitleForTesting == "欢迎使用萤火虫" else { fail("first title") }
guard guide.currentBodyForTesting.contains("五笔优先") else { fail("first body") }
guide.nextForTesting()
guard guide.currentTitleForTesting == "切换输入状态" else { fail("second title") }
guard guide.currentBodyForTesting.contains("切换模式") else { fail("second body") }
guide.nextForTesting()
guard guide.currentTitleForTesting == "学习区" else { fail("third title") }
guide.backForTesting()
guard guide.currentTitleForTesting == "切换输入状态" else { fail("back title") }
guard let panel = guide.panelForTesting else { fail("panel") }
guard panel.title.hasPrefix("萤火虫使用指南") else { fail("panel title \(panel.title)") }
print("PASS onboarding-guide: steps, dynamic hotkeys, window navigation")
