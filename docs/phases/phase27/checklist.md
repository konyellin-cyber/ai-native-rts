# Phase 27 Checklist — Phase 26 美术流水线演练

**目标**: 演练一条稳定的 Phase 26 士兵美术生产流水线，从人体透视线稿开始，逐步验证姿态、装备、色块和 atlas 方案。  
**设计文档**: [design.md](design.md)  
**状态**: 📋 设计中

---

## 验收标准

- [x] 产出人体 / 枪兵 45 度透视构造线稿基准图
- [x] 产出 4–6 动作线稿姿态表
- [ ] 产出装备轮廓测试图
- [ ] 产出低饱和色块测试图
- [ ] 每一步保存 prompt
- [ ] 每一步保存输出图
- [ ] 每一步保存 review
- [ ] 至少一张输出图进入 Phase 26 小规模窗口或 mock 验证

---

## 27A：目录与记录规范

- [x] **27A.1** 新建 `docs/phases/phase27/art-pipeline/`
- [x] **27A.2** 新建 `art-pipeline/prompts/`
- [x] **27A.3** 新建 `art-pipeline/references/`
- [x] **27A.4** 新建 `art-pipeline/outputs/`
- [x] **27A.5** 新建 `art-pipeline/reviews/`
- [x] **27A.6** 新建 prompt 记录模板
- [x] **27A.7** 新建 review 记录模板

## 27B：人体 / 枪兵透视构造线稿基准

- [x] **27B.1** 编写 `001-spearman-perspective-construction.md`
- [x] **27B.2** 生成枪兵 45 度透视构造线稿
- [x] **27B.3** 复制输出到 `art-pipeline/outputs/`
- [x] **27B.4** 评审视角、头身比、脚底地面关系、长枪方向和透视压缩
- [x] **27B.5** 通过后标记为比例母版
- [x] **27B.6** 未通过透视评审时，不进入装备、色块或动作 sheet

## 27C：核心动作姿态表

- [x] **27C.1** 编写 `002-spearman-pose-sheet-lineart.md`
- [x] **27C.2** 生成 idle / march / attack / brace / hit / fallen 姿态表
- [x] **27C.3** 复制输出到 `art-pipeline/outputs/`
- [x] **27C.4** 评审各动作比例一致性
- [x] **27C.5** 评审缩小后的动作可读性

## 27D：装备轮廓层

- [ ] **27D.1** 编写 `003-equipment-silhouette.md`
- [ ] **27D.2** 生成轻甲步兵轮廓测试
- [ ] **27D.3** 生成矛兵 / 盾兵 / 旗手轮廓方向
- [ ] **27D.4** 复制输出到 `art-pipeline/outputs/`
- [ ] **27D.5** 评审小尺寸兵种区分度

## 27E：材质与色块层

- [ ] **27E.1** 编写 `004-color-block-test.md`
- [ ] **27E.2** 生成低饱和色块测试
- [ ] **27E.3** 测试 3 个家族色 tint 方向
- [ ] **27E.4** 复制输出到 `art-pipeline/outputs/`
- [ ] **27E.5** 评审人海画面噪声和远景可读性

## 27F：Atlas 与引擎验证

- [x] **27F.1** 编写 `003-phase26-pikeman-atlas-lineart.md`
- [x] **27F.2** 定义 atlas 命名、帧数、动作和透明背景要求
- [ ] **27F.3** 选择至少一张输出图做 Phase 26 mock / 窗口验证
- [ ] **27F.4** 记录验证截图或结论
- [ ] **27F.5** 决定是否扩大到完整士兵素材生产

---

## 非目标

- [ ] 不制作完整兵种库
- [ ] 不替换 Phase 26 全部士兵渲染
- [ ] 不为每个士兵实例生成独立图片
- [ ] 不推进 Phase 2 RTS 沙盒玩法

---

_更新: 2026-05-10_
