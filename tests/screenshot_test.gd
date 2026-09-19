extends SceneTree

# ---------------------------------------------------
# 画面確認用テスト
# main.tscnを起動し、実際のクリック操作を再現して各段階のスクリーンショットを保存する。
#
# 実行方法（ウィンドウ付きで起動する。--headlessでは描画されないので不可）:
#   godot --path . -s res://tests/screenshot_test.gd -- <保存先ディレクトリ>
# 保存先を省略すると user://screenshots に保存する。
# ---------------------------------------------------

var main: Node2D
var out_dir: String
var failures: Array[String] = []

func _init() -> void:
	var args = OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://screenshots")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# シナリオごとにゲームを起動し直して、前のシナリオの影響を受けないようにする
	for scenario in [run_build_scenario, run_stairs_scenario, run_camera_scenario]:
		await start_main()
		await scenario.call()
	Engine.time_scale = 1.0

	if failures.is_empty():
		print("RESULT: ALL PASSED")
	else:
		print("RESULT: FAILED")
		for f in failures:
			print("  - ", f)
	quit(0 if failures.is_empty() else 1)

func start_main() -> void:
	if main:
		main.queue_free()
		await wait_frames(1)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait_frames(3)

# ---------------------------------------------------
# シナリオ1: 建設・撤去とモード表示
# ---------------------------------------------------
func run_build_scenario() -> void:
	print("[シナリオ] 建設・撤去")
	var start_funds: int = main.funds
	await capture("build_01_start")

	# 1. 階段ボタンをクリック → 階段が[選択中]になる
	await click_button(main.mode_buttons["stairs"])
	check(main.current_mode == "stairs", "階段ボタンでモードがstairsになる")
	check(main.mode_buttons["stairs"].text.contains("[選択中]"), "階段ボタンに[選択中]が付く")
	check(not main.mode_buttons["office"].text.contains("[選択中]"), "オフィスボタンから[選択中]が外れる")
	await capture("build_02_stairs_selected")

	# 2. 空マスを左クリック → 階段を建設（-5万円）
	var stairs_cell := Vector2i(-4, 20)
	await click_cell(stairs_cell, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(stairs_cell) == "stairs", "左クリックで階段が建つ")
	check(main.funds == start_funds - 50000, "階段の建設費5万円が引かれる")

	# 3. オフィスに切り替えて左クリック → オフィスを建設（-10万円）
	await click_button(main.mode_buttons["office"])
	var office_cell := Vector2i(2, 20)
	await click_cell(office_cell, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(office_cell) == "office", "左クリックでオフィスが建つ")
	check(main.funds == start_funds - 150000, "オフィスの建設費10万円が引かれる")
	await capture("build_03_built")

	# 4. 建てた階段を右クリック → 撤去（+2.5万円）
	await click_cell(stairs_cell, MOUSE_BUTTON_RIGHT)
	check(main.is_cell_empty(stairs_cell), "右クリックで階段が撤去される")
	check(main.tile_map.get_cell_source_id(stairs_cell) == -1, "撤去したマスのタイルが消える")
	check(main.funds == start_funds - 125000, "階段の半額2.5万円が払い戻される")

	# 5. 事前配置のタイルを右クリック → 撤去（+5万円）
	var preset_cell := Vector2i(0, 15)
	await click_cell(preset_cell, MOUSE_BUTTON_RIGHT)
	check(main.is_cell_empty(preset_cell), "事前配置のタイルも撤去できる")
	check(main.funds == start_funds - 75000, "オフィスの半額5万円が払い戻される")

	# 6. 空マスを右クリック → 何も起きない
	await click_cell(Vector2i(-10, 21), MOUSE_BUTTON_RIGHT)
	check(main.funds == start_funds - 75000, "空マスの右クリックでは資金が変わらない")
	await capture("build_04_demolished")

