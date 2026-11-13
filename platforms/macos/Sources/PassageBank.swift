import AppKit

/// 文章跟打短句库（ADR-347，项目自编，CC-BY-SA-4.0）。
///
/// 只用于本机练习：按顺序循环出题，不联网、不上报、不参与候选排序。
enum PassageBank {
    static let sentences: [String] = [
        "今天天气很好。",
        "我们一起去公园散步。",
        "请把窗户关上。",
        "他每天早上六点起床。",
        "这本书我已经看完了。",
        "周末我们去爬山吧。",
        "你喜欢喝什么茶？",
        "妈妈做的菜真好吃。",
        "会议室在二楼左边。",
        "请稍等一下，我马上回来。",
        "外面下雨了，记得带伞。",
        "这个问题我们再讨论一次。",
        "文件已经发到你的邮箱。",
        "他说话的声音很轻。",
        "路边的花开了。",
        "我坐地铁去上班。",
        "晚上八点开始看电影。",
        "请把桌子擦干净。",
        "孩子们在操场上跑步。",
        "明天上午有一个会议。",
        "这家店的面条不错。",
        "我还没想好去哪里。",
        "请帮我关一下灯。",
        "他正在学习新的技术。",
        "天气转凉了，多穿点衣服。",
        "这个问题不难解决。",
        "我们需要更多的时间。",
        "请把门轻轻带上。",
        "她喜欢听古典音乐。",
        "周末在家里休息。",
        "这本字典很实用。",
        "热水在厨房的壶里。",
        "请把地址写清楚。",
        "他每周都去游泳。",
        "这家公司去年成立了。",
        "我先把作业写完。",
        "你什么时候有空？",
        "会议改到下周三。",
        "请把资料整理好。",
        "他们正在讨论方案。",
        "外面风很大。",
        "我今天不喝咖啡。",
        "请把这句话再读一遍。",
        "图书馆下午五点关门。",
        "他刚搬到新的小区。",
        "我们坐火车去旅行。",
        "记得把充电器带上。",
        "这道题我算了两遍。",
        "请把手机调成静音。",
        "他习惯早起跑步。",
        "我们下午三点见。",
        "这个季节水果很多。",
        "请把发票放进包里。",
        "她正在准备考试。",
        "房间里的灯坏了。",
        "我们去超市买点菜。",
        "请把文件保存好。",
        "他说话很讲道理。",
        "我昨天看了一场球赛。",
        "路上注意安全。",
        "请把序号写对。",
        "这个想法值得试一试。",
        "他喜欢在河边钓鱼。",
        "我们明天再确认。",
        "请把窗帘拉开。",
        "她每天写一页日记。",
        "这个周末要加班。",
        "请把邮件转发给我。",
        "他正在修理自行车。",
        "冬天白天比较短。",
        "我们去楼下走走吧。",
        "请把垃圾带下去。",
        "他刚从外地回来。",
        "这个方案还需要修改。",
        "我习惯用键盘输入。",
        "请把时间安排一下。",
        "孩子们喜欢看动画。",
        "他做事一向很认真。",
        "请把这个问题记下来。",
        "我们下个月搬新家。",
        "这家银行的营业时间很长。",
        "请把座位让给老人。",
        "他每天读半小时书。",
        "我把钥匙放在桌上了。",
        "请把窗户关好再走。",
        "我们沿着河边散步。",
        "他正在学习做菜。",
        "这个周末天气不错。",
        "请把名字写在第一行。",
        "她喜欢种花种草。",
        "我们约好在地铁站见面。",
        "请把电视声音调小一点。",
        "他昨天很晚才睡。",
        "这个办法简单有效。",
        "请把衣服晾到阳台上。",
        "我们一起做晚饭吧。",
        "他正在等一个电话。",
        "请把行李放进行李箱。",
        "今天的任务完成了。",
        "明天记得早起。",
    ]

    /// 下一句：顺序循环，保证不连续重复。
    static func next(after current: String?) -> String {
        guard let current, let index = sentences.firstIndex(of: current) else {
            return sentences.first ?? ""
        }
        return sentences[(index + 1) % sentences.count]
    }

    struct Result {
        let correct: Int
        let total: Int
        let firstMismatch: Int?
        let expected: Character?
        let typed: Character?

        var isExact: Bool { firstMismatch == nil && correct == total }
    }

    /// 去掉所有空白后逐字比较；标点也算一个字。
    static func judge(target: String, typed: String) -> Result {
        func compact(_ text: String) -> [Character] {
            text.filter { !$0.isWhitespace }
        }
        let expected = compact(target)
        let actual = compact(typed)
        var correct = 0
        var mismatch: Int?
        for index in expected.indices {
            if index < actual.count, expected[index] == actual[index] {
                correct += 1
            } else if mismatch == nil {
                mismatch = index
            }
        }
        if mismatch == nil, actual.count > expected.count {
            mismatch = expected.count
        }
        return Result(
            correct: correct,
            total: expected.count,
            firstMismatch: mismatch,
            expected: mismatch.flatMap { $0 < expected.count ? expected[$0] : nil },
            typed: mismatch.flatMap { $0 < actual.count ? actual[$0] : nil }
        )
    }
}
