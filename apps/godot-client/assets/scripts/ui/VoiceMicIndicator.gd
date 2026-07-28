extends Control

@onready var pending_upload_badge: Label = get_node_or_null("PendingUploadBadge")

func _ready() -> void:
	_update_pending_upload_badge()

func _process(_delta: float) -> void:
	_update_pending_upload_badge()

func _update_pending_upload_badge() -> void:
	if pending_upload_badge == null:
		return
	var count := _pending_upload_count()
	pending_upload_badge.visible = count > 0
	pending_upload_badge.text = str(count)

func _pending_upload_count() -> int:
	var magic_echo_manager := get_node_or_null("/root/MagicEchoManager")
	if magic_echo_manager == null or not magic_echo_manager.has_method("get_pending_uploads"):
		return 0
	var uploads: Variant = magic_echo_manager.call("get_pending_uploads")
	if uploads is Array:
		return uploads.size()
	return 0
