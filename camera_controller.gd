extends Camera2D

# ---------------------------------------------------
# カメラ操作（ズームと移動）
# - ズーム: マウスホイール / トラックパッドのピンチ（カーソル位置を中心に拡大縮小）
# - 移動:   トラックパッドの2本指スクロール / マウス中ボタンドラッグ / WASD・矢印キー
# ---------------------------------------------------

const DEFAULT_ZOOM := 3.0
const MIN_ZOOM := 1.0
const MAX_ZOOM := 6.0
const WHEEL_ZOOM_STEP := 1.15 # ホイール1回あたりの拡大率
const KEY_PAN_SPEED := 600.0  # キー移動の速さ（画面上のpx/秒）

var dragging := false

func _ready() -> void:
	zoom = Vector2.ONE * DEFAULT_ZOOM

# 指定したワールド座標が画面中央に来るようにする
func focus_on(world_pos: Vector2) -> void:
	position = world_pos

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_at(event.position, WHEEL_ZOOM_STEP)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_at(event.position, 1.0 / WHEEL_ZOOM_STEP)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_MIDDLE:
				dragging = event.pressed
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		pan_by_screen(-event.relative)
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		# deltaは画面上の移動量に近い値なので、見た目の速さが一定になるよう係数をかける
		pan_by_screen(event.delta * 20.0)

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO:
		pan_by_screen(dir.normalized() * KEY_PAN_SPEED * delta)

# 画面上の移動量（px）だけカメラを動かす。ズーム中でも見た目の速さが同じになる
func pan_by_screen(screen_delta: Vector2) -> void:
	position += screen_delta / zoom

# 画面上の点screen_posの下にあるワールド座標を固定したまま、ズームをfactor倍する
func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old_zoom := zoom.x
	var new_zoom := clampf(old_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var offset_from_center := screen_pos - get_viewport_rect().size / 2.0
	position += offset_from_center * (1.0 / old_zoom - 1.0 / new_zoom)
	zoom = Vector2.ONE * new_zoom

# 画面上の点に写っているワールド座標
func screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size / 2.0) / zoom.x
