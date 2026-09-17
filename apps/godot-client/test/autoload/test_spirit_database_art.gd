extends GutTest

## T60 守卫：每个词灵条目都必须带有可解析的 art 立绘路径，
## 且 SpiritUnlockOverlay 能真正把它加载进立绘槽位（尺寸按稀有度分档）。

const EXPECTED_SPIRIT_COUNT: int = 16
const COMMON_RARE_ART_SIZE: int = 256
const LEGENDARY_ART_SIZE: int = 320


func _get_spirits() -> Array[Dictionary]:
	if SpiritDatabase.current_state != SpiritDatabase.State.LOADED:
		SpiritDatabase.initialize()
	return SpiritDatabase.get_all_spirits()


func test_all_spirits_have_resolvable_art() -> void:
	var spirits: Array[Dictionary] = _get_spirits()
	assert_eq(
		spirits.size(),
		EXPECTED_SPIRIT_COUNT,
		"词灵数据库应含 16 个条目"
	)

	for spirit in spirits:
		var sid: String = str(spirit.get("id", ""))
		var art: String = str(spirit.get("art", ""))
		assert_false(art.is_empty(), "词灵 %s 缺少 art 字段" % sid)
		assert_true(
			ResourceLoader.exists(art),
			"词灵 %s 的 art 路径无法解析：%s" % [sid, art]
		)


func _load_overlay_art(spirit_id: String) -> Texture2D:
	var overlay: SpiritUnlockOverlay = autofree(SpiritUnlockOverlay.new())
	add_child(overlay)
	await get_tree().process_frame
	overlay.display_spirit_unlock(spirit_id)
	return overlay._spirit_image.texture


func test_unlock_overlay_loads_common_spirit_art() -> void:
	var texture: Texture2D = await _load_overlay_art("spirit_sun_001")

	assert_not_null(texture, "解锁浮层应把词灵立绘加载进 _spirit_image")
	if texture != null:
		assert_eq(
			texture.get_width(),
			COMMON_RARE_ART_SIZE,
			"普通词灵立绘应为 256 宽"
		)
		assert_eq(
			texture.get_height(),
			COMMON_RARE_ART_SIZE,
			"普通词灵立绘应为 256 高"
		)


func test_unlock_overlay_loads_legendary_spirit_art_at_larger_size() -> void:
	var texture: Texture2D = await _load_overlay_art("spirit_dragon_001")

	assert_not_null(texture, "传说词灵应能加载立绘")
	if texture != null:
		assert_eq(
			texture.get_width(),
			LEGENDARY_ART_SIZE,
			"传说词灵立绘应为 320 宽"
		)
		assert_eq(
			texture.get_height(),
			LEGENDARY_ART_SIZE,
			"传说词灵立绘应为 320 高"
		)
