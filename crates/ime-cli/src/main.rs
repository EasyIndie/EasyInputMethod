//! 萤火虫输入法 CLI：P1-M0 的开发/测试原型。
//!
//! 演示竖切：五笔码 → 候选 → 上屏 → 模式切换。

#![forbid(unsafe_code)]

use std::io::{self, Write};

use ime_core::{InputMode, Session};
use ime_table::{CodeTableEngine, Table};

/// M0 用小型示例码表验证竖切；正式自建码表在 P1-M1 接入。
fn sample_table() -> Table {
    let singles: &[(&str, &str, i32)] = &[
        ("g", "一", 100),
        ("gggg", "一", 100),
        ("gggg", "王", 90),
        ("q", "我", 100),
        ("trnt", "我", 100),
        ("wq", "你", 100),
        ("wqiy", "你", 100),
        ("vb", "好", 90),
        ("gg", "五", 80),
        ("k", "中", 100),
        ("khk", "中", 100),
        ("l", "国", 100),
        ("lgyi", "国", 100),
        ("w", "人", 100),
        ("r", "的", 100),
        ("j", "是", 100),
        ("llll", "田", 80),
        ("oooo", "火", 80),
        ("mmmm", "山", 80),
    ];
    let phrases: &[(&str, &str, i32)] = &[
        ("kwwl", "中华人民共和国", 100),
        ("ltif", "输入法", 100),
        ("khyy", "中文", 95),
        ("ggtt", "五笔", 90),
        ("gtpg", "五笔字型", 85),
    ];

    let mut table = Table::new();
    for (code, text, weight) in singles.iter().chain(phrases.iter()) {
        table.insert(code, text, *weight);
    }
    table.finalize();
    table
}

fn print_candidates(session: &Session) {
    let candidates = session.candidates();
    if candidates.is_empty() {
        println!("  （无候选）buffer={:?}", session.buffer());
        return;
    }
    let shown: Vec<String> = candidates
        .iter()
        .take(9)
        .enumerate()
        .map(|(i, c)| {
            let mark = if c.is_prefix { "…" } else { "" };
            format!("{}.{}{}", i + 1, c.text, mark)
        })
        .collect();
    println!("  {}", shown.join("  "));
}

fn main() {
    let mut session = Session::new(InputMode::Mixed);
    session.set_wubi_engine(Box::new(CodeTableEngine::new(sample_table(), 4)));

    println!("萤火虫输入法 ime-cli（P1-M0 原型）");
    println!(
        "  输入五笔码回车上屏；:lookup <码> 只看候选；:mode [mixed|wubi|pinyin]；:help；:quit"
    );

    let stdin = io::stdin();
    loop {
        print!("{}> ", session.mode());
        io::stdout().flush().ok();

        let mut line = String::new();
        if stdin.read_line(&mut line).is_err() {
            break;
        }
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        match line {
            ":quit" | ":q" => break,
            ":help" => {
                println!(
                    "  命令：<五笔码> 回车上屏 | :lookup <码> | :mode [mixed|wubi|pinyin] | :quit"
                );
                continue;
            }
            ":mode" => {
                println!("  当前模式: {}", session.mode());
                continue;
            }
            _ => {}
        }

        if let Some(mode) = line.strip_prefix(":mode ") {
            match mode.trim().parse::<InputMode>() {
                Ok(m) => {
                    session.set_mode(m);
                    println!("  已切换到 {m}");
                }
                Err(_) => println!("  未知模式（mixed|wubi|pinyin）"),
            }
            continue;
        }

        if let Some(code) = line.strip_prefix(":lookup ") {
            for ch in code.chars() {
                session.handle_key(ch);
            }
            print_candidates(&session);
            session.cancel();
            continue;
        }

        // 普通输入：逐字喂入
        for ch in line.chars() {
            session.handle_key(ch);
        }

        if session.composing() && !session.candidates().is_empty() {
            print_candidates(&session);
            session.handle_key(' ');
            println!("  上屏: {}", session.committed());
        } else if session.composing() {
            print_candidates(&session);
            session.cancel();
        } else if !session.committed().is_empty() {
            println!("  上屏: {}", session.committed());
        }
    }

    println!("再见。");
}
