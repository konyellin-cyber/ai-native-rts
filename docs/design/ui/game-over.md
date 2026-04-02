# 游戏结束画面 (GameOverUI)

> 索引：[UI INDEX](INDEX.md)
> 实现：`scripts/ui/game_over_ui.gd`

---

## 外观

一方基地被摧毁时弹出，全屏半透明遮罩 + 居中面板：

```
┌─────────────────────────────────┐
│                                 │
│        🎉 胜 利！               │
│   摧毁了敌方基地                 │
│                                 │
│  战况统计:                      │
│   存活单位: 12                  │
│   击杀敌方: 25                  │
│   总采集量: 1850 晶体            │
│                                 │
│   [ 重新开始 ]    [ 退出 ]      │
│                                 │
└─────────────────────────────────┘
```

## 交互规则

| 操作 | 结果 |
|------|------|
| 点击「重新开始」 | `get_tree().reload_current_scene()` |
| 点击「退出」 | `get_tree().quit()` |

## Headless 行为

不弹窗，直接输出 `[RESULT] RED WINS` / `[RESULT] BLUE WINS` 并退出。

## 断言验收

> 当前无专属窗口断言。游戏结束信号 `game_over` 已接入截图机制（`screenshot_on_signals`），
> 可在 `tests/screenshots/` 中目视验证结束画面。
