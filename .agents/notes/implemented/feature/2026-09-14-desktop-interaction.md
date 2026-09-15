# Agent Note: 自由便笺与明确的显示入口

Status: implemented

## Problem

多个工作任务并行时，需要随手记录上下文。早期边缘悬停会意外打开，拖出的便笺一直显示也造成干扰。本文补记截至 0.11.0 已实现的会话决策。

## Decision

采用原生 macOS 自由便笺，Geneva + Fusion Pixel，默认 14 pt。点击可拖动的边缘图标才展开；默认自动隐藏，单张可钉住。鼠标保留区域向外扩大 72 pt，移出约 0.65 秒后开始收起。拖动顶边可直接移动另一张便笺，无需先激活；每张保存尺寸、缩放和显示器位置。Cmd +/- 同时调整尺寸与显示倍率。

## Alternatives considered

会话中先采用屏幕边缘悬停，后因误触改为点击图标。自由便笺始终显示的行为被用户要求改为默认隐藏、按需钉住。只调整便笺尺寸的快捷键按用户要求扩展为同时放大文字。

## Consequences

保留区域只用于判断是否收起，不应拦截其他应用点击。多显示器按屏幕身份保存位置，断开后临时回退；仍需真实外接显示器验收。

## Verification

实现见 [EdgeReveal](../../../../Sources/EdgeReveal.swift)、[DesktopNotes](../../../../Sources/DesktopNotes.swift)、[ScreenLayout](../../../../Sources/ScreenLayout.swift)。已有 [屏幕布局回归](../../../../Sources/ScreenLayoutTests.swift) 和 [缩放快捷键回归](../../../../Sources/ResizeShortcutTests.swift)。本次仅整理文档，未重新运行原生窗口测试；真实多屏体验尚未验收。

## Maintenance

2026-09-15 新增图标右键“固定模式（全部展开并保持显示）”。开启时取消未归档便笺及全局的折叠状态，显示侧边与自由便笺，暂停鼠标移出自动隐藏；保持图标可见以便取消。模式独立持久化，旧数据默认关闭，切换不修改单张钉住状态或原 autoHide 偏好。显式隐藏全部退出固定模式；普通自动隐藏仍遵循原规则。

取代检查：为当前交互决策新增显式模式，同一记录补充事实，不取代默认隐藏行为，无需归档。[FixedModeTests](../../../../Sources/FixedModeTests.swift) 覆盖展开、移出保留、菜单状态、持久化与偏好恢复。2026-09-15 验证：8 项固定模式检查及完整 self-test 全部通过；使用合成数据和原生窗口，真实多显示器体验仍待实机验收。
