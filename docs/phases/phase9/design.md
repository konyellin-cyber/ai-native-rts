# Phase 9 设计文档：45 度等距视角镜头

> **适用阶段**：Phase 9
> **写于**：2026-03-29
> **背景**：Phase 8 完成后，游戏渲染为正交俯视（Camera3D rotation_degrees = -90°）。现希望切换至经典 RTS 等距视角（45° 斜视），增强立体感和视觉层次。

---

## 1. 目标

切换到 45 度等距正交视角，并保证：

- 游戏地图仍完整可见（无剪裁，无大片空白）
- headless 验证 11/11 全部 PASS（纯视觉层改动，不触碰逻辑）
- 窗口断言完整适配新视角参数
- UI 投影（生产面板跟随 HQ 的 unproject_position）在新视角下仍正确
- AI Renderer 坐标语义不受影响（逻辑层仍在 XZ 平面，_to_flat 不变）

不在本次范围内：

- 单位/建筑的 3D 高度（所有实体仍保持 Y=0）
- 等距地图素材替换（使用 Phase 7 现有 Mesh）
- 镜头平移/缩放交互功能

---

## 2. 视角参数设计

### 等距视角的几何约定

经典 RTS 等距视角由两个旋转角定义：

```
俯仰角（Pitch）= -45°    绕 X 轴旋转，向下倾斜 45°
偏航角（Yaw）  = -45°    绕 Y 轴旋转，使地图 45° 斜向呈现（右上=远，左下=近）
```

Godot rotation_degrees 表示为 `Vector3(-45, -45, 0)`。

### 摄像机位置计算

正交相机不存在近大远小，位置只影响"看到哪里"，不影响透视畸变。
需要保证：**地图中心在屏幕中央**。

等距视角下，相机需要从斜后上方看向地图中心。设地图中心为 `C = (map_w/2, 0, map_h/2)`，
相机相对中心的位移由旋转角反推：

```
摄像机朝向（forward）= Vector3(-sin45°·cos45°, sin45°, -cos45°·cos45°)
                     ≈ Vector3(-0.5, 0.707, -0.5)（归一化后）

摄像机位置 = 地图中心 - forward * 后退距离
```

实际落地：高度 Y 取 1500（与 Phase 7-8 一致），由高度反算 Z 偏移：

```
后退距离 D = Y / sin(45°) ≈ 1500 / 0.707 ≈ 2121
Z 偏移    = D * cos(45°) ≈ 2121 * 0.707 ≈ 1500

camera.position = Vector3(map_w/2, 1500, map_h/2 + 1500)
```

### 正交 size 计算

等距视角下摄像机"看到的宽度"由两个因素决定：
1. 地图的对角线方向变为竖直方向（斜 45°），可视宽度约为 `map_w / sqrt(2)`
2. 地图被压缩（Y 轴 cos45° 投影），高度方向约为 `map_h * cos45° / 2`

保守估计，取地图对角线确保完整覆盖：

```
diagonal   = sqrt(map_w² + map_h²)   ≈ sqrt(3000² + 2000²) ≈ 3606
iso_height = map_h * cos(45°)        ≈ 2000 * 0.707 ≈ 1414

取二者之中较大者再加 10% 安全边距：
size = max(diagonal / 2, iso_height) * 1.1
     ≈ max(1803, 1414) * 1.1 ≈ 1984

实际取 size = 2000（整数，方便理解）
```

> **为什么不直接试**：size 过小会剪裁地图边缘，过大浪费分辨率。先推导一个合理初值，再用窗口断言验证。

---

## 3. 模块影响分析

### 3A：bootstrap.gd — 唯一需要修改的文件

`_setup_3d_scene()` 函数改动三处：

| 参数 | 当前值 | 新值 | 理由 |
|------|--------|------|------|
| `rotation_degrees` | `(-90, 0, 0)` | `(-45, -45, 0)` | 等距标准角 |
| `position` | `(cx, 1500, cz)` | `(cx, 1500, cz + 1500)` | 斜视需要向后退，Z 偏移 ≈ Y 高度 |
| `size` | `map_h`（≈2000） | `2000`（不变）| 推导后数值相同，无需改 |

