#!/usr/bin/env python3
"""Prepare an unexecuted IMK acceptance packet without accessing the desktop."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent


def formal_module():
    spec = importlib.util.spec_from_file_location('formal_acceptance', HERE / 'acceptance-results.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Each tuple describes future observations, never an execution command.
SCENARIOS = (
    ('identity', 'package-validation', '核验同一最终候选',
     '核对SOURCE-COMMIT、已装执行文件SHA、Developer ID、公证/Gatekeeper和架构；记录实际宿主PID、可执行路径与摘要。',
     '包、安装副本与运行宿主身份一致；旧宿主不得作为新候选结果。',
     'package-identity.json、host-identity.json、信任检查原始输出'),
    ('preflight', 'resource-isolation', '确认当前空闲与资源边界',
     '记录本轮用户空闲确认时间、辅助功能/自动化状态、原输入源与完整启用集合；创建唯一空白测试资源并登记路径/窗口/进程。',
     '仅自有测试资源可操作；真实配置与词库摘要不变；权限或归属不确定不切源、不发键。',
     'preflight.json、owned-resources.json、data-before.json；不保存用户文本'),
    ('focus-stop', 'focus', '验证焦点变化停止',
     '仅在自有资源中测试；受控改变焦点后检查驱动拒绝下一动作，不向其他窗口发键；再次运行须重新确认对象。',
     '每次动作前在同调用中校验应用/窗口/AX控件/输入源，失配立即停止，不自动抢回焦点。',
     'focus-guard.log、rejected-action.json；记录拒绝原因及未执行动作'),
    ('restore', 'state-restoration', '正常/失败/INT/TERM四路径恢复',
     '分别在合成wq预编辑已确认后正常提交、断言失败、INT、TERM；每轮用新资源，先恢复原源与启用集合再精确关闭自有资源。',
     '四路径单独记录；组合可控取消，真实数据摘要保持，无其他窗口被关闭；未确认的marked range不得推断。',
     '四个独立result.json、source-before/after.json、data-before/after.json、cleanup.log'),
    ('input', 'core-input', '实际输入及候选',
     '先选择已核验源再创建/首次激活自有客户端；输入wq空格、nihao选词、翻页选择；在支持客户端读取明确marked range。',
     '五笔提交你、拼音提交你好；候选/页码与提交一致，提交后marked range清除；缺字显示兜底但保留原文。',
     'synthetic-input-result.json、marked-range.json、候选截图；只记录合成内容'),
    ('menu-cycle', 'mode-switch', '系统菜单父项与显式子项',
     '在真实输入源菜单检查普通右侧状态紧邻系统箭头；父项循环混输/五笔/拼音；分别选子项并重开检查；记录每次菜单是否保持。',
     '父项循环后保持菜单且实时刷新；子项选择与当前模式同步；四个状态项无多余对号，切换后文案正确。',
     'menu-actions.json、每步带候选身份的截图/录屏、会话同步观察'),
    ('learning', 'core-input', '学习区与快捷键',
     '在自有文档测试学习区开关与默认热键、切换候选、长词点击/滚动及翻页；核验配置往返；仅对已校验拆字断言内容。',
     '开关/快捷键即时一致，不改变候选原文；编码与当前候选一致；未知拆字明确缺失，不当作全量覆盖。',
     'learning-actions.json、长词/滚动截图、私有fixture配置前后摘要'),
    ('settings', 'mode-switch', '菜单设置同步及失败恢复',
     '仅在已建立私有fixture并证明写入隔离后测试模式、快捷键重绑定和保存失败；重开设置检查；隔离未就绪则BLOCKED。',
     '菜单/会话/设置一致，冲突被拒绝，失败不伪装保存成功；不改真实配置作故障注入。',
     'settings-actions.json、配置写入结果、恢复日志'),
    ('keyboard', 'accessibility', '物理键盘导航',
     '用实际物理键盘打开系统菜单，逐项导航、展开子菜单、选择和Esc退出；逐动作记录焦点与状态；合成NSEvent不可替代。',
     '可到达父项/子项，选择生效，无焦点陷阱；失败与未到达分别记录。',
     'keyboard-steps.json、导航录屏/人工观察及实际设备信息'),
    ('voiceover', 'accessibility', '实际VoiceOver',
     '记录原辅助功能状态；单独安排启用VoiceOver，导航菜单/候选/学习/设置，记录实际播报并恢复原状态。',
     '名称、角色、当前值与选中候选可理解；直接AX动作或属性存在不算播报通过。',
     'voiceover-observations.json、实际播报记录、辅助功能状态恢复结果'),
    ('appearance', 'light-dark-layout', '真实系统外观和辅助显示',
     '记录原系统外观，在亮/暗及辅助显示下检查菜单、候选、设置；结束恢复原状态，多屏另项取证。',
     '无遮挡或裁切、对比可辨、状态对齐；组件指定appearance截图不能替代本项。',
     'system-appearance-before/after.json、原生桌面截图、观察结果'),
    ('client-matrix', 'application-TextEdit', '逐客户端独立取证',
     'TextEdit/Safari/Chrome/VSCode/WeChat/Terminal各自记录版本、所有权和焦点协议；安全字段、非US布局单列；没有安全适配器的客户端保持BLOCKED。',
     '每客户端分别更新正式application-ID；禁止复用TextEdit通过覆盖其他客户端或真实聊天草稿。',
     '各客户端独立步骤、输入/恢复结果；其他application-ID仍按实际状态填写'),
)


def prepare(output):
    formal = formal_module()
    packet = formal.template()
    # Preparation is deliberately unable to assign observed values or PASS.
    steps = []
    for identifier, parent, title, action, expected, evidence in SCENARIOS:
        if parent not in formal.REQUIRED:
            raise ValueError('未知正式用例：' + parent)
        steps.append({'id': identifier, 'formal_case': parent, 'title': title,
                      'steps': action, 'expected': expected, 'required_evidence': evidence,
                      'status': 'BLOCKED', 'actual': '', 'observed_at': '', 'evidence': []})
    os.umask(0o077)
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    (output / 'formal-report.json').write_text(json.dumps(packet, ensure_ascii=False, indent=2) + '\n')
    (output / 'checklist.json').write_text(json.dumps({'scope': 'unexecuted-imk-plan', 'executed': False, 'scenarios': steps}, ensure_ascii=False, indent=2) + '\n')
    lines = ['# 真实IMK验收准备包（尚未执行）', '',
             '生成成功不等于验收通过。正式23项全部BLOCKED；候选与应用版本留空，等待同一最终包实测。', '',
             '## 执行前条件', '',
             '当前合入/公证/安装暂停。恢复执行需明确范围及当时空闲；不能沿用历史空闲确认。',
             '先核验候选与运行宿主身份、权限、资源所有权、私有fixture与逐动作焦点保护，再允许动作。',
             '现有TextEdit/Safari/Terminal驱动仅适用其独有隔离协议，不直接用于当前正式包或新菜单交互。',
             '未实现保护的步骤保持受控手工待验，不通过模板自动执行。', '',
             '## 停止与恢复', '',
             '焦点/输入源/对象身份变化、权限缺失、无法确认marked range或用户开始操作时停止后续动作。',
             '正常、失败、INT、TERM分别取证；恢复输入源及完整启用集合后只关闭有所有权的对象。',
             '配置已被外部修改不得盲目回写；恢复失败保留日志/备份，标记FAIL或BLOCKED，列出待恢复对象。',
             '不可捕获中断只按所有权日志人工核对，不全局关窗/杀进程、不清空聊天或剪贴板。', '',
             '## 逐项记录', '']
    for item in steps:
        lines += [f"### {item['id']}：{item['title']} → {item['formal_case']}", '',
                  '- 状态：BLOCKED（尚未执行）', '- 步骤：' + item['steps'],
                  '- 预期：' + item['expected'], '- 证据：' + item['required_evidence'],
                  '- 实测 / 时间 / 操作者 / 候选身份：待记录', '']
    lines += ['## 记录规则', '',
              '每次动作记录预期与实际，失败保留原始证据并另建运行目录重测，未执行项不得填PASS。',
              '清单是正式用例的子场景，单个子场景通过不能直接使父级通过。客户端矩阵只提供步骤，六个正式application-ID必须分别取证。',
              '长期组合、撤销、睡眠唤醒、性能、多屏、Intel设备、独立复现及五工作日仍须另行执行；不可由此清单推断通过。',
              'formal-report.json保持既有schema 2，完成真实观察后逐项填身份/状态/原因/相对证据路径，用acceptance-results.py check审核。',
              '验证器通过也需要人工审查证据真实性；本准备入口没有执行模式。', '']
    (output / 'checklist.md').write_text('\n'.join(lines))
    return len(steps)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='全新目录，拒绝覆盖')
    args = parser.parse_args()
    try:
        count = prepare(args.output)
        print(f'PREPARED {count} scenarios; executed=false; formal cases remain BLOCKED')
        return 0
    except (OSError, ValueError) as error:
        print('BLOCKED: ' + str(error), file=sys.stderr)
        return 3


if __name__ == '__main__':
    sys.exit(main())
