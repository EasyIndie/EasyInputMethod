/* 萤火虫输入法 — C ABI 冒烟测试。
 *
 * 验证：staticlib 可链接、会话 ABI 可用（喂键→候选→选择→上屏）、
 * 配置 ABI 可读、坏输入（NULL）不崩。
 */
#include "ime.h"

#include <stdio.h>
#include <string.h>

int main(void) {
    /* ── 会话 ── */
    ImeSession* s = ime_session_new();
    if (s == NULL) {
        printf("FAIL: ime_session_new returned NULL\n");
        return 1;
    }

    ime_session_key(s, (uint32_t)'w');
    ime_session_key(s, (uint32_t)'q');

    ImeCandidates cands = ime_session_candidates(s);
    if (cands.len < 1 || cands.items == NULL) {
        printf("FAIL: no candidates\n");
        ime_session_free(s);
        return 1;
    }
    printf("candidates(%u):", cands.len);
    for (uint32_t i = 0; i < cands.len; i++) {
        printf(" [%s|%s|w=%d|prefix=%d]",
               cands.items[i].text, cands.items[i].code,
               cands.items[i].weight, cands.items[i].is_prefix);
    }
    printf("\n");

    ime_session_select(s, 0);
    ImeString committed = ime_session_commit(s);
    printf("commit: %s (len=%u)\n",
           committed.data != NULL ? committed.data : "(null)", committed.len);
    if (committed.data == NULL || strcmp(committed.data, "\u4f60") != 0) { /* 你 */
        printf("FAIL: unexpected commit\n");
        ime_string_free(committed);
        ime_session_free(s);
        return 1;
    }
    ime_string_free(committed);

    /* ── 配置 ── */
    const char* mode = ime_config_get("mode");
    printf("config mode: %s\n", mode != NULL ? mode : "(null)");
    if (mode == NULL || strcmp(mode, "mixed") != 0) {
        printf("FAIL: config mode not mixed\n");
        ime_session_free(s);
        return 1;
    }

    const ImeConfigSchema* schema = ime_config_schema();
    if (schema == NULL || schema->len < 1 || schema->items == NULL) {
        printf("FAIL: empty schema\n");
        ime_session_free(s);
        return 1;
    }
    printf("schema options: %u (first=%s)\n", schema->len, schema->items[0].key);

    /* ── 坏输入安全（不崩） ── */
    (void)ime_session_key(NULL, (uint32_t)'a');
    ime_session_select(NULL, 0);
    ime_session_free(NULL);
    ime_string_free((ImeString){ NULL, 0 });
    if (ime_config_get(NULL) != NULL) {
        printf("FAIL: ime_config_get(NULL) should be NULL\n");
        ime_session_free(s);
        return 1;
    }

    ime_session_free(s);
    printf("OK\n");
    return 0;
}
