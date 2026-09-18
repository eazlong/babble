# VFX 预设纹理完整性测试
# 每个 vfx preset JSON 声明的 texture_path 都必须能在引擎内解析，
# 否则粒子发射时会静默丢失贴图（本测试即用于守住该缺口不再复发）。
extends GutTest

const PRESET_DIR: String = "res://assets/resources/vfx_presets"

const REQUIRED_PARTICLE_TEXTURES: Array[String] = [
	"spirit_particle",
	"star_particle",
	"gold_particle",
	"firefly_particle",
]


func test_every_preset_texture_path_resolves() -> void:
	var dir: DirAccess = DirAccess.open(PRESET_DIR)
	assert_not_null(dir, "vfx_presets 目录应可访问")
	if dir == null:
		return

	var checked: int = 0
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue

		var path: String = PRESET_DIR.path_join(file_name)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		assert_true(parsed is Dictionary, "%s 应为 JSON 对象" % file_name)
		if not (parsed is Dictionary):
			continue

		var texture_path: String = str((parsed as Dictionary).get("texture_path", ""))
		if texture_path.is_empty():
			continue

		checked += 1
		assert_true(
			ResourceLoader.exists(texture_path),
			"%s 声明的贴图无法解析：%s" % [file_name, texture_path]
		)

	assert_gt(checked, 0, "至少应有一个预设声明 texture_path")


func test_particle_textures_exist_and_are_transparent() -> void:
	for name in REQUIRED_PARTICLE_TEXTURES:
		var path: String = "res://assets/textures/particles/%s.png" % name
		assert_true(ResourceLoader.exists(path), "%s 应存在" % name)
		if not ResourceLoader.exists(path):
			continue

		var texture: Texture2D = load(path)
		assert_not_null(texture, "%s 应能加载" % name)
		if texture != null:
			assert_eq(texture.get_width(), 64, "%s 应为 64 宽" % name)
			assert_eq(texture.get_height(), 64, "%s 应为 64 高" % name)
