extends RefCounted

## 渲染能力探测 —— 一个地方回答"现在有没有真渲染器"。
##
## 为什么需要这一句判断：`--headless` 用的是 **Dummy 渲染器，不支持 shader**。
## 给 `ShaderMaterial.shader` 赋值会 push 一条引擎 ERROR
## （`shader_set_code`，dummy/storage/material_storage.cpp），而 GUT 把测试期间出现的
## 引擎错误一律算作测试失败 —— 归卷厅提亮层刚落地时，一次弄红了 **107 个用例**。
##
## 所以凡是"建材质 / 挂 shader"的地方都先问这一句：headless 下走**不建材质**的兜底分支，
## 让层级、几何、参数、时间轴这些与渲染后端无关的逻辑仍然能被 GUT 覆盖。
##
## 注意它**不能**回答"这份 shader 编译成功了吗"——headless 下 Dummy 渲染器的
## uniform 列表恒为空，真机上语法错误（例如注释写成 `#`）也会静默失败。
## 那是 `Shader.get_shader_uniform_list().is_empty()` 要回答的问题，见
## `WakeEyeTransition.wake_material()`。

static func supports_shaders() -> bool:
	return DisplayServer.get_name() != "headless"
