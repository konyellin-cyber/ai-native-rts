# NavigationRegion2D API 参考

> 来源: Godot 4.6 官方文档 https://docs.godotengine.org/en/stable/classes/class_navigationregion2d.html

## 属性

| 属性名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| enabled | bool | true | 是否启用导航区域 |
| enter_cost | float | 0.0 | 进入此区域的路径成本代价 |
| navigation_layers | int | 1 | 导航层位掩码（1-32层） |
| navigation_polygon | NavigationPolygon | - | 使用的导航多边形资源 |
| travel_cost | float | 1.0 | 区域内移动成本乘数 |
| use_edge_connections | bool | true | 是否使用边缘连接与其他区域相连 |

## 方法

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `bake_navigation_polygon(on_thread: bool = true)` | void | **烘焙导航多边形**。默认在后台线程执行 |
| `get_bounds()` | Rect2 | 返回导航网格的轴对齐矩形 |
| `get_navigation_map()` | RID | 返回当前使用的导航地图 RID |
| `get_rid()` | RID | 返回 NavigationServer2D 上的 RID |
| `is_baking()` | bool | 是否正在后台烘焙 |
| `get_navigation_layer_value(layer_number: int)` | bool | 指定层是否启用 |
| `set_navigation_layer_value(layer_number: int, value: bool)` | void | 启用/禁用指定层 |

## 信号

| 信号 | 说明 |
|------|------|
| `bake_finished` | 导航多边形烘焙完成时发出 |
| `navigation_polygon_changed` | 导航多边形被替换或内部更改提交时发出 |

## 重要注意事项

- **异步烘焙**: `bake_navigation_polygon(true)` 是异步的，用 `is_baking()` 检查状态，`bake_finished` 信号通知完成
- **同步烘焙**: `bake_navigation_polygon(false)` 会阻塞主线程
- **区域连接**: 两个区域仅重叠不够，必须共享相似边缘才能连接
