extends GutTest

## 「画中小世界」唤醒演出的接线契约（蜃影客栈主人房）。
##
## 需求：把画独立成精灵，玩家**说完**「画中小世界」之后，画亮起来，然后飞向玩家。
##
## 四件事必须同时成立，缺一件演出就是错的：
## 1. 画是**场景根下的独立精灵**，不属于任何房间视图 —— 控制器切到书阁时
##    `_show_view` 会把非目标视图 `visible = false`，画挂在 OwnerRoomView 里就会在半空消失；
## 2. 画**只在口令命中之后**才亮 —— 原先 `_start_voice_listening()` 里"一进监听就换苏醒贴图"
##    是反的：玩家还没开口画就亮了，说完反而没有变化；
## 3. 亮 → 飞 → 淡出三步齐全，且书阁在满屏的画**下面**淡入，最后由画自己淡出露出来；
## 4. 主人房底图拆层后，立轴那一层**只能画一遍**（装裱作为 MountArt 进了 WallPainting，
##    控制器不再补画），灯笼那一层则必须补回来（底板上那块是留白的）。

const SCENE_PATH: String = "res://assets/scenes/MirageInnIntroduction.tscn"
const CONTROLLER_PATH: String = "res://assets/scripts/scenes/MirageInnIntroductionController.gd"
const PAINTING_SCRIPT_PATH: String = "res://assets/scripts/components/PaintingScroll.gd"
## 背景里烤着的那张画心（实测 x908-1092, y288-624），精灵按 198×351 居中盖住它。
const PAINTING_HOME: Vector2 = Vector2(1001, 457.5)