# ---------------------------------------------------
# シナリオ2: 階段による移動
# 事前配置のブロック（y=15〜18）の右隣に階段を置き、その上の階にオフィスを並べる。
# 住人はブロック上段(0,15)から、階段(8,15)→(8,14)を通って上の階(4,14)へ向かう。
# ---------------------------------------------------
func run_stairs_scenario() -> void:
	print("[シナリオ] 階段による移動")
	await click_button(main.mode_buttons["stairs"])
	await click_cell(Vector2i(8, 15), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for x in range(4, 9):
		await click_cell(Vector2i(x, 14), MOUSE_BUTTON_LEFT)
	await click_cell(Vector2i(-10, 20), MOUSE_BUTTON_LEFT) # どこにもつながらない孤立したオフィス
	
	# 移動ルール
	check(main.can_move(Vector2i(8, 15), Vector2i(8, 14)), "階段マスから上の階へ移動できる")
	check(main.can_move(Vector2i(8, 14), Vector2i(8, 15)), "上の階から階段マスへ降りられる")
	check(not main.can_move(Vector2i(7, 15), Vector2i(7, 14)), "オフィス同士は上下に移動できない")
	check(not main.can_move(Vector2i(8, 15), Vector2i(9, 15)), "空マスへは移動できない")
	
	# 住人を配置
	await click_button(main.mode_buttons["resident"])
	var start := Vector2i(0, 15)
	await click_cell(start, MOUSE_BUTTON_LEFT)
	check(main.residents.size() == 1, "住人モードでクリックすると住人が配置される")
	var resident = main.residents[0]
	check(resident.cell == start and resident.selected, "配置した住人が選択状態になる")
	
	# 経路のない行き先 → 移動しない
	await click_cell(Vector2i(-10, 20), MOUSE_BUTTON_LEFT)
	check(not resident.is_moving(), "経路のない行き先では移動しない")
	check(main.message_label.text.contains("経路がありません"), "経路がないことがメッセージで表示される")
	
	# 上の階へ移動
	var goal := Vector2i(4, 14)
	await click_cell(goal, MOUSE_BUTTON_LEFT)
	check(resident.is_moving(), "上の階を指定すると移動を始める")
	check(resident.path.has(Vector2i(8, 15)) and resident.path.has(Vector2i(8, 14)), "経路が階段を通っている")
	check(not resident.selected, "移動指示のあと住人の選択が外れる")
	
	Engine.time_scale = 4.0 # 歩く様子を早送りする
	await wait_until(func(): return resident.cell == Vector2i(8, 15), 10.0)
	await capture("stairs_01_walking")
	await wait_until(func(): return not resident.is_moving(), 10.0)
	Engine.time_scale = 1.0
	check(resident.cell == goal, "住人が階段を使って上の階の目的地に着く")
	await capture("stairs_02_arrived")
	
	# 足元を撤去 → 住人は退場する
	await click_cell(goal, MOUSE_BUTTON_RIGHT)
	await wait_frames(2)
	check(not is_instance_valid(resident), "足元を撤去すると住人が退場する")

# ---------------------------------------------------
# シナリオ3: カメラのズームと移動
# ---------------------------------------------------
func run_camera_scenario() -> void:
	print("[シナリオ] カメラ操作")
	var cam = main.camera
	check(is_equal_approx(cam.zoom.x, cam.DEFAULT_ZOOM), "起動時は%.0f倍にズームしている" % cam.DEFAULT_ZOOM)
	check(cam.position.is_equal_approx(Vector2(0, 272)), "起動時はビルが画面中央に来る")
	await capture("camera_01_default")
	
	# ホイールでズームイン → カーソル下の位置は動かない
	var screen_pos := Vector2(900, 500)
	var world_before: Vector2 = cam.screen_to_world(screen_pos)
	await scroll_wheel(screen_pos, MOUSE_BUTTON_WHEEL_UP, 3)
	check(cam.zoom.x > cam.DEFAULT_ZOOM, "ホイール上でズームインする")
	check(cam.screen_to_world(screen_pos).is_equal_approx(world_before), "ズームしてもカーソル下の位置がずれない")
	check(main.funds == 1000000, "ホイール操作で建設されない")
	
	# ズーム後もクリックしたマスに正しく建設できる
	await click_cell(Vector2i(6, 14), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(6, 14)) == "office", "ズーム後もクリックしたマスに建設できる")
	await capture("camera_02_zoomed_in")
	
	# ズームの上限・下限
	await scroll_wheel(screen_pos, MOUSE_BUTTON_WHEEL_UP, 30)
	check(is_equal_approx(cam.zoom.x, cam.MAX_ZOOM), "ズームインは%.0f倍で止まる" % cam.MAX_ZOOM)
	await scroll_wheel(screen_pos, MOUSE_BUTTON_WHEEL_DOWN, 40)
	check(is_equal_approx(cam.zoom.x, cam.MIN_ZOOM), "ズームアウトは%.0f倍で止まる" % cam.MIN_ZOOM)
	
	# トラックパッドのピンチ
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = screen_pos
	pinch.factor = 2.0
	root.push_input(pinch)
	await wait_frames(1)
	check(is_equal_approx(cam.zoom.x, 2.0), "ピンチでズームする")
	
	# トラックパッドの2本指スクロール → 移動
	var pos_before: Vector2 = cam.position
	var pan := InputEventPanGesture.new()
	pan.position = screen_pos
	pan.delta = Vector2(3, 0)
	root.push_input(pan)
	await wait_frames(1)
	check(cam.position.x > pos_before.x, "2本指スクロールで横に移動する")
	
	# 中ボタンドラッグ → 地図をつかんで動かす（右へドラッグするとカメラは左へ）
	pos_before = cam.position
	await middle_drag(screen_pos, Vector2(100, 0))
	check(is_equal_approx(cam.position.x, pos_before.x - 100 / cam.zoom.x), "中ボタンドラッグで移動する")
	check(main.funds == 900000, "中ボタンドラッグで建設・撤去されない")
	
	# キー操作 → 押している間移動する
	pos_before = cam.position
	await hold_key(KEY_W, 0.2)
	check(cam.position.y < pos_before.y, "Wキーで上に移動する")
	await capture("camera_03_moved")

