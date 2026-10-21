//! Check packaged vocabulary through real engine merging and numeric selection.
use ime_core::{EngineOptions, InputMode, KeyOutcome, Session};
use ime_pinyin::{PinyinEngine, TablePinyinBackend};
use ime_table::{CodeTableEngine, Table};

#[test]
fn common_input_terms_are_reachable_and_submit_the_displayed_candidate() {
    let wubi = include_str!("../../../data/generated/wubi86-core.tsv");
    let pinyin = include_str!("../../../data/generated/pinyin-core.tsv");
    let backend = TablePinyinBackend::from_tsv(
        include_str!("../../../data/generated/pinyin-chars.tsv"),
        pinyin,
        "core-terms",
    )
    .unwrap();
    let mut session = Session::new(InputMode::Mixed);
    session.set_wubi_engine(Box::new(CodeTableEngine::new(
        Table::from_tsv(wubi).unwrap(),
        4,
    )));
    session.set_pinyin_engine(Box::new(PinyinEngine::new(Box::new(backend), 32)));
    session.configure_engines(&EngineOptions {
        auto_commit: false,
        fuzzy: true,
        z_wildcard: false,
    });
    for mode in [InputMode::WubiOnly, InputMode::PinyinOnly, InputMode::Mixed] {
        session.set_mode(mode);
        let baseline = [
            "输入法",
            "五笔",
            "拼音",
            "词库",
            "候选",
            "开发者",
            "人工智能",
        ];
        let domain = include_str!("../../../data/domain-vocabulary.tsv")
            .lines()
            .filter(|line| !line.starts_with('#') && !line.is_empty())
            .map(|line| line.split('\t').nth(1).unwrap());
        for text in baseline.into_iter().chain(domain) {
            for (table, is_pinyin) in [(wubi, false), (pinyin, true)] {
                if (mode == InputMode::WubiOnly && is_pinyin)
                    || (mode == InputMode::PinyinOnly && !is_pinyin)
                {
                    continue;
                }
                let code = table
                    .lines()
                    .filter(|line| !line.starts_with('#'))
                    .find_map(|line| {
                        let mut columns = line.split('\t');
                        let code = columns.next()?;
                        (columns.next()? == text).then_some(code)
                    })
                    .unwrap_or_else(|| panic!("词表缺少 {text}"));
                let inputs = if is_pinyin {
                    vec![code.replace(' ', ""), code.replace(' ', "'")]
                } else {
                    vec![code.into()]
                };
                for input in inputs {
                    session.cancel();
                    for ch in input.chars() {
                        assert_eq!(session.handle_key(ch), KeyOutcome::Consumed);
                    }
                    let mut found = false;
                    for _ in 0..session.page_count() {
                        if let Some(index) = session
                            .candidates()
                            .iter()
                            .position(|candidate| candidate.text == text)
                        {
                            assert_eq!(
                                session.handle_key(char::from(b'1' + index as u8)),
                                KeyOutcome::Committed(text.into())
                            );
                            found = true;
                            break;
                        }
                        session.page(1);
                    }
                    assert!(found, "{mode:?}: {input} → {text} 不可达");
                }
            }
        }
    }
}
