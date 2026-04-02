# NavigationMeshSourceGeometryData2D API 参考

> 来源: Godot 4.6 官方文档 https://docs.godotengine.org/en/stable/classes/class_navigationmeshsourcegeometrydata2d.html
> 状态: **Experimental**（实验性，未来版本可能变更）

## 说明

Godot 4.6 引入的新类，用于在烘焙导航网格前收集几何数据。是 `NavigationPolygon.bake_from_source_geometry_data()` 的输入参数。

## 方法

### 数据管理

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `clear()` | void | 清空所有数据 |
| `has_data()` | bool | 是否有解析过的源几何数据 |
| `merge(other: NavigationMeshSourceGeometryData2D)` | void | 合并另一个数据源 |
| `get_bounds()` | Rect2 | 所有几何数据的轴对齐包围盒 |

### 可遍历区域

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `add_traversable_outline(shape_outline: PackedVector2Array)` | void | 添加可行走区域轮廓 |
| `set_traversable_outlines(outlines: Array[PackedVector2Array])` | void | 设置所有可行走区域轮廓 |
| `append_traversable_outlines(outlines: Array[PackedVector2Array])` | void | 追加可行走区域轮廓 |
| `get_traversable_outlines()` | Array[PackedVector2Array] | 获取所有可行走区域轮廓 |

### 障碍物区域

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `add_obstruction_outline(shape_outline: PackedVector2Array)` | void | 添加障碍物轮廓 |
| `set_obstruction_outlines(outlines: Array[PackedVector2Array])` | void | 设置所有障碍物轮廓 |
| `get_obstruction_outlines()` | Array[PackedVector2Array] | 获取所有障碍物轮廓 |

### 投影障碍物

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `add_projected_obstruction(vertices: PackedVector2Array, carve: bool)` | void | 添加投影障碍物 |
| `clear_projected_obstructions()` | void | 清除所有投影障碍物 |
| `get_projected_obstructions()` | Array | 获取投影障碍物（字典数组） |

## 使用示例

```gdscript
var source_data = NavigationMeshSourceGeometryData2D.new()

# 定义整个地图的可行走区域
source_data.add_traversable_outline(PackedVector2Array([
    Vector2(0, 0), Vector2(2000, 0),
    Vector2(2000, 1500), Vector2(0, 1500)
]))

# 定义障碍物（矩形）
source_data.add_obstruction_outline(PackedVector2Array([
    Vector2(500, 300), Vector2(700, 300),
    Vector2(700, 500), Vector2(500, 500)
]))

# 用 source_data 烘焙
var nav_poly = NavigationPolygon.new()
nav_poly.bake_from_source_geometry_data(source_data)
```

## carve 参数说明

`add_projected_obstruction(vertices, carve)`:
- `carve = true`: 严格切割，不受代理半径偏移影响，障碍物边缘精确贴合
- `carve = false`: 障碍物周围保留代理半径的缓冲空间
