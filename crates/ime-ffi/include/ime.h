/* 萤火虫输入法 — 窄 C ABI 头文件。
 *
 * 会话 ABI 见 docs/技术方案.md §5.3；配置 ABI 见 docs/配置架构.md §9。
 * 契约：
 *   - 纯 C；不透明句柄；UTF-8；错误用 int32_t 返回码（0=成功，负数=错误）；
 *   - 会话句柄线程绑定（同一会话仅限单线程）；配置接口线程安全；
 *   - 借用指针（候选 / 快照 / Schema）调用方不得释放。
 */
#ifndef IME_H
#define IME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── 返回码 ─────────────────────────────────────────── */
#define IME_OK               0
#define IME_ERR_NULL        -1  /* 空指针参数 */
#define IME_ERR_INVALID_UTF8 -2  /* 非法 UTF-8 */
#define IME_ERR_INVALID_INPUT -3 /* 值非法（类型/范围/枚举） */
#define IME_ERR_UNKNOWN_KEY -4  /* 未知配置键 */
#define IME_ERR_IO          -5  /* 文件 IO 错误 */
#define IME_ERR_PARSE       -6  /* 语法/解析错误 */
#define IME_ERR_LOCKED      -7  /* 配置文件被锁 */
#define IME_ERR_PANIC       -8  /* 内部 panic（绝不应发生） */
#define IME_ERR_NOT_FOUND   -9  /* 未找到精确用户词条 */

/* ── ABI 版本 ───────────────────────────────────────── */
/* 宿主启动时应校验；主版本不匹配应拒绝使用（避免结构体布局不一致）。 */
uint32_t ime_abi_version(void);

/* ── 候选来源 ───────────────────────────────────────── */
#define IME_SOURCE_CODE_TABLE 0
#define IME_SOURCE_PINYIN     1
#define IME_SOURCE_PHRASE     2

/* ── ime_session_key 成功时的按键结果 ───────────────── */
#define IME_KEY_CONSUMED     0  /* 键被消费，候选已更新（== IME_OK） */
#define IME_KEY_COMMITTED    1  /* 已上屏，随后取 ime_session_commit */
#define IME_KEY_PASS_THROUGH 2  /* 与本输入法无关，宿主应透传 */

/* ── 不透明句柄 ─────────────────────────────────────── */
typedef struct ImeSession ImeSession;
typedef struct ImeConfig ImeConfig;

/* ── 库所有的字符串（调用方负责 ime_string_free） ──────── */
typedef struct ImeString {
    const char* data;   /* NUL 结尾 UTF-8；空串为 ""，绝不 NULL */
    uint32_t    len;    /* 字节长度（不含结尾 NUL） */
} ImeString;

/* ── 候选（借用自会话，下次会话变更前有效） ────────────── */
typedef struct ImeCandidate {
    const char* text;    /* 候选文本（UTF-8） */
    const char* code;    /* 五笔码或拼音（UTF-8） */
    int32_t     weight;
    int32_t     source;  /* IME_SOURCE_* */
    int32_t     is_prefix; /* 0/1 */
} ImeCandidate;

typedef struct ImeCandidates {
    const ImeCandidate* items;
    uint32_t            len;
} ImeCandidates;

/* ── 会话 ABI（线程绑定） ────────────────────────────── */
ImeSession*  ime_session_new(void);
ImeSession*  ime_session_new_with_data(const char* wubi_path,
                                       const char* pinyin_chars_path,
                                       const char* pinyin_words_path);
