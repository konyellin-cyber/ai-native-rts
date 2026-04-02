# Godot 4.6 二维导航系统概览

> 来源: Godot 4.6 官方文档 https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html

## 架构

```
NavigationServer2D（底层服务器）
    ↑
NavigationRegion2D（定义可行走区域）
NavigationAgent2D（寻路代理）
```

## 设置步骤

1. 添加 `NavigationRegion2D` 节点，定义可行走区域
2. 烘焙导航多边形（编辑器按钮或 `bake_navigation_polygon()`）
3. 添加 `CharacterBody2D` 作为角色
4. 在角色下添加 `NavigationAgent2D` 子节点
5. 设置 target_position 触发路径计算
6. 在 `_physics_process` 中用 `get_next_path_position()` 移动

## 关键初始化顺序

```gdscript
func _ready():
    # 错误：直接设置 target_position，导航地图可能为空
    # navigation_agent.target_position = target

    # 正确：等待 NavigationServer 同步
    await get_tree().physics_frame
    navigation_agent.target_position = target
```

**原因**: 游戏启动第一帧 NavigationServer 的地图可能尚未同步区域数据。必须等待物理帧后再设置目标。

## 代理半径与碰撞偏移

- 导航网格定义的是角色**中心**可以站立的区域
- 需要在导航多边形边缘和碰撞物体之间留出足够的边距
- 代理半径 (`NavigationAgent2D.radius`) 会影响路径计算时与障碍物的最小距离

## 多区域连接

- 两个 NavigationRegion2D 仅重叠不够，必须共享相似边缘才能连接
- 连接距离阈值由 `NavigationServer2D.map_set_edge_connection_margin()` 控制
- 可通过 `use_edge_connections` 属性控制是否启用边缘连接

## 导航层

- NavigationRegion2D 和 NavigationAgent2D 都有 `navigation_layers` 属性
- 代理只会使用匹配层的区域进行寻路
- 用于创建不同类型单位使用不同路径的场景
