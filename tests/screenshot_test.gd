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

	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await wait_frames(3)
	await run_scenario()

	if failures.is_empty():
		print("RESULT: ALL PASSED")
	else:
		print("RESULT: FAILED")
		for f in failures:
			print("  - ", f)
	quit(0 if failures.is_empty() else 1)

func run_scenario() -> void:
	var start_funds: int = main.funds
	await capture("01_start")

	# 1. 階段ボタンをクリック → 階段が[選択中]になる
	await click_button(main.mode_buttons["stairs"])
	check(main.current_mode == "stairs", "階段ボタンでモードがstairsになる")
	check(main.mode_buttons["stairs"].text.contains("[選択中]"), "階段ボタンに[選択中]が付く")
	check(not main.mode_buttons["office"].text.contains("[選択中]"), "オフィスボタンから[選択中]が外れる")
	await capture("02_stairs_selected")

	# 2. 空マスを左クリック → 階段を建設（-5万円）
	var stairs_cell := Vector2i(-2, 12)
	await click_cell(stairs_cell, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(stairs_cell) == "stairs", "左クリックで階段が建つ")
	check(main.funds == start_funds - 50000, "階段の建設費5万円が引かれる")

	# 3. オフィスに切り替えて左クリック → オフィスを建設（-10万円）
	await click_button(main.mode_buttons["office"])
	var office_cell := Vector2i(1, 12)
	await click_cell(office_cell, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(office_cell) == "office", "左クリックでオフィスが建つ")
	check(main.funds == start_funds - 150000, "オフィスの建設費10万円が引かれる")
	await capture("03_built")

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
	await click_cell(Vector2i(-5, 5), MOUSE_BUTTON_RIGHT)
	check(main.funds == start_funds - 75000, "空マスの右クリックでは資金が変わらない")
	await capture("04_demolished")

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

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path = out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("SCREENSHOT: ", path)

func check(ok: bool, desc: String) -> void:
	print(("  OK   " if ok else "  NG   ") + desc)
	if not ok:
		failures.append(desc)

func wait_frames(n: int) -> void:
	for i in n:
		await process_frame
