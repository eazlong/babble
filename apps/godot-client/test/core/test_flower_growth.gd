# test_flower_growth.gd
# GUT 测试用例 — FlowerGrowth + MagicFlower.FlowerState
# 测试花朵状态枚举、FlowerGrowth 静态工具函数

extends GutTest

const FlowerGrowth = preload("res://assets/scripts/components/FlowerGrowth.gd")

# ── FlowerState 枚举（通过 MagicFlower 脚本获取） ──

func test_flower_state_enum_values():
	# MagicFlower.FlowerState 定义在 MagicFlower.gd
	var MagicFlowerScript = load("res://assets/scripts/components/MagicFlower.gd")
	# 枚举常量应可访问
	assert_eq(MagicFlowerScript.FlowerState.WILTED, 0)
	assert_eq(MagicFlowerScript.FlowerState.INACTIVE, 1)
	assert_eq(MagicFlowerScript.FlowerState.GROWING, 2)
	assert_eq(MagicFlowerScript.FlowerState.BLOOMED, 3)

func test_flower_state_sequential():
	var MagicFlowerScript = load("res://assets/scripts/components/MagicFlower.gd")
	assert_eq(MagicFlowerScript.FlowerState.BLOOMED - MagicFlowerScript.FlowerState.WILTED, 3,
		"WILTED 到 BLOOMED 跨越 3 步")

# ── FlowerGrowth 常量 ──

func test_growth_constants_positive():
	assert_gt(FlowerGrowth.GROWTH_DURATION, 0.0)
	assert_gt(FlowerGrowth.BLOOM_SCALE.x, 1.0, "BLOOM_SCALE 应大于 1（放大）")
	assert_gt(FlowerGrowth.WILTED_SCALE.x, 0.0, "WILTED_SCALE 应大于 0")
	assert_lt(FlowerGrowth.WILTED_SCALE.x, 1.0, "WILTED_SCALE 应小于 1（缩小）")

func test_full_scale_is_unit():
	assert_eq(FlowerGrowth.FULL_SCALE, Vector2(1.0, 1.0))

# ── FlowerGrowth.apply_wilted / apply_inactive（node=null 安全性） ──

func test_apply_wilted_null_sprite_no_crash():
	# 传入 null 不应崩溃
	FlowerGrowth.apply_wilted(null)
	assert_true(true, "null sprite 不崩溃")

func test_apply_inactive_null_sprite_no_crash():
	FlowerGrowth.apply_inactive(null)
	assert_true(true, "null sprite 不崩溃")

func test_play_growth_tween_null_node():
	var result = FlowerGrowth.play_growth_tween(null, null)
	assert_null(result, "null node 应返回 null tween")

# ── apply_wilted 视觉状态（使用真实 ColorRect） ──

func test_apply_wilted_sets_gray_modulate():
	var sprite := ColorRect.new()
	add_child(sprite)
	FlowerGrowth.apply_wilted(sprite)
	assert_eq(sprite.modulate, Color(0.5, 0.5, 0.5, 1.0), "枯萎应为灰色 modulate")
	assert_gt(sprite.rotation, 0.0, "枯萎应有正旋转（下垂）")
	sprite.queue_free()

func test_apply_inactive_resets_modulate():
	var sprite := ColorRect.new()
	add_child(sprite)
	sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)  # 先设为枯萎
	FlowerGrowth.apply_inactive(sprite)
	assert_eq(sprite.modulate, Color.WHITE, "INACTIVE 应重置为白色")
	assert_eq(sprite.rotation, 0.0, "INACTIVE 应无旋转")
	sprite.queue_free()

# ── 花朵颜色默认值 ──

func test_magic_flower_default_color():
	var MagicFlowerScript = load("res://assets/scripts/components/MagicFlower.gd")
	var flower = MagicFlowerScript.new()
	# MagicFlower 需要 Sprite 子节点（@onready var sprite: ColorRect = $Sprite）
	var sprite := ColorRect.new()
	sprite.name = "Sprite"
	flower.add_child(sprite)
	# 添加到场景树触发 _ready()
	add_child(flower)
	assert_eq(flower.flower_color, "red", "默认花朵颜色应为 red")
	assert_eq(flower.get_color(), "red")
	flower.queue_free()
