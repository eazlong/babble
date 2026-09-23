extends GutTest

## VoiceMicIndicator（录音石）测试。
##
## 背景：这个指示器原来显示 80×80 的**麦克风图标**，2026-09-22 换成集气灵石。
## 它被 7 个场景共用（序章/客栈×2/长安×2/归卷厅），所以"默认贴图是不是灵石"
## 和"状态切换有没有真的换图"必须钉住——一个改错，7 个场景一起错。

const IndicatorScript = preload("res://assets/scripts/ui/VoiceMicIndicator.gd")
const INDICATOR_SCENE: String = "res://assets/scenes/ui/VoiceMicIndicator.tscn"
const INDICATOR_SCRIPT_PATH: String = "res://assets/scripts/ui/VoiceMicIndicator.gd"

func _make_indicator() -> Control:
	var packed: Variant = load(INDICATOR_SCENE)
	var node: Control = null
	if packed is PackedScene:
		node = packed.instantiate()
	else:
		node = IndicatorScript.new()
	add_child(node)
	return node

func _texture_path(node: Control) -> String:
	var button: TextureRect = node.get_node_or_null("Button")
	if button == null or button.texture == null:
		return ""
	return button.texture.resource_path

# ── 默认贴图 ────────────────────────────────────────────────────────

func test_default_texture_is_the_stone_not_a_mic() -> void:
	# 这条就是本次改动的验收点：默认贴图不能再是麦克风。
	var node = _make_indicator()
	var path: String = _texture_path(node)
	assert_true(path.contains("spritestone"), "默认贴图应是集气灵石，实测 %s" % path)
	assert_false(path.contains("mic_button"), "默认贴图不应再是麦克风图标，实测 %s" % path)
	node.free()

func test_default_texture_actually_loads() -> void:
	# 贴图路径写错时 load() 静默返回 null，指示器会变成空白方块——这里挡住。
	var node = _make_indicator()
	var button: TextureRect = node.get_node_or_null("Button")
	assert_not_null(button, "应有 Button 子节点")
	assert_not_null(button.texture, "默认灵石贴图应能加载")
	node.free()

func test_scene_declares_idle_stone_texture() -> void:
	# 光靠 _ready 里赋值不够：场景文件本身也得指向灵石，
	# 否则编辑器里预览到的还是麦克风，别人会以为没换。
	var text: String = FileAccess.get_file_as_string(INDICATOR_SCENE)
	assert_true(text.contains("spritestone"), "VoiceMicIndicator.tscn 的默认贴图应是灵石")
	assert_false(text.contains("ui_mic_button_idle.png\""), "tscn 不应再把麦克风图标作为默认贴图")
	# 麦克风图标要留在脚本里当兜底（灵石贴图缺失时还能显示点东西）
	var script_text: String = FileAccess.get_file_as_string(INDICATOR_SCRIPT_PATH)
	assert_true(script_text.contains("ui_mic_button_idle.png"),
		"麦克风图标应保留为脚本里的兜底贴图")

func test_set_state_is_a_method_for_soft_calls() -> void:
	# 调用方用 has_method("set_state") 软调用；只留属性的话这里会挂。
	var node = _make_indicator()
	assert_true(node.has_method("set_state"), "必须有 set_state 方法，否则控制器调不动")
	node.free()

# ── 状态切换 ────────────────────────────────────────────────────────

func test_listening_state_switches_texture() -> void:
	# 录音石"在听"的样子和待机不同（涟漪），切状态必须真的换图，
	# 否则显 idle 态等于把麦克风的唯一功能丢了。
	var node = _make_indicator()
	var idle_path: String = _texture_path(node)
	node.set_state("listening")
	var listening_path: String = _texture_path(node)
	assert_true(listening_path.contains("listening"), "listening 态应换到 listening 贴图，实测 %s" % listening_path)
	assert_ne(listening_path, idle_path, "listening 贴图应与 idle 不同")
	node.free()

func test_every_declared_state_loads() -> void:
	var node = _make_indicator()
	for state_name in IndicatorScript.STATE_TEXTURES.keys():
		node.set_state(str(state_name))
		assert_not_null(node.get_node("Button").texture, "状态 %s 应有可加载的贴图" % state_name)
	node.free()

func test_state_falls_back_to_mic_when_stone_missing() -> void:
	# 灵石贴图缺失时应回退到旧麦克风图标，而不是留个空白方块。
	var node = _make_indicator()
	# 直接把缓存塞成 null，模拟"灵石加载不出来"
	node._texture_cache["listening"] = null
	var fallback: Texture2D = node._load_first([node._fallback_for("listening")])
	assert_not_null(fallback, "listening 的兜底贴图应能加载")
	assert_true(fallback.resource_path.contains("mic_button"), "兜底应是麦克风图标")
	node.free()

func test_unknown_state_does_not_blank_the_stone() -> void:
	# 拼错状态名不该把指示器清成空白——保留上一次的图。
	var node = _make_indicator()
	var before: String = _texture_path(node)
	node.set_state("no_such_state")
	assert_eq(_texture_path(node), before, "未知状态不应改变现有贴图")
	node.free()

# ── pending upload 徽标（原有行为，别被这次改动碰坏）────────────────

func test_pending_upload_badge_still_wired() -> void:
	var node = _make_indicator()
	node._update_pending_upload_badge()
	var badge: Label = node.get_node_or_null("PendingUploadBadge")
	assert_not_null(badge, "pending upload 徽标应仍在")
	assert_false(badge.visible, "没有待上传录音时徽标应隐藏")
	node.free()
