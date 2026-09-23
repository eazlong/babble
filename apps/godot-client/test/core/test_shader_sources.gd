extends GutTest

## 全项目 shader 源码约束。
##
## 由来（真事）：`wake_eye_open.gdshader` 每一行注释都以 `#` 开头，而 Godot 4 把 `#`
## 当**预处理指令**（`#define` / `#include` / `#ifdef` …），`# 注释` 不是合法指令
## → **整份 shader 静默编译失败**：材质还在、`set_shader_parameter()` 不报错、
## 画面却完全不响应。序章的睁眼过场因此退化成"一帧静止黑图"，一直没人发现。
##
## headless（Dummy 渲染器）拿不到编译结果 —— 它的 uniform 列表恒为空，分不出
## "编译成功"和"编译失败"。所以这条约束只能在**源码层面**守：注释必须是 `//`。

const SHADER_DIR: String = "res://assets/resources/shaders"


## 递归收集目录下所有 .gdshader。
func _collect_shaders(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_shaders(full, out)
		elif entry.ends_with(".gdshader"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func test_shader_dir_is_not_empty() -> void:
	# 前置条件：目录扫描真的扫到了东西（写错路径会让下面几条测试假绿）。
	var shaders: Array[String] = []
	_collect_shaders(SHADER_DIR, shaders)
	assert_gt(shaders.size(), 0, "应至少扫到一份 shader（实际=%d）" % shaders.size())


func test_no_shader_uses_hash_comments() -> void:
	# `#` 开头的行 = 预处理指令位；`# 注释` / `## 标题` 会让整份 shader 编译失败。
	var shaders: Array[String] = []
	_collect_shaders(SHADER_DIR, shaders)
	for path in shaders:
		var offending: Array[String] = []
		for line in _read(path).split("\n"):
			if line.begins_with("#"):
				offending.append(line.strip_edges())
		assert_eq(offending.size(), 0,
			"%s 的 `#` 开头注释行 = %s（应为空：`#` 是预处理指令位，会让整份 shader 静默编译失败，注释只能用 //）" % [
				path, offending])


func test_wake_eye_shader_is_present_and_declares_the_uniforms_the_component_sets() -> void:
	# 组件按名字设参数；shader 改名/删 uniform 会**静默无效**（set_shader_parameter 不报错）。
	var path: String = "res://assets/resources/shaders/effects/wake_eye_open.gdshader"
	assert_true(ResourceLoader.exists(path), "睁眼过场 shader 应存在：%s" % path)
	var source := _read(path)
	assert_ne(source, "", "睁眼过场 shader 源码应可读")
	for uniform_name in ["eye_center_left", "eye_center_right", "eye_half_width",
			"lid_upper_y", "lid_lower_y", "lid_corner_y",
			"lid_upper_y_right", "lid_lower_y_right", "lid_corner_y_right",
			"lid_arch_upper", "lid_arch_lower", "lid_shade", "overlay_alpha"]:
		assert_true(source.contains("uniform ") and source.contains(uniform_name),
			"shader 应声明 uniform %s" % uniform_name)