# ---------------------------------------------------
# 操作・撮影のヘルパー
# ---------------------------------------------------

# ボタンの中心をクリックする（GUIの入力処理を実際に通す）
func click_button(btn: Button) -> void:
	await click_at(btn.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)

# タイル座標のマスの中心をクリックする
func click_cell(cell: Vector2i, button: MouseButton) -> void:
	var tile_map: TileMapLayer = main.tile_map
	var screen_pos: Vector2 = tile_map.get_global_transform_with_canvas() * tile_map.map_to_local(cell)
	await click_at(screen_pos, button)

func click_at(pos: Vector2, button: MouseButton) -> void:
	# GUIはホバー状態を見るため、先にマウスを移動させておく
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion)
	await wait_frames(1)

	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev)
		await wait_frames(1)

func scroll_wheel(pos: Vector2, button: MouseButton, times: int) -> void:
	for i in times:
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			ev.pressed = pressed
			ev.position = pos
			ev.global_position = pos
			root.push_input(ev)
	await wait_frames(1)

func middle_drag(from: Vector2, amount: Vector2) -> void:
	for pressed in [true, false]:
		if not pressed:
			var motion := InputEventMouseMotion.new()
			motion.position = from + amount
			motion.global_position = from + amount
			motion.relative = amount
			motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
			root.push_input(motion)
			await wait_frames(1)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_MIDDLE
		ev.pressed = pressed
		ev.position = from + amount if not pressed else from
		ev.global_position = ev.position
		root.push_input(ev)
		await wait_frames(1)

func hold_key(keycode: Key, seconds: float) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		Input.parse_input_event(ev)
		if pressed:
			await create_timer(seconds).timeout
	await wait_frames(1)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path = out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT: ", path)

func check(ok: bool, desc: String) -> void:
	print(("  OK   " if ok else "  NG   ") + desc)
	if not ok:
		failures.append(desc)

# 条件がtrueになるまで待つ（timeout秒を過ぎたら諦める）
func wait_until(condition: Callable, timeout: float) -> void:
	var limit := Time.get_ticks_msec() + int(timeout * 1000)
	while not condition.call() and Time.get_ticks_msec() < limit:
		await process_frame

func wait_frames(n: int) -> void:
	for i in n:
		await process_frame