void         ime_session_free(ImeSession* session);
int32_t      ime_session_key(ImeSession* session, uint32_t codepoint); /* IME_KEY_* 或负错误码 */
const char*  ime_session_buffer(ImeSession* session);   /* 借用组合缓冲区（UTF-8） */
int32_t      ime_session_toggle_english(ImeSession* session);
int32_t      ime_session_toggle_width(ImeSession* session);
int32_t      ime_session_is_english(ImeSession* session);
int32_t      ime_session_is_full_width(ImeSession* session); /* 1=全角，0=半角，-1=错误 */
int32_t      ime_session_dictionary_error(ImeSession* session);
ImeString    ime_session_dictionary_error_message(ImeSession* session); /* 拥有式字符串，调用ime_string_free */
int32_t      ime_session_dictionary_add(ImeSession* session, const char* scheme, const char* code, const char* text);
int32_t      ime_session_dictionary_remove(ImeSession* session, const char* scheme, const char* code, const char* text);
int32_t      ime_session_dictionary_import(ImeSession* session, const char* path);
int32_t      ime_session_dictionary_export(ImeSession* session, const char* path);
int32_t      ime_session_configure(ImeSession* session);
int32_t      ime_session_set_variant_data(ImeSession* session, const char* path); /* 注入简→繁表 */
int32_t      ime_session_mode(ImeSession* session); /* mixed=0 wubi=1 pinyin=2 */
int32_t      ime_session_set_mode(ImeSession* session, const char* mode);
ImeCandidates ime_session_candidates(ImeSession* session);
int32_t      ime_session_select(ImeSession* session, int32_t index);
int32_t      ime_session_page(ImeSession* session, int32_t delta);
int32_t      ime_session_set_page_size(ImeSession* session, int32_t size);
int32_t      ime_session_page_index(ImeSession* session);
int32_t      ime_session_page_count(ImeSession* session);
/* 只读反查：有效文本 <=256 UTF-8 字节；未知为空，非法/NULL 返回 NULL；string_free 释放。 */
ImeString    ime_session_reverse_lookup(const ImeSession* session, const char* text);
/* Read-only Wubi teaching TSV v1, <=256 UTF-8 bytes, payload <=64KiB; NULL invalid; owned/string_free. */
ImeString    ime_wubi_learning(const char* text);
ImeString    ime_session_commit(ImeSession* session);
void         ime_session_focus_out(ImeSession* session);
void         ime_session_reset(ImeSession* session);
void         ime_string_free(ImeString s);

int32_t ime_session_variant_error(const ImeSession* session); /* 懒加载资源错误，不触发加载 */
int32_t ime_session_is_traditional(const ImeSession* session); /* 有效繁体状态，非请求偏好 */

/* ── 配置 ABI（线程安全） ────────────────────────────── */
int32_t          ime_config_init(const char* path);  /* 宿主设定配置路径，须最先调用 */
const ImeConfig* ime_config_snapshot(void);   /* 借用；勿释放；按线程保留，该线程下次调用前有效 */
const char*      ime_config_get(const char* key); /* 字符串形式；NULL=未知/错误 */
typedef struct ImeHotkey {
    uint32_t kind;       /* 0=关闭 1=单Shift 2=组合键 */
    uint32_t modifiers;  /* ctrl=1 alt=2 shift=4 cmd=8 */
    uint32_t key;        /* ASCII码点，space=32 */
} ImeHotkey;
ImeHotkey        ime_config_hotkey(const char* key); /* 规范表示，错误/未知键返回关闭 */
const char*      ime_config_last_error(void);      /* 最近一次加载/重载失败原因；空串=无错误；借用 */

/* Schema：供设置界面动态渲染（界面零硬编码） */
typedef struct ImeConfigSchemaOption {
    const char* key;          /* 点分键名（UTF-8） */
    int32_t     value_type;   /* 0=bool 1=int 2=enum 3=string */
    const char* default_toml; /* 默认值 TOML 字面量 */
    const char* doc_zh;       /* 中文说明 */
    int32_t     scope;        /* 0=engine 1=candidate_window 2=appearance 3=hotkey */
    int32_t     int_min;      /* int 类型闭区间下界（其它类型为 0） */
    int32_t     int_max;      /* int 类型闭区间上界（其它类型为 0） */
    const char* enum_values;  /* enum 取值：NUL 分隔，空串结束 */
    const char* title_zh;      /* 设置界面短标题（UTF-8） */
    const char* enum_labels_zh;/* enum 显示名：NUL 分隔，与 enum_values 一一对应 */
} ImeConfigSchemaOption;

typedef struct ImeConfigSchema {
    const ImeConfigSchemaOption* items;
    uint32_t                     len;
} ImeConfigSchema;

const ImeConfigSchema* ime_config_schema(void);

int32_t ime_config_set(const char* key, const char* value_toml);
int32_t ime_config_reload(void);

/* 变更回调：在触发 set/reload 的线程上同步派发。`user` 必须在订阅存在期间、
 * 且所有在途回调派发完成前保持有效；unsubscribe 不等待已开始的回调。 */
typedef void (*ImeConfigChangedFn)(const char* key, void* user);
int32_t ime_config_subscribe(ImeConfigChangedFn cb, void* user);
int32_t ime_config_unsubscribe(int32_t token);

#ifdef __cplusplus
}
#endif

#endif /* IME_H */
