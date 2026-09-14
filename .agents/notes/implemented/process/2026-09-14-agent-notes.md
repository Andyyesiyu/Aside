# Agent Note: 通过 Agent Notes 保留跨会话决策

Status: implemented

## Problem

长会话包含不断修正的交互和同步约束。只有聊天或版本说明，后续协作者难以区分当前决定、历史行为和未来设想。

## Decision

新增产品意图文档、根 AGENTS 入口以及按生命周期和类别组织的中文 Agent Notes。非平凡改动应同时更新相关记录。脚本检查结构、状态、本地链接；提供 Git 基线时还检查既有归档不变，以及代码和流程改动是否带有活跃记录。GitHub Actions 执行同一门禁和检查器回归测试。参考来源和适配范围见 [规范](../../README.md)。

## Alternatives considered

本次设计评估了只上传聊天、只扩写 README、照搬上游双语与插件体系。聊天包含私人上下文且难以维护，单一 README 不便表示决策生命周期，完整上游体系对当前项目过重。因此采用独立的中文文档和 Python 标准库检查器；这些是本次工程取舍，不是用户逐项否决。

## Consequences

不会接入 AI 模型或读取用户笔记。检查器能检查结构，不能判断文字是否真实，也不能自动识别所有非平凡修改；人工仍需维护理由、替代关系和验证边界。归档冻结从指定 Git 基线起生效。

## Verification

检查入口为 [check_notes.py](../../../../scripts/check_notes.py)，回归为 [test_check_notes.py](../../../../scripts/test_check_notes.py)，自动化为 [notes.yml](../../../../.github/workflows/notes.yml)。2026-09-14 本地执行检查器及相对 origin/main 基线检查通过，8 个单元测试通过，覆盖结构、损坏链接、状态不符、归档冻结与变更门禁。该流程不代替原生应用和真实备忘录验收。
