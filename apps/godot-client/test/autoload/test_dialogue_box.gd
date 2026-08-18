# test_dialogue_box.gd
# GUT测试用例 — DialogueBox (Autoload)
# 测试弹出动画、逐字显示、TTS同步

extends GutTest

const DialogueBoxScript = preload("res://assets/scripts/autoload/DialogueBox.gd")

var dialogue_box

func before_each():
	# DialogueBox is an autoload without class_name; instantiate the script directly
	dialogue_box = DialogueBoxScript.new()
	add_child(dialogue_box)

func after_each():
	if dialogue_box and is_instance_valid(dialogue_box):
		dialogue_box.queue_free()

func test_dialogue_box_layer():
	# 测试CanvasLayer层级
	assert_eq(dialogue_box.layer, 20, "DialogueBox层级应为20（DialogueCanvasLayer）")

func test_initialization():
	# 测试初始化状态
	assert_not_null(dialogue_box.dialogue_panel, "DialoguePanel应被创建")
	assert_not_null(dialogue_box.npc_name_label, "NPCNameLabel应被创建")
	assert_not_null(dialogue_box.message_label, "MessageLabel应被创建")
	assert_not_null(dialogue_box._typing_timer, "TypingTimer应被创建")
	assert_false(dialogue_box.is_showing, "初始状态不应显示")

func test_show_message_popup_animation():
	# 测试弹出动画
	var dialogue_panel = PanelContainer.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.modulate.a = 0.0
	dialogue_panel.scale = Vector2(0.5, 0.5)
	dialogue_box.add_child(dialogue_panel)
	dialogue_box.dialogue_panel = dialogue_panel

	var npc_name_label = Label.new()
	npc_name_label.name = "NPCName"
	dialogue_panel.add_child(npc_name_label)
	dialogue_box.npc_name_label = npc_name_label

	var message_label = Label.new()
	message_label.name = "Message"
	dialogue_panel.add_child(message_label)
	dialogue_box.message_label = message_label

	dialogue_box.show_message("Feifei", "欢迎来到精灵森林！")

	# 验证弹出动画开始
	assert_true(dialogue_panel.visible, "DialoguePanel应可见")
	assert_eq(dialogue_panel.modulate.a, 0.0, "初始alpha应为0（动画开始）")
	assert_eq(dialogue_panel.scale.x, UIAnimationPresets.ScalePop.START_SCALE, "初始缩放应为START_SCALE")

	# 等待动画完成
	await yield_for(0.5)

	assert_almost_eq(dialogue_panel.modulate.a, 1.0, 0.1, "弹出动画后alpha应为1.0")
	assert_almost_eq(dialogue_panel.scale.x, 1.0, 0.1, "弹出动画后缩放应为1.0")

	if dialogue_panel and is_instance_valid(dialogue_panel):
		dialogue_panel.queue_free()

func test_typing_animation():
	# 测试逐字显示动画
	var message_label = Label.new()
	message_label.name = "Message"
	message_label.text = ""
	dialogue_box.add_child(message_label)
	dialogue_box.message_label = message_label

	dialogue_box._start_typing_animation("测试文本")

	# 验证Timer启动
	assert_true(dialogue_box._typing_timer.is_processing(), "TypingTimer应启动")

	# 等待逐字显示
	await yield_for(0.3)

	# 验证部分字符显示
	assert_gt(message_label.text.length(), 0, "应显示部分字符")
	assert_lt(message_label.text.length(), 4, "应尚未显示全部字符")

	# 等待完成
	await yield_for(0.5)

	assert_eq(message_label.text, "测试文本", "应显示完整文本")
	assert_false(dialogue_box._typing_timer.is_processing(), "TypingTimer应停止")

	if message_label and is_instance_valid(message_label):
		message_label.queue_free()

func test_sync_with_tts():
	# 测试TTS同步
	dialogue_box._current_message = "这是测试消息，共十个字符。"
	dialogue_box._typing_speed = 0.05

	dialogue_box.sync_with_tts(3.0)  # 3秒音频

	# 计算预期速度：3秒 / 15字符 = 0.2秒/字符
	var expected_speed = 3.0 / dialogue_box._current_message.length()
	assert_almost_eq(dialogue_box._typing_speed, expected_speed, 0.01, "TypingSpeed应根据音频时长调整")

func test_hide_message():
	# 测试隐藏消息
	dialogue_box.is_showing = true
	dialogue_box.dialogue_panel = PanelContainer.new()
	dialogue_box.dialogue_panel.visible = true
	dialogue_box.add_child(dialogue_box.dialogue_panel)

	dialogue_box.hide_message()

	assert_false(dialogue_box.is_showing, "状态应为不显示")
	assert_false(dialogue_box.dialogue_panel.visible, "DialoguePanel应隐藏")

func test_is_active():
	# 测试isActive状态
	dialogue_box.is_showing = false
	assert_false(dialogue_box.is_active(), "不显示时应返回false")

	dialogue_box.is_showing = true
	assert_true(dialogue_box.is_active(), "显示时应返回true")