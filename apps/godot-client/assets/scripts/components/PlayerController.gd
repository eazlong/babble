extends CharacterBody2D

@export var speed: float = 200.0
@export var acceleration: float = 1500.0
@export var friction: float = 800.0

@onready var sprite: AnimatedSprite2D = $Sprite

var input_direction: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if input_direction != Vector2.ZERO:
		velocity = velocity.move_toward(input_direction * speed, acceleration * delta)
		sprite.play("walk")

		if input_direction.x < 0:
			sprite.flip_h = true
		elif input_direction.x > 0:
			sprite.flip_h = false
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		sprite.play("idle")

	move_and_slide()

func get_position() -> Vector2:
	return global_position