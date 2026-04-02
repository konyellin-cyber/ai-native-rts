# DisplayServer — 窗口模式 / 全屏

Godot 4.x

---

## 窗口模式常量

| 常量 | 值 | 说明 |
|------|----|------|
| `WINDOW_MODE_WINDOWED` | 0 | 默认带标题栏窗口 |
| `WINDOW_MODE_MINIMIZED` | 1 | 最小化 |
| `WINDOW_MODE_MAXIMIZED` | 2 | 最大化（仍有标题栏） |
| `WINDOW_MODE_FULLSCREEN` | 3 | 独占全屏 |
| `WINDOW_MODE_EXCLUSIVE_FULLSCREEN` | 4 | 严格独占全屏（某些平台） |

> Godot 4 中 `WINDOW_MODE_BORDERLESS` 已并入 Flag，不再是独立的 mode 值。

---

## 核心 API

```gdscript
# 设置窗口模式
DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# 读取当前模式
var mode = DisplayServer.window_get_mode()

# 切换全屏 / 窗口
func toggle_fullscreen() -> void:
    if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
```

---

## 项目中的用法（bootstrap.gd）

在 `config.json` 中配置：
```json
"window": { "fullscreen": true }
```

bootstrap.gd 在 `_ready()` 中读取：
```gdscript
if not is_headless:
    var window_config = config.get("window", {})
    if window_config.get("fullscreen", false):
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
```

headless 模式下自动跳过，不影响 headless 回归。

---

## 注意事项

- **全屏下设置窗口尺寸无效**，需先切回 `WINDOW_MODE_WINDOWED` 再设 size
- **headless 模式**下调用 `window_set_mode` 会报错，必须先判断 `not is_headless`
- **Web 导出**：全屏请求必须由用户事件触发，不能在 `_ready()` 中直接调用