func _source(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s 应能读取" % path)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## 取某个顶层函数的函数体（从函数头起到下一个顶层 `func ` 之前）。
## 用来把"接线"钉在某一个函数里：`_start_voice_listening` 不该碰画，
## `_continue_after_scroll_call` 才是画的三步。
func _function_body(source: String, header: String) -> String:
	var start := source.find(header)
	if start < 0:
		return ""
	var rest := source.substr(start + header.length())
	var next := rest.find("\nfunc ")
	if next < 0:
		return rest
	return rest.substr(0, next)


# ── 画是场景根下的独立精灵 ───────────────────────────────────────────

func test_intro_scene_owns_the_painting_as_a_root_level_sprite() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	assert_not_null(packed, "MirageInnIntroduction.tscn 应能加载")
	if packed == null:
		return
	var scene: Node = packed.instantiate()
	var painting: Node = scene.get_node_or_null("WallPainting")
	assert_not_null(painting, "主人房应有墙上画卷 WallPainting")
	if painting != null:
		assert_true(painting is Sprite2D, "画卷必须是独立精灵（Sprite2D），不是房间视图里的 TextureRect")
		assert_eq(
			painting.get_parent(), scene,
			"画卷必须挂在场景根下：挂在房间视图里时，控制器一切视图就会把正在飞的画一起按掉"
		)
		assert_not_null(painting.get_script(), "画卷应挂脚本")
		if painting.get_script() != null:
			assert_eq(
				painting.get_script().resource_path, PAINTING_SCRIPT_PATH,
				"画卷应挂 PaintingScroll.gd"
			)
		assert_eq(painting.position, PAINTING_HOME, "画卷应贴住背景里那张画心")
		assert_false(painting.visible, "开场画卷待机：由 _show_view 随主人房视图一起请上台")
		assert_true(painting.z_index > 0, "画卷要画在世界内容（腓腓）之上，才不会在飞行途中被切开")
	assert_false(
		scene.get_node_or_null("WorldLayer/VisualRoot/OwnerRoomView/ScrollDormant") != null,
		"旧的代码拼贴画卷不应再挂在房间视图里"
	)
	scene.free()


func test_controller_no_longer_builds_the_painting_from_texture_rects() -> void:
	var source := _source(CONTROLLER_PATH)
	assert_false(source.contains("ScrollDormant"), "旧的两张 TextureRect 拼贴（ScrollDormant）应已删除")
	assert_false(source.contains("ScrollAwake"), "旧的两张 TextureRect 拼贴（ScrollAwake）应已删除")
	assert_false(source.contains("_set_scroll_awake"), "旧的整体换贴图函数应已删除")
	assert_false(
		source.contains("scroll_dormant_prop") or source.contains("scroll_awake_prop"),
		"画卷道具句柄应已删除（画由组件事务自己管）"
	)


# ── 分层底图：立轴只能画一遍 ────────────────────────────────────────
#
# 主人房底图已拆层（灯笼 / 画 / 其它）。这里守两条：
# 1. 底板那一块在底板上是空白的 → 灯笼必须单独补一层，否则屋顶吊灯变成一个洞；
# 2. 立轴那一层**不能**由控制器补画 —— 装裱已经作为 `MountArt` 进了 WallPainting，
#    控制器再画一遍就是一幅画叠两遍（这正是"介绍场景也换分层底图"要躲的坑）。

func test_owner_room_uses_the_layered_background_with_a_lantern_layer() -> void:
	var source := _source(CONTROLLER_PATH)
	assert_true(
		source.contains("mirage_inn_owner_room_layer_plate.png"),
		"主人房应用分层底图的底板（..._layer_plate.png）"
	)
	assert_true(
		source.contains("mirage_inn_owner_room_layer_lantern.png"),
		"灯笼要从分层底图里补一层回来（底板上那块是留白的）"
	)
	assert_false(
		source.contains("mirage_inn_owner_room_bg.png"),
		"扁平底图（..._owner_room_bg.png）应退役：它把灯笼和画都烤在一起了"
	)


func test_scroll_layer_is_drawn_only_by_the_painting_sprite() -> void:
	var source := _source(CONTROLLER_PATH)
	assert_false(
		source.contains("owner_room_layer_scroll"),
		"控制器不应补画立轴那一层：装裱已作为 MountArt 进了 WallPainting，两处都画就是一幅画叠两遍"
	)
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		return
	var scene: Node = packed.instantiate()
	var painting: Node = scene.get_node_or_null("WallPainting")
	if painting == null:
		scene.free()
		return
	var mount: Sprite2D = painting.get_node_or_null("MountArt")
	assert_not_null(mount, "立轴那一层应由 WallPainting 的 MountArt 承担")
	if mount != null:
		assert_not_null(mount.texture, "MountArt 应有贴图")
		if mount.texture != null:
			assert_true(
				mount.texture.resource_path.ends_with("mirage_inn_owner_room_layer_scroll.png"),
				"MountArt 用的应是分层底图里的立轴那一层，实际=%s" % mount.texture.resource_path
			)
	scene.free()


# ── 亮起来必须挂在口令命中之后 ───────────────────────────────────────

func test_listening_alone_does_not_light_the_painting() -> void:
	var source := _source(CONTROLLER_PATH)
	var body := _function_body(source, "func _start_voice_listening")
	assert_false(body.is_empty(), "应能取到 _start_voice_listening 的函数体")
	assert_false(
		body.contains("wall_painting"),
		"开始监听不应碰画：原先一进监听就让它亮，玩家还没开口画就亮了，说完反而没有变化"
	)


func test_passphrase_runs_light_up_then_flight_then_dissolve() -> void:
	var source := _source(CONTROLLER_PATH)
	var body := _function_body(source, "func _continue_after_scroll_call")
	assert_false(body.is_empty(), "应能取到 _continue_after_scroll_call 的函数体")
	var awaken_at := body.find("wall_painting.awaken()")
	var fly_at := body.find("wall_painting.fly_to_player()")
	var dissolve_at := body.find("wall_painting.dissolve()")
	assert_true(awaken_at >= 0, "口令命中后应先让画亮起来")
	assert_true(fly_at > awaken_at, "亮起来之后才是飞向玩家")
	assert_true(dissolve_at > fly_at, "飞完留到书阁淡入之后，再由画自己淡出")
	# 亮起来不能 await：它要和画卷那句台词同拍（台词在响、画在亮）。
	assert_false(
		body.contains("await wall_painting.awaken()"),
		"亮起来不应 await：否则台词要等画亮完才开口"
	)


func test_library_view_fades_in_before_the_painting_dissolves() -> void:
	var source := _source(CONTROLLER_PATH)
	var body := _function_body(source, "func _continue_after_scroll_call")
	var show_at := body.find("_show_view(library_view)")
	var dissolve_at := body.find("wall_painting.dissolve()")
	assert_true(show_at >= 0, "口令命中后应切到书阁视图")
	assert_true(
		dissolve_at > show_at,
		"书阁要先把视图淡入（在满屏的画下面），画再淡出 —— 反过来的话会先露出空背景再出现书阁"
	)


func test_painting_follows_the_owner_room_view_only() -> void:
	var source := _source(CONTROLLER_PATH)
	var body := _function_body(source, "func _show_view")
	assert_true(
		body.contains("_sync_wall_painting(target == owner_room_view)"),
		"切视图时应把画交给待机可见性（组件在表演期间会压后兑现）"
	)
