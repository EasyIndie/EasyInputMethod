# 仓库公开可行性初审（2026-10-09）

## 结论

EasyIndie/EasyInputMethod 已归属 EasyIndie 组织，当前 private，无需迁移。项目定位与 GPL-3.0-or-later 适合公开；本次仅评估，不改变可见性。

## 检查证据与边界

- GitHub API 确认 owner.type 为 Organization，本账号有仓库 admin 权限。
- 扫描本地全部 Git 引用的 604 个历史 blob：未发现常见私钥 PEM、GitHub token、AWS AKIA key 模式，也未发现 p12/p8/pfx/key/.env/SSH 私钥文件路径。此检查不是完整密钥审计，未覆盖远端独有引用、Actions 日志及附件。
- 项目有 LICENSE、贡献规范、数据来源/许可/SHA 登记；图标记录 AI 生成来源。许可核验沿用既有登记与验证结果，本次没有重新开展法律审查。
- PR 使用 pull_request，无签名凭据；签名工作流仅 main，contents: read，临时材料退出清理。公开前建议固定第三方 Actions 的完整 commit SHA，并明确普通 CI 的只读权限。
- 公开会暴露历史代码、提交作者信息、文档中的本机路径/签名身份，以及 Actions 历史与日志；需确认这些信息可以公开，并完成日志/附件复核。
- main 保护接口返回套餐限制 403，不能据此确认已有保护；公开后应设置 PR 与必需 CI 检查，并限制绕过。

## 凭据实际状态

仓库可见组织 Secrets：APPLE_ASC_API_KEY、APPLE_ASC_API_KEY_ID、APPLE_ASC_ISSUER_ID、APPLE_ID、APPLE_TEAM_ID。仓库级 Secrets 列表为空；仓库变量 MACOS_SIGNING_IDENTITY 存在。

现有工作流要求 MACOS_CERTIFICATE_P12_BASE64、MACOS_CERTIFICATE_PASSWORD、ASC_API_KEY_P8_BASE64、ASC_API_KEY_ID、ASC_API_ISSUER_ID。目前名称不匹配，且未看到证书及密码。APPLE_ASC_API_KEY 的内容格式未知，不能直接假定为 base64 p8。APPLE_ID/APPLE_TEAM_ID 不能替代证书私钥和导出密码。

组织级 Secrets 列表请求因当前 token 缺 admin:org 返回 403；仓库可见组织 Secrets 的只读接口成功，无需扩大权限即可确认上述可见名单。

## 下一步

1. 对齐组织 Secrets 名称、p8 编码格式及证书/密码，首次验证签名公证链路。
2. 复核待公开的历史日志/附件和个人元信息，完成 Actions 权限加固。
3. 用户明确决定公开后调整可见性，设置并验证 main 分支保护；本次未执行公开、合并或发布。

依据：[GitHub 仓库可见性说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)。
