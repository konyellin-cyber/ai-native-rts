# 生产面板 (ProdPanel)

> 索引：[UI INDEX](INDEX.md)
> 实现：`scripts/ui/prod_panel.gd`

---

## 外观

选中己方基地时弹出，**悬浮在基地上方**：

```
┌─────────────────────────┐
│  ⚒ Base — Production    │
├───────────┬─────────────┤
│ 👷 Worker  │ 💎 50  ⏱ 3s │  ← 资源够高亮，不够灰显
├───────────┼─────────────┤
│ ⚔ Fighter │ 💎 100 ⏱ 5s │
├───────────┴─────────────┤
│ Producing: Fighter (2.3s)│
│ ████████████░░░░░░  0%  │  ← 进度条（始终存在）
└─────────────────────────┘
```

## 交互规则

| 操作 | 结果 |
|------|------|
| 左键单击 HQ | 弹出面板 |
| 框选包含 HQ 的区域 | 弹出面板 |
| 点击 Worker / Fighter 按钮 | 消耗资源，加入生产队列；**面板保持打开** |
| 资源不足时 | 按钮灰显 |
| 左键单击面板内空白处 | **不关闭**（面板区域内的点击被拦截） |
| 左键单击面板外空白处（click_missed） | 关闭面板 |
| 右键（移动命令） | 关闭面板 |
| 框选其他区域 | 关闭面板 |

## 位置规则

- 面板中心 X 对齐基地屏幕坐标 X
- 面板底边距基地屏幕坐标上方 80px
- 超出视口边界时自动 clamp

## 断言验收

| 断言 | 验收标准 |
|------|---------|
| `prod_panel_hidden_at_start` | 游戏启动 10 帧后 `visible_state == false` |
| `prod_panel_shows_on_hq_click` | 选中 HQ 后（单击或框选均可）`visible_state == true` |
| `prod_panel_hides_on_click_outside` | 面板显示后，点击空白处或发出移动命令后 `visible_state == false` |
| `prod_panel_has_progress_bar` | 面板节点树中存在 `ProgressBar` 子节点 |
| `prod_panel_position_near_hq` | 面板中心与 HQ 屏幕投影坐标距离 ≤ 300px |

## 待实现 / 已知差距

- [ ] 资源不足时红色"资源不足"提示文字（当前仅灰显按钮）
- [ ] 图标使用 💎（晶体）而非 ♥（当前 emoji 渲染差异，暂用文字替代）
