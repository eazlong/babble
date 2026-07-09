# Shader系统详细设计文档

**版本**: 1.0
**日期**: 2026-06-24
**引擎**: Godot 4.6
**适用平台**: iOS / Android / Web (Mobile Rendering)

---

## 1. 设计目标

- **性能优先**: 单帧Shader耗时 < 5ms，确保60 FPS
- **移动端兼容**: 避免高精度float运算，兼容低端GPU
- **降级策略**: 3级性能降级自动切换
- **易维护**: 统一命名规范，模块化设计

---

## 2. Shader文件清单

### 2.1 核心Shader (已验证)

| Shader文件 | 用途 | 复杂度 | 适用场景 | 性能预算 |
|------------|------|--------|----------|----------|
| `spirit_glow.gdshader` | 词灵发光效果 | 中等 | 词灵解锁、精灵召唤 | 2ms/帧 |
| `magic_burst.gdshader` | 魔法爆发波纹 | 中等 | 施法成功、宝箱开启 | 2.5ms/帧 |
| `transition_wipe.gdshader` | 场景过渡擦除 | 低 | 场景切换 | 1ms/帧 |

### 2.2 规划中Shader

| Shader文件 | 用途 | 复杂度 | 状态 | 预计性能 |
|------------|------|--------|------|----------|
| `star_trail.gdshader` | 星星拖尾轨迹 | 中等 | 待实现 | 2ms/帧 |
| `ambient_particle.gdshader` | 环境粒子着色 | 低 | 待实现 | 1ms/帧 |
| `ui_glass.gdshader` | UI玻璃效果 | 高 | 待实现 | 3ms/帧 (降级备用) |
| `ripple_distortion.gdshader` | 水波纹扭曲 | 中等 | 待实现 | 2ms/帧 |

### 2.3 复杂度分级定义

```
低复杂度:
  - 仅fragment()函数
  - 无循环，最多2次纹理采样
  - 简单数学运算(+,-,*,smoothstep)

中复杂度:
  - fragment() + vertex()函数
  - 最多1次循环(固定次数<10)
  - 最多3次纹理采样
  - 使用TIMEuniform

高复杂度:
  - 复杂数学运算(sin/cos/pow多次调用)
  - 多纹理采样(>3次)
  - 动态分支(if/else嵌套)
```

---

## 3. 技术实现规范

### 3.1 标准Shader模板

```glsl
// [shader_name].gdshader
// [中文描述] — [功能简述]
// Godot 4.6, canvas_item shader
// 复杂度: [低/中/高]
// 性能预算: [X]ms/帧

shader_type canvas_item;

// ============================================================
// Uniform变量声明
// ============================================================

// 颜色参数 (总是使用source_color hint)
uniform vec4 main_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// 浮点参数 (总是使用hint_range限制范围)
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// 布尔参数 (Godot 4.6支持)
uniform bool enable_effect = true;

// ============================================================
// 常量定义 (避免magic number)
// ============================================================

const float PI = 3.14159265359;
const vec2 CENTER = vec2(0.5, 0.5);

// ============================================================
// 辅助函数
// ============================================================

// 计算到中心的距离 (移动端优化版本)
float distance_to_center(vec2 uv) {
    vec2 delta = uv - CENTER;
    // 避免sqrt运算，使用近似或平方距离
    return dot(delta, delta);
}

// 脉冲函数 (使用sin而非复杂曲线)
float pulse(float time, float speed) {
    return sin(time * speed) * 0.5 + 0.5;
}

// ============================================================
// Vertex函数
// ============================================================

void vertex() {
    // 顶点变换 (保持简单)
    // 避免复杂矩阵运算
}

// ============================================================
// Fragment函数
// ============================================================

void fragment() {
    // 基础纹理采样 (总是先采样)
    vec4 tex_color = texture(TEXTURE, UV);

    // 效果计算...

    // 输出 (保持alpha通道正确)
    COLOR = vec4(final_rgb, final_alpha);
}
```

### 3.2 Uniform变量命名规范

| 类型 | 命名模式 | 示例 | 说明 |
|------|---------|------|------|
| 颜色 | `[name]_color` | `glow_color`, `burst_color` | 总是source_color hint |
| 强度 | `[name]_intensity` | `glow_intensity` | hint_range(0.0, 2.0) |
| 进度 | `progress` | `progress` | hint_range(0.0, 1.0) |
| 速度 | `[name]_speed` | `pulse_speed` | hint_range(0.0, 5.0) |
| 开关 | `enable_[name]` | `enable_effect` | bool类型 |
| 尺寸 | `[name]_size/width` | `rim_width` | hint_range(0.0, 1.0) |

