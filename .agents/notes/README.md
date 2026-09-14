# Aside Agent Notes

Agent Notes 保存跨会话的决策依据：问题、实际决定、考虑过的替代方案、影响和验证。它不是用户的便笺数据库，也不保存完整聊天或个人笔记。

## 目录与状态

路径格式：`{status}/{category}/YYYY-MM-DD-topic.md`。状态使用 `proposed`、`implemented`、`rejected`、`archived`；类别使用 `feature`、`bug-fix`、`architecture`、`process`、`testing`、`simplification`。日期为该记录首次提出日期；后补的历史决策注明实际发生时间，不伪造历史文件日期。

- proposed：待讨论或尚未完整交付。写验收条件，不能作为当前功能依据。
- implemented：已经落地。同步维护代码位置、参数等事实；决策改变时新建记录并交叉引用。
- rejected：经过讨论后不采纳，状态行必须说明原因。只保留仍有指导意义的拒绝理由。
- archived：已实现记录失去当前指导价值后的冻结历史。保留 `Status: implemented`，增加 `Archived: YYYY-MM-DD`。归档后不再修改或当作现行要求；Git 基线检查阻止改写或删除历史归档。

没有记录时不建空状态目录。按路径和文本搜索发现记录，不维护集中 INDEX。

## 写作与生命周期

非平凡变更在同一提交/PR 中新增或更新 notes；先查重。已有记录可更新同一决策的事实，不改写成相反决定。新决定应说明替代关系；部分取代时两份记录都保留并互相链接。归档前把仍有效的约束转入活跃文档，修复所有入站链接。提案未实施就过时，应转为 rejected，不直接归档。

新文件使用 [模板](../templates/agent-note.md)。头部固定为标题、空行、`Status:`。正文中文，固定章节名英文，便于轻量检查：

- proposed：Problem、Proposal、Alternatives considered、Acceptance criteria、Risks。
- implemented：Problem、Decision、Alternatives considered、Consequences、Verification。
- rejected：保留提案骨架，状态行为 `Status: rejected — 原因`。

替代方案必须来自实际讨论或明确标注为本次设计评估，不能捏造用户否决。Verification 指向代码/测试、实际结果和未覆盖范围；仅“新增了测试文件”不等于执行通过。正文使用相对链接，状态迁移时一起修正链接。

## 检查入口

`python3 scripts/check_notes.py` 检查路径、状态、必需章节和本地文件链接。`--base <commit>` 还检查既有归档是否改变，以及 Sources/、scripts/、工作流或构建配置的改动是否带有活跃 note。GitHub Actions 在 push/PR 中运行同一检查。纯机械修改如触发代码门禁，可在变更中补充已有记录的验证事实，不使用静默跳过开关。

## 参考与本地取舍

参考 [DeepSeek Harness 的 notes 规范](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/.agents/notes/README.zh.md)、[notes 协作入口](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/.agents/notes/AGENTS.md) 和 [归档规则](https://github.com/deepseek-ai/deepseek-harness/blob/c291e7961a515f6d7af9304e7fd1d257929aef26/.agents/notes/archived/AGENTS.md)，查阅日期 2026-09-14。

Aside 沿用按状态/类别组织、记录理由和替代方案、核对取代关系、冻结归档的思路；采用单份中文 Markdown，不引入上游的双语三文件组、翻译记录和完整工具链。这里是针对小型原生应用独立编写的适配规则，不依赖 harness 运行时，也未安装其插件。
