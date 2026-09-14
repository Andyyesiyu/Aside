# Agent Note: 编辑末行被底部裁切的回归约束

Status: implemented

## Problem

用户反馈输入时最后一行被底部遮住或只显示半行。此记录补记此前 0.10.7 阶段的修复：普通字号初测未复现，扩大到缩放及窗口尺寸变化后复现。

## Decision

在布局完成后的主线程回调中更新编辑区高度，并滚动到完整插入行；保留 24 pt 底部空间。需要保证缩放、换行和调整窗口后继续输入仍可见，同时不打断用户主动向上阅读。

## Alternatives considered

定位时先检查普通字号的底部空间，未能覆盖问题；扩展到缩放与窗口变化后发现布局与滚动时序问题。仅增加固定留白不足以验证或解决这个时序问题。

## Consequences

末行可见性成为持续回归要求。不要将一次普通字号测试通过推广为所有缩放和中文输入状态都正确。

## Verification

[EditorViewport](../../../../Sources/EditorViewport.swift) 实现延迟布局后的可见性修正。[LastLineTests](../../../../Sources/LastLineTests.swift) 覆盖 0.8、1、1.2、1.5、2 倍缩放，以及中文组合输入、换行、折行、尺寸变化等场景，并接入 [SelfTests](../../../../Sources/SelfTests.swift)。此前修复时回归通过；本次是历史记录整理，未重新运行。单独入口为 `DeskNotes --last-line-check`，需 macOS 图形会话。
