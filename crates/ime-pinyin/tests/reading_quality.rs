use ime_core::{Engine, EngineOptions};
use ime_pinyin::{PinyinEngine, TablePinyinBackend};

#[test]
fn shipped_common_readings_stay_on_first_page() {
    let backend = TablePinyinBackend::from_tsv(
        include_str!("../../../data/generated/pinyin-chars.tsv"),
        include_str!("../../../data/generated/pinyin-core.tsv"),
        "reading-quality",
    )
    .unwrap();
    let mut engine = PinyinEngine::new(Box::new(backend), 32);
    engine.configure(&EngineOptions {
        fuzzy: true,
        auto_commit: false,
        z_wildcard: false,
    });
    // Common alternative readings must remain reachable while weak readings
    // no longer displace the ordinary targets for xian and xing.
    for (input, target, max_rank) in [
        ("xian", "先", 1),
        ("jian", "见", 1),
        ("sheng", "省", 1),
        ("xing", "行", 1),
        ("hang", "行", 9),
        ("chang", "长", 9),
        ("zhang", "长", 9),
        ("zhong", "重", 9),
        ("chong", "重", 9),
        ("le", "乐", 9),
        ("yue", "乐", 9),
        ("dou", "都", 9),
        ("du", "都", 9),
        ("de", "地", 9),
        ("dei", "得", 9),
        ("hai", "还", 9),
        ("huan", "还", 9),
        ("bian", "便", 9),
        ("pian", "便", 9),
        ("jiang", "降", 9),
        ("xiang", "降", 9),
        ("jue", "觉", 9),
        ("jiao", "觉", 9),
        ("bao", "薄", 9),
        ("bo", "薄", 9),
        ("ni", "你", 1),
        ("wo", "我", 1),
        ("shi", "是", 1),
        ("yu", "与", 1),
        ("hao", "好", 1),
        ("wang", "王", 1),
        ("xi'an", "西安", 1),
        ("nv", "女", 1),
        ("lv", "绿", 9),
        ("lve", "略", 9),
        ("jsj", "计算机", 1),
        ("jisuanji", "计算机", 1),
    ] {
        let result = engine.convert(input, 256);
        let rank = result
            .candidates
            .iter()
            .position(|c| c.text == target)
            .map(|index| index + 1);
        assert!(
            rank.is_some_and(|rank| rank <= max_rank),
            "{input} → {target}: rank {rank:?}, expected <= {max_rank}"
        );
    }
}
