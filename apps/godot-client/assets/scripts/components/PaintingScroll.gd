## 墙上画卷（词灵书阁的入口）：独立精灵，自己管三段表演 —— 睡着 / 亮起来 / 飞向玩家。
##
## 为什么把它独立成一个精灵（而不是烤进房间背景、或控制器里那两张 TextureRect）：
## 口令命中后这层美术必须**脱离房间视图**继续演 —— 先在墙上亮起来，再整幅飞向玩家把
## 屏幕盖满，等书阁在它下面淡入之后，才由它自己淡出。挂在房间视图（OwnerRoomView）下面
## 时，控制器一切视图就会连它一起按掉（`_show_view` 会把非目标视图 `visible = false`），
## 画会在半空消失。
##
## 因此本组件带**表演锁**：表演进行中（`_performing`）外部只能写"待机可见性"
## （`stage_visible`，只记进 `_staged_visible`），等表演结束再兑现。控制器在 `_show_view`
## 里只调这一个入口，不需要知道画此刻在做什么。
##
## 坐标：根节点在**默认画布（世界空间）**——房间美术在 `CanvasLayer(-50)`，所以画天然落在
## 墙上、又在 HUD(10)/overlay(30) 之下。场景无 Camera2D，于是"飞向玩家"就是
## "移到舞台中心 + 放大到盖满舞台"。
extends Sprite2D

## 表演阶段。控制器与测试靠它判断画现在能不能被切视图按掉。
enum Phase { DORMANT, AWAKE, FLYING, SPENT }

signal awakened()
signal flight_finished()

## 舞台尺寸 = 房间美术的坐标画布。控制器里所有道具（画卷 902,282 / 腓腓）
## 都按这套 1920×1080 坐标摆放，`_add_texture` 也把背景写死成这个尺寸。所以"屏幕中心"
## 与"盖满屏幕"必须按舞台算，**不能**按窗口实际像素算：窗口一旦不是 16:9（expand 拉伸、
## 全屏、开发机上手动拉大），两者能差出几百像素，画会飞到墙外面去。
const STAGE_SIZE: Vector2 = Vector2(1920, 1080)
## 盖满舞台的余量：贴图 198×351 与 16:9 不同比例，按 max 比例放大后短边正好贴边，
## 留 6% 免得收尾时边缘露墙。
const COVER_MARGIN: float = 1.06
const AWAKE_SECONDS: float = 0.85
const FLIGHT_SECONDS: float = 1.15
const DISSOLVE_SECONDS: float = 0.5
## 与房间视图淡入同一拍（控制器 `_show_view` 的 0.45s）：画和房间一起出现，
## 否则画会先"啪"地跳在还没淡入的墙上。
const STAGE_FADE_SECONDS: float = 0.45
const GLOW_ALPHA_AWAKE: float = 0.5
const GLOW_ALPHA_FLIGHT: float = 0.95
## 苏醒 / 扑到脸上时的暖色提亮。modulate 超过 1 是提亮（不是裁剪），"画在发光"就靠
## 它 + 光晕两层，不需要新美术。
const AWAKE_TINT: Color = Color(1.06, 1.02, 0.94, 1.0)
const FLIGHT_TINT: Color = Color(1.18, 1.12, 0.98, 1.0)

var phase: int = Phase.DORMANT

## 待机可见性（控制器 `_show_view` 写）。表演进行中只记不兑现。
var _staged_visible: bool = true
## 已经兑现的可见性：与 `_staged_visible` 相等时不再动它，
## 否则表演刚结束就会被 `_apply_staged_visibility` 重放一次淡入（画闪一下）。
var _applied_visible: bool = true
var _performing: bool = false
var _awake_art: Sprite2D
var _wall_glow: Sprite2D
var _home_position: Vector2
var _home_scale: Vector2
var _home_modulate: Color


func _ready() -> void:
	_awake_art = get_node_or_null("AwakeArt") as Sprite2D
	_wall_glow = get_node_or_null("WallGlow") as Sprite2D
	_home_position = position
	_home_scale = scale
	_home_modulate = modulate
	_applied_visible = visible
	reset_to_dormant()


# ── 三段表演 ──────────────────────────────────────────────────────────

## 亮起来：画心从沉睡态换到苏醒态，暖光晕起亮，整体提亮一拍再回落。
## 协程，但**不要求**调用方 await —— 控制器要让它与画卷那句台词同拍。
func awaken(speed_scale: float = 1.0) -> void:
	if phase != Phase.DORMANT:
		return
	var factor := _speed(speed_scale)
	_performing = true
	var tween := create_tween()
	tween.set_parallel(true)
	if _awake_art:
		tween.tween_property(_awake_art, "modulate:a", 1.0, AWAKE_SECONDS * factor) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	if _wall_glow:
		tween.tween_property(_wall_glow, "modulate:a", GLOW_ALPHA_AWAKE, AWAKE_SECONDS * factor) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate", AWAKE_TINT, AWAKE_SECONDS * factor * 0.45) \
		.set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "modulate", _home_modulate, AWAKE_SECONDS * factor * 0.55)
	await tween.finished
	phase = Phase.AWAKE
	_performing = false
	_apply_staged_visibility()
	awakened.emit()


