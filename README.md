# AI Native RTS

> 和竹晓一起做一款游戏。AI 是编码助手，人是玩法设计师。

**状态**: Phase 0-3 ✅ | Phase 5 ✅ | Phase 6 ⏳
**引擎**: Godot 4.6

## 目录结构

```
ai-native-rts/
├── README.md
├── overview.md                             ← 项目宪章、设计决策、风险
│
├── docs/
│   ├── design/                             ← 系统性设计（跨 Phase 有效）
│   │   ├── game/mvp.md                     ← 玩法机制
│   │   └── tech/ai-renderer.md             ← AI Renderer 架构（v1-v4）
│   ├── phases/                             ← 阶段文档
│   │   ├── roadmap.md                      ← Phase 概览与进度
│   │   ├── phase{0,05,1,2,3,4}/checklist.md
│   │   ├── phase5/{design,checklist}.md    ← 架构重构
│   │   └── phase6/{design,checklist}.md    ← 3D 适配
│   ├── rules/
│   │   ├── dev-rules.md                    ← 开发规范
│   │   └── pitfalls.md                     ← 踩坑记录
│   └── knowledge-base/godot-api/           ← Godot API 本地参考
│
└── src/
    ├── phase0-balls/                        ← Phase 0 ✅
    ├── phase05-rts-prototype/               ← Phase 0.5 ✅
    ├── phase1-rts-mvp/                      ← Phase 1 ✅
    └── shared/ai-renderer/                  ← AI Renderer v6（共享）
```

## 快速导航

| 想了解... | 去看... |
|----------|---------|
| 当前开发到哪了 | [`docs/phases/roadmap.md`](./docs/phases/roadmap.md) |
| 某个 Phase 的详细进度 | `docs/phases/<phaseN>/checklist.md` |
| 怎么写代码 | [`docs/rules/dev-rules.md`](./docs/rules/dev-rules.md) |
| 踩过什么坑 | [`docs/rules/pitfalls.md`](./docs/rules/pitfalls.md) |
| AI Renderer 架构 | [`docs/design/tech/ai-renderer.md`](./docs/design/tech/ai-renderer.md) |
| 玩法机制 | [`docs/design/game/mvp.md`](./docs/design/game/mvp.md) |
| Phase 1 文件索引 | [`src/phase1-rts-mvp/FILES.md`](./src/phase1-rts-mvp/FILES.md) |
| Godot API 参考 | [`docs/knowledge-base/godot-api/`](./docs/knowledge-base/godot-api/) |
| 项目宪章和风险 | [`overview.md`](./overview.md) |

## 运行项目

```bash
# Headless 模式（自动测试，无窗口）
godot --headless --path src/phase1-rts-mvp --scene res://tests/test_runner.tscn

# 窗口测试模式（默认，有窗口 + 自动剧本 + 断言验证，跑完 1800 帧后自动退出）
godot --path src/phase1-rts-mvp

# 游玩模式（有窗口，关闭 SimulatedPlayer 和断言，手动操作，不自动退出）
godot --path src/phase1-rts-mvp -- --play
```

### 三种启动模式对比

| 模式 | 命令 | SimulatedPlayer | 断言 | 帧数限制 | 用途 |
|------|------|:-:|:-:|:-:|------|
| Headless | `--headless` | ✅ | ✅ | ✅ | CI / 自动回归 |
| 窗口测试 | （默认） | ✅ | ✅ | ✅ 1800帧 | 可视化断言验证 |
| 游玩 | `-- --play` | ❌ | ❌ | ❌ | 手动游玩 |

---

_创建: 2026-03-21 | 更新: 2026-04-03_
