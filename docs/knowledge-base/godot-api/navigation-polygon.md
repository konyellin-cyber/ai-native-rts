# NavigationPolygon API 参考

> 来源: Godot 4.6 官方文档 https://docs.godotengine.org/en/stable/classes/class_navigationpolygon.html

## 属性

| 属性名 | 类型 | 说明 |
|--------|------|------|
| vertices | PackedVector2Array | 多边形顶点坐标 |
| polygons | Array[PackedInt32Array] | 构成导航网格的多边形（顶点索引数组） |
| outlines | Array[PackedVector2Array] | 用于烘焙的轮廓（顶点坐标数组，闭合形状） |
| baked_polygons | Array[PackedInt32Array] | 烘焙后的多边形数据（只读） |
| baked_vertices | PackedVector2Array | 烘焙后的顶点数据（只读） |

## 方法

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `add_outline(outline: PackedVector2Array)` | void | 添加一个轮廓（传入顶点坐标数组） |
| `remove_outline(idx: int)` | void | 移除指定索引的轮廓 |
| `get_outline_count()` | int | 轮廓数量 |
| `add_polygon(polygon: PackedInt32Array)` | void | 手动添加多边形 |
| `clear()` | void | 清除所有数据 |

### 烘焙方法（⚠️ Godot 4.6 变更）

> **踩坑 #8**: Godot 4.6 中 `bake()` 无参调用已不可用！必须使用 `bake_from_source_geometry_data()`。

**旧方式（Godot 4.5 及之前，已废弃）**:
```gdscript
nav_poly.add_outline(PackedVector2Array([Vector2(0,0), Vector2(100,0), Vector2(100,100), Vector2(0,100)]))
nav_poly.bake()
```

**新方式（Godot 4.6，推荐使用 NavigationRegion2D 的方法）**:
```gdscript
var source_data = NavigationMeshSourceGeometryData2D.new()
# 用 source_data 添加可遍历区域和障碍物...
nav_poly.bake_from_source_geometry_data(source_data)
```

或者在 `NavigationRegion2D` 上直接调用:
```gdscript
nav_region.bake_navigation_polygon(false)  # false = 同步烘焙
```

## 代码创建导航多边形示例

```gdscript
var nav_poly = NavigationPolygon.new()

# 定义顶点 - 矩形可行走区域
nav_poly.vertices = PackedVector2Array([
    Vector2(0, 0),
    Vector2(2000, 0),
    Vector2(2000, 1500),
    Vector2(0, 1500)
])

# 添加轮廓
nav_poly.add_outline(PackedVector2Array([
    Vector2(0, 0), Vector2(2000, 0),
    Vector2(2000, 1500), Vector2(0, 1500)
]))

# 烘焙（Godot 4.6 需要通过 NavigationRegion2D 的方法）
var nav_region = NavigationRegion2D.new()
nav_region.navigation_polygon = nav_poly
add_child(nav_region)
nav_region.bake_navigation_polygon(false)  # 同步烘焙
```
