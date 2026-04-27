extends StaticBody2D

@export var npc_id: String = "spark"
@export var npc_name_zh: String = "精灵教练 Spark"
@export var npc_name_en: String = "Spirit Coach Spark"
@export var greeting_zh: String = "你好！我是 Spark，你的语言学习伙伴！"
@export var greeting_en: String = "Hello! I'm Spark, your language learning companion!"

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var dialogue_trigger: Area2D = $DialogueTrigger

var dialogue_state: String = "idle"
var player_in_range: bool = false

func _ready() -> void:
	dialogue_trigger.body_entered.connect(_on_body_entered)
	dialogue_trigger.body_exited.connect(_on_body_exited)
	sprite.play("idle")

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("get_position") and dialogue_state == "idle":
		player_in_range = true
		sprite.play("greeting")
		trigger_dialogue()

func _on_body_exited(body: Node2D) -> void:
	if body.has_method("get_position"):
		player_in_range = false

func trigger_dialogue() -> void:
	if dialogue_state != "idle":
		return

	dialogue_state = "active"

	var npc_name = GameManager.current_lang == "zh" ? npc_name_zh : npc_name_en
	var greeting = GameManager.current_lang == "zh" ? greeting_zh : greeting_en

	DialogueManager.start_npc_dialogue(npc_id, greeting)

func get_greeting() -> String:
	return GameManager.current_lang == "zh" ? greeting_zh : greeting_en

func get_npc_name() -> String:
	return GameManager.current_lang == "zh" ? npc_name_zh : npc_name_en

func end_dialogue() -> void:
	dialogue_state = "idle"
	sprite.play("idle")

func set_emotion(emotion: String) -> void:
	sprite.play(emotion)