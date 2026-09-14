# Agent Note: 备忘录同步优先保留内容与格式

Status: implemented

## Problem

用户希望在 Aside 和苹果备忘录两边编辑。备忘录脚本接口会规范化或丢失部分格式，简单覆盖可能造成不一致。本文补记既有同步设计。

## Decision

按关联笔记 ID 同步；回写前检查远端是否相对基线改变，保存同步前备份，写入后回读核验内容及支持的格式。不一致时保留本地版本并暂停自动同步，由用户查看差异后选择。启动、展开、唤醒检查远端，平时约每 5 秒轮询，停止编辑约 1.5 秒后尝试同步。复杂格式不能可靠往返时阻止回写。

## Alternatives considered

会话要求补齐常见格式，不能仅以纯文本替代富文本。对于回读不一致，本次整理明确评估了直接忽略差异继续覆盖的方案：它无法满足保留数据的要求，因而不采用。

## Consequences

支持范围内的双向编辑不等于全部备忘录格式无损同步；脚本接口也不提供原子条件写入，写前比较不能消除所有并发竞争。冲突暂停是一项保护，需要继续改善差异解释和恢复体验。品牌改名保留原应用标识及数据兼容路径。

## Verification

实现见 [Sync](../../../../Sources/Sync.swift)、[NotesBridge](../../../../Sources/NotesBridge.swift)、[格式安全](../../../../Sources/NotesFormatSafety.swift)。回归入口包括 [SyncSafetyTests](../../../../Sources/SyncSafetyTests.swift) 和 [LiveSyncTests](../../../../Sources/LiveSyncTests.swift)。本次未操作个人备忘录或重新执行集成测试；真实账户的并发编辑仍应使用独立测试笔记验证。