## 飞向玩家：整幅画边放大边扑到舞台中心，收尾时**盖满舞台**——
## 玩家最后看到的是画里的小世界填满屏幕，书阁就从这张满屏的画里淡出来。
## 视觉重心全在缩放上（198→约 2050 px）：位置只挪几十像素，读起来是"画朝我扑过来"。
func fly_to_player(speed_scale: float = 1.0) -> void:
	if phase == Phase.FLYING or phase == Phase.SPENT:
		return
	var factor := _speed(speed_scale)
	_performing = true
	phase = Phase.FLYING
	var cover := cover_scale_for(STAGE_SIZE)
	var tween := create_tween()
	tween.set_parallel(true)
	# EASE_IN：先慢后快，收尾那一下才有"扑到脸上"的加速度。
	tween.tween_property(self, "position", STAGE_SIZE * 0.5, FLIGHT_SECONDS * factor) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "scale", Vector2(cover, cover), FLIGHT_SECONDS * factor) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate", FLIGHT_TINT, FLIGHT_SECONDS * factor) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	if _wall_glow:
		tween.tween_property(_wall_glow, "modulate:a", GLOW_ALPHA_FLIGHT, FLIGHT_SECONDS * factor) \
			.set_ease(Tween.EASE_IN)
	await tween.finished
	# 这里**不**落回待机可见性：画还要留在满屏状态，等书阁在它下面淡入。
	flight_finished.emit()


## 淡出：把下面已经淡入的世界露出来 —— 书阁正是这样"从画里出现"的。
func dissolve(speed_scale: float = 1.0) -> void:
	if phase != Phase.FLYING:
		return
	var factor := _speed(speed_scale)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, DISSOLVE_SECONDS * factor) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished
	phase = Phase.SPENT
	_performing = false
	_apply_staged_visibility()


# ── 待机可见性（控制器唯一入口）────────────────────────────────────────

## 由控制器 `_show_view` 调用：画只在主人房视图里出现。
## 表演进行中**只记不兑现** —— 切视图那一帧正在飞的画不能被按掉。
func stage_visible(should_show: bool) -> void:
	_staged_visible = should_show
	if _performing:
		return
	_apply_staged_visibility()


## 回到沉睡态（初始态 / 测试用）。
func reset_to_dormant() -> void:
	phase = Phase.DORMANT
	_performing = false
	_restore_home_transform()
	if _awake_art:
		_awake_art.modulate.a = 0.0
	if _wall_glow:
		_wall_glow.modulate.a = 0.0


func is_performing() -> bool:
	return _performing


func is_awake() -> bool:
	return phase != Phase.DORMANT


## 放大到能盖满舞台的比例（长边短边都要盖住）。
func cover_scale_for(stage_size: Vector2) -> float:
	var tex_size := _texture_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0 or stage_size.x <= 0.0 or stage_size.y <= 0.0:
		return 1.0
	return maxf(stage_size.x / tex_size.x, stage_size.y / tex_size.y) * COVER_MARGIN


## 画此刻在舞台上的实际尺寸（贴图尺寸 × 缩放）。
func drawn_size() -> Vector2:
	return _texture_size() * scale


## 飞完之后画必须盖满舞台 —— 盖不满就会在书阁淡入时露出墙，穿帮。
func covers_stage() -> bool:
	var drawn := drawn_size()
	return drawn.x >= STAGE_SIZE.x and drawn.y >= STAGE_SIZE.y


# ── 内部 ──────────────────────────────────────────────────────────────

func _speed(speed_scale: float) -> float:
	# 测试把 2.5s 的表演压到几十毫秒；0 会让补间时长为 0（Godot 会报警告）。
	return maxf(speed_scale, 0.001)


func _texture_size() -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return texture.get_size()


## 把画放回墙上原位。首演之前与重演之前都要走一遍：飞完那一版留着
## 满屏的 scale 与透明的 modulate，不复位的话再进主人房会看到一张罩住全屏的透明画。
func _restore_home_transform() -> void:
	position = _home_position
	scale = _home_scale
	modulate = _home_modulate


func _apply_staged_visibility() -> void:
	if _staged_visible == _applied_visible:
		return
	if _staged_visible:
		_enter_stage()
	else:
		visible = false
		_applied_visible = false


## 上台：复位 + 与房间视图同一拍淡入。
## 画心（`AwakeArt`）的明暗**故意不复位**：画卷醒了就不再睡回去，
## 之后回主人房看到的应该还是那张亮着的画。
func _enter_stage() -> void:
	_restore_home_transform()
	visible = true
	_applied_visible = true
	if STAGE_FADE_SECONDS <= 0.0:
		modulate.a = 1.0
		return
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, STAGE_FADE_SECONDS) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
