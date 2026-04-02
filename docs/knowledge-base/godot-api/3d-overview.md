# Godot 4.x 3D 支持情况

---

## 渲染管线

| 管线 | 适用场景 | 特点 |
|------|--------|------|
| **Forward+** | 桌面 3D 游戏（默认） | 功能最完整，支持体积雾、SSR、全局光照 |
| **Mobile** | VR/XR、高端移动 | 功能与性能平衡 |
| **Compatibility** | 网页、低端设备、2D | OpenGL，兼容性最好，功能最少 |

当前项目（相当于桌面 RTS）如扩展到 3D 选 **Forward+**。

---

## 2D → 3D 节点对应

| 2D 节点 | 3D 对应 | 说明 |
|---------|--------|------|
| Node2D | Node3D | 基础变换节点 |
| CharacterBody2D | CharacterBody3D | 玩家/NPC，用 `move_and_slide()` |
| StaticBody2D | StaticBody3D | 地板、墙、静态环境 |
| RigidBody2D | RigidBody3D | 物理模拟，用 `apply_force()` |
| Area2D | Area3D | 区域检测，信号 `body_entered/exited` |
| Sprite2D + AnimatedSprite2D | MeshInstance3D + AnimationMixer | 模型渲染和动画 |
| NavigationAgent2D | NavigationAgent3D | 寻路（3D 版为实验性 API） |

---

## 物理引擎：Godot Physics vs Jolt

Godot 4.6 起新项目默认使用 **Jolt Physics**。

| 对比项 | Godot Physics | Jolt Physics |
|--------|-------------|-------------|
| 多核并行 | 基本没有 | 原生并行，性能 3-5x |
| 稳定刚体数量 | < 1,000 | 10,000+ |
| 精度 | 厘米级 | 亚毫米级 |
| SoftBody3D | ✅ | ❌（实验阶段） |
| 推荐场景 | 需软体/精细关节 | RTS / 大量单位 / VR |

**RTS 大量单位 → 选 Jolt**。

---

## 从 2D 迁移到 3D 关键注意点

### 坐标系
```gdscript
# 俯视角 RTS（最常见）：Y 是高度，XZ 是平面
var pos3d = Vector3(pos2d.x, 0.0, pos2d.y)

# 所有角度用弧度，不是度数
rotation.y = deg_to_rad(90)   # ✅
rotation.y = 90                # ❌ 这是 90 弧度 ≈ 5000°
```

### 重力需要手动加
```gdscript
func _physics_process(delta):
    velocity.y -= 9.8 * delta   # 2D 中物理引擎自动处理，3D 要手写
    velocity = move_and_slide()
```

### 平面移动用 X/Z，不是 X/Y
```gdscript
# 3D RTS 单位移动
velocity.x = direction.x * speed
velocity.z = direction.z * speed   # 2D 中是 velocity.y
```

### 碰撞层设置不变
`collision_layer` / `collision_mask` 机制与 2D 完全一致，32 层。

---

## 对当前 RTS 项目的迁移建议

当前项目是俯视角 2D RTS，迁移 3D 有两条路：

**路线 A：保持俯视，换成 3D 渲染（视觉升级）**
- Camera3D 放在高处向下 `look_at` 地面
- CharacterBody2D → CharacterBody3D，Y 固定为 0
- 地图从 NavigationPolygon → NavigationMesh（烘焙方式相似）
- 改动量：中等，逻辑基本不变

**路线 B：真正的 3D 空间（地形高低差）**
- 需要重新设计导航（NavigationRegion3D）
- 单位需要处理重力、坡度
- 改动量：大

对于 RTS 游戏风格，**路线 A 更合理**，视觉提升明显但逻辑改动最小。

---

## 性能陷阱（3D 特有）

1. **不要每个单位用 trimesh 碰撞** → 用 CapsuleShape3D / BoxShape3D
2. **大量相同单位** → 用 MultiMeshInstance3D 替代单独 MeshInstance3D（快 50-100x）
3. **实时阴影很贵** → 静态物体用烘焙光照
4. **着色器首次编译卡顿** → 在 Loading 阶段预热
