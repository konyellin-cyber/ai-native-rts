# Input 与鼠标事件 API 参考

> 来源: Godot 4.6 官方文档

## 鼠标位置获取

### Input 单例

```gdscript
# 获取鼠标在视口中的位置（Vector2）
var mouse_pos = Input.get_mouse_position()

# 获取鼠标在 2D 世界中的位置（需要 Camera2D）
var world_pos = get_global_mouse_position()  # Node2D 子类可用
```

### InputEventMouseButton 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `button_index` | MouseButton | 按钮索引：`MOUSE_BUTTON_LEFT`、`MOUSE_BUTTON_RIGHT`、`MOUSE_BUTTON_MIDDLE` |
| `pressed` | bool | true=按下，false=释放 |
| `position` | Vector2 | 事件发生时鼠标位置（视口坐标） |
| `button_mask` | int | 当前按下的所有按钮位掩码 |
| `double_click` | bool | 是否双击 |
| `factor` | float | 横向滚轮滚动量 |

## 事件处理

### 方式一：`_input` 虚函数

```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            # 左键按下
            var pos = event.position
        elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            # 右键按下
            pass
    elif event is InputEventMouseMotion:
        # 鼠标移动
        var pos = event.position
        if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            # 左键拖拽中
            pass
```

### 方式二：`_unhandled_input`（未被 UI 消费的事件）

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    # 仅处理未被 Control 节点消费的事件
    if event is InputEventMouseButton:
        pass
```

### 方式三：输入映射（推荐用于 RTS 框选）

在 `project.godot` 中定义输入映射：
```ini
[input]
ui_select={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"button_index":1,"canceled":false,"double_click":false,"script":null)]
}
ui_select_next={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"button_index":2,"canceled":false,"double_click":false,"script":null)]
}
```

代码中使用：
```gdscript
func _physics_process(_delta):
    if Input.is_action_just_pressed("ui_select"):
        # 左键按下（开始框选）
        _drag_start = get_global_mouse_position()
    if Input.is_action_just_released("ui_select"):
        # 左键释放（完成框选）
        _drag_end = get_global_mouse_position()
    if Input.is_action_just_pressed("ui_select_next"):
        # 右键按下（移动命令）
        _move_target = get_global_mouse_position()
```

## 持续检测 vs 单次触发

| 方法 | 说明 |
|------|------|
| `Input.is_action_pressed("action")` | 当前帧按钮是否按住 |
| `Input.is_action_just_pressed("action")` | 当前帧按钮刚按下（仅触发一次） |
| `Input.is_action_just_released("action")` | 当前帧按钮刚释放（仅触发一次） |
| `Input.is_mouse_button_pressed(button)` | 当前帧鼠标按钮是否按住 |

## RTS 框选拖拽实现要点

```gdscript
var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _drag_start = get_global_mouse_position()
                _is_dragging = true
            else:
                if _is_dragging:
                    var drag_end = get_global_mouse_position()
                    _on_selection_rect(_drag_start, drag_end)
                    _is_dragging = false
```
