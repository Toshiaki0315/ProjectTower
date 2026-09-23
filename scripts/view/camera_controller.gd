extends Camera2D

# ---------------------------------------------------
# カメラ操作（ズームと移動）
# - スクロール: マウスホイールで上下、Shift+ホイール（または横ホイール）で左右
# - ズーム: Ctrl（⌘）+マウスホイール / トラックパッドのピンチ（カーソル位置を中心に拡大縮小）
# - 移動:   トラックパッドの2本指スクロール / マウス中ボタンドラッグ / WASD・矢印キー
#           （⌘・Ctrlを押している間はキーでは動かさない。⌘Sのセーブで画面が動かないように）
# ---------------------------------------------------

const DEFAULT_ZOOM := 3.0
const KEY_ZOOM_STEP := 1.25 # ⌘+ / ⌘- で1回に変える拡大率
const MIN_ZOOM := 1.0
const MAX_ZOOM := 6.0
const WHEEL_ZOOM_STEP := 1.15 # ホイール1回あたりの拡大率
const KEY_PAN_SPEED := 600.0  # キー移動の速さ（画面上のpx/秒）
const WHEEL_SCROLL := 48.0    # ホイール1回でスクロールする量（画面上のpx）

var dragging := false

func _ready() -> void:
	zoom = Vector2.ONE * DEFAULT_ZOOM

# 指定したワールド座標が画面中央に来るようにする
func focus_on(world_pos: Vector2) -> void:
	position = world_pos

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT:
				if event.pressed:
					handle_wheel(event)
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

# ホイール: 上下スクロール。Shiftや横ホイールなら左右、Ctrl（⌘）ならズーム
func handle_wheel(event: InputEventMouseButton) -> void:
	var up := event.button_index == MOUSE_BUTTON_WHEEL_UP
	var down := event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	if (up or down) and (event.ctrl_pressed or event.meta_pressed):
		zoom_at(event.position, WHEEL_ZOOM_STEP if up else 1.0 / WHEEL_ZOOM_STEP)
	elif event.button_index == MOUSE_BUTTON_WHEEL_LEFT or (up and event.shift_pressed):
		pan_by_screen(Vector2(-WHEEL_SCROLL, 0))
	elif event.button_index == MOUSE_BUTTON_WHEEL_RIGHT or (down and event.shift_pressed):
		pan_by_screen(Vector2(WHEEL_SCROLL, 0))
	else:
		pan_by_screen(Vector2(0, -WHEEL_SCROLL if up else WHEEL_SCROLL))

func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_CTRL):
		return # ⌘S（セーブ）などのショートカットの文字キーで、画面が動かないようにする
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
# 画面の真ん中を動かさずに拡大・縮小する（⌘+ / ⌘-）
func zoom_by(factor: float) -> void:
	zoom_at(get_viewport_rect().size / 2.0, factor)

# 拡大率を最初の大きさに戻す（⌘0）
func reset_zoom() -> void:
	zoom = Vector2.ONE * DEFAULT_ZOOM

func screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size / 2.0) / zoom.x