### 3.3 性能优化规则

#### 禁止项 (移动端)
```glsl
// 禁止使用高精度float
float high_precision;  // 禁止

// 避免复杂三角函数
float complex = sin(sin(x) * cos(y));  // 禁止

// 避免动态循环
for(int i = 0; i < dynamic_value; i++)  // 禁止

// 避免分支
if(condition) {  // 尽量减少，使用mix替代
    color = a;
} else {
    color = b;
}
```

#### 推荐写法
```glsl
// 使用mix替代分支
vec4 color = mix(color_b, color_a, float(condition));

// 使用step替代if
float mask = step(threshold, value);

// 预计算常量
const float INV_PI = 1.0 / 3.14159265359;

// 延迟采样 (只在需要时采样)
vec4 tex_color = enable_effect ? texture(TEXTURE, UV) : vec4(1.0);
```

---

## 4. Shader材质资源组织结构

```
assets/resources/shaders/
├── effects/                    # 特效Shader
│   ├── magic_burst.gdshader           # 魔法爆发
│   ├── star_trail.gdshader            # 星星拖尾 (todo)
│   └── ripple_distortion.gdshader     # 水波纹 (todo)
├── spirit/                     # 精灵相关
│   └── spirit_glow.gdshader           # 词灵发光
├── ui/                         # UI效果 (可选)
│   └── ui_glass.gdshader              # 玻璃效果 (todo)
├── transitions/                # 过渡效果
│   └── transition_wipe.gdshader       # 擦除过渡
└── shared/                     # 共享代码
    └── common.glsl                    # 辅助函数库 (todo)
```

---

## 5. 移动端降级策略

### 5.1 自动降级触发条件

```gdscript
# VFXManager性能监控
if fps < 30:
    shader_degradation = LEVEL_3  # 禁用所有Shader
elif fps < 45:
    shader_degradation = LEVEL_2  # 仅保留必要Shader
elif fps < 55:
    shader_degradation = LEVEL_1  # 降低Shader复杂度
```

### 5.2 降级级别定义

| 级别 | 名称 | 行为 |
|------|------|------|
| 0 | FULL | 所有Shader正常运行 |
| 1 | REDUCED | 降低粒子数量，简化计算 |
| 2 | MINIMAL | 仅保留UI和过渡Shader |
| 3 | DISABLED | 所有Shader禁用，使用ColorRect替代 |

---

## 6. Shader调试方法

### 6.1 实时参数调整

```gdscript
# 在编辑器中实时调整Shader参数
func _process(delta: float) -> void:
    if Engine.is_editor_hint():
        # 通过Inspector调整的参数自动生效
        pass

# 运行时动态调整
func update_shader_progress(progress: float) -> void:
    sprite.material.set_shader_parameter("progress", progress)
```

### 6.2 调试可视化

```gdshader
// 添加调试输出模式
uniform bool debug_mode = false;

void fragment() {
    // 正常计算...

    if (debug_mode) {
        // 可视化UV坐标
        COLOR = vec4(UV.x, UV.y, 0.0, 1.0);
        return;
    }
}
```

### 6.3 性能分析

```gdscript
# 在PerformanceMonitor中
func _process(delta: float) -> void:
    if _shader_enabled:
        var start_time = Time.get_ticks_usec()

        # Shader更新逻辑
        update_shader_parameters()

        var elapsed = Time.get_ticks_usec() - start_time
        if elapsed > 5000:  # 5ms阈值
            push_warning("Shader耗时过高: %d us" % elapsed)
            _trigger_degradation()
```

---

## 7. 实现检查清单

### 7.1 Shader编写检查

- [ ] 文件头包含描述和复杂度标注
- [ ] 所有uniform使用hint_range限制
- [ ] 颜色uniform使用source_color hint
- [ ] 避免高精度float运算
- [ ] 循环使用固定小次数
- [ ] 使用mix替代分支
- [ ] 保持alpha通道正确传递
- [ ] 添加性能预算注释

### 7.2 材质配置检查

- [ ] Shader预加载使用preload()
- [ ] 材质参数初始化完整
- [ ] 降级方案已实现
- [ ] 内存释放逻辑正确

### 7.3 性能验证

- [ ] 单帧耗时 < 5ms
- [ ] FPS稳定在55+
- [ ] 降级触发逻辑正确
- [ ] 内存无泄漏

---

**文档结束**