光照方向同步调整，等距视角下从左前上方打光层次更好：

| 参数 | 当前值 | 新值 |
|------|--------|------|
| `light.rotation_degrees` | `(-60, -30, 0)` | `(-45, -45, 0)` | 与视角方向对齐，避免正面全黑 |

### 3B：window_assertion_setup.gd — 断言适配

三处 camera 断言受影响：

| 断言 | 当前逻辑 | Phase 9 调整 |
|------|---------|-------------|
| `camera_orthographic` | 检查 `projection == ORTHOGONAL` | ✅ 不变（仍是正交） |
| `camera_covers_map` | 检查 `size >= map_height * 0.8` | ✅ 不变（size=2000 仍满足） |
| `camera_centered` | 检查 `camera.position.(x,z)` 在地图中央 ±300 | ⚠️ 需调整：等距视角 Z 偏移 1500，不再贴近地图中心 |

`camera_centered` 的修改方案：

- 旧逻辑：检查 `position.(x,z)` 与地图中心的 XZ 距离
- 新逻辑：检查 `position.x` 居中（X 方向不变），同时检查 `rotation_degrees.y ≈ -45`（表征等距偏航角）
- 重命名为 `camera_isometric`，语义更准确

新断言清单：11 个（替换 1 个，总数不变）：

```
保留（10个）：
  camera_orthographic, camera_covers_map,
  units_have_mesh, hq_has_mesh,
  no_initial_selection, prod_panel_hidden_at_start,
  prod_panel_shows_on_hq_click, bottom_bar_visible,
  prod_panel_has_progress_bar, prod_panel_position_near_hq

替换（1个）：
  camera_centered  →  camera_isometric
  新逻辑：position.x 居中 ±300 且 rotation_degrees.y ≈ -45° ±5°
```

### 3C：prod_panel.gd — unproject_position 兼容验证

`unproject_position()` 是 Godot Camera3D 的标准 API，对正交相机的**任意旋转角度**均有效，等距视角下不需要修改。

但需要验证：等距视角下 HQ 的屏幕投影坐标是否仍在合理范围（生产面板不跑到屏幕外）。

验证方式：窗口断言 `prod_panel_position_near_hq` 已覆盖（检查面板与 HQ 屏幕坐标距离 ≤ 300px），Phase 9 该断言保留，验证自动完成。

### 3D：AI Renderer — 不受影响

`formatter_engine.gd` 的 `_to_flat()` 取 `(pos.x, pos.z)`，等距视角不改变游戏逻辑层坐标，无需修改。

---

## 4. 暗坑预警

| 风险 | 表现 | 预防 |
|------|------|------|
| size 偏小导致地图边缘被剪 | 窗口模式下地图四角不可见 | camera_covers_map 断言会捕获；目视截图复查 |
| Z 偏移计算偏差 | 地图显示偏下/偏上，红蓝基地不对称 | camera_isometric 断言检查 X 居中；目视截图复查 |
| unproject 超出视口 | 生产面板飞到屏幕外 | prod_panel_position_near_hq 断言覆盖 |
| 光照方向与视角不协调 | 单位正面全黑，看不清 Mesh 形状 | 目视截图，必要时调 light.rotation_degrees |
| headless 断言误报 | camera_* 断言在 headless 下找不到 Camera3D | 已有"Camera3D not found → pending" 保护逻辑，不受影响 |

---

## 5. 验证标准

| 维度 | 通过条件 |
|------|---------|
| headless 回归 | 11/11 PASS（视觉改动不触碰逻辑层） |
| 窗口断言 | 11/11 PASS（含新 camera_isometric 替换旧 camera_centered） |
| 目视截图 | 地图完整可见，红蓝基地/矿物/单位均可辨认，无严重遮挡 |
| UI 投影 | 生产面板在选中 HQ 后出现在 HQ 上方，不跑出视口 |

---

_创建: 2026-03-29_
