extends SceneTree

const ElevatorCar := preload("res://scripts/actors/elevator_car.gd")

# ---------------------------------------------------
# 画面確認用テスト
# main.tscnを起動し、実際のクリック操作を再現して各段階のスクリーンショットを保存する。
#
# 実行方法（ウィンドウ付きで起動する。--headless ではGUIのクリックやカーソル位置の判定が働かないので不可）:
#   godot --path . -s res://tests/screenshot_test.gd -- <保存先ディレクトリ>
# 保存先を省略すると user://screenshots に保存する。
# 一部のシナリオだけ流すときは、環境変数 TEST_ONLY にシナリオの関数名の一部を入れる（例: TEST_ONLY=express）。
# いくつかの組に分けて並べて実行するときは、TEST_SHARD に「番号/個数」を入れる（例: TEST_SHARD=1/3）。
# まとめて流すには tools/run_tests.sh を使う（既定は3組に分けて並べて実行し、2分半ほどで終わる）。
# ※ テスト中のウィンドウは常に最前面に出る（マウスは受け付けないので操作の邪魔にはならない）。
# ---------------------------------------------------

var main: Node2D
var out_dir: String
var failures: Array[String] = []

func _init() -> void:
	var args = OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://screenshots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	# 本物のマウスの操作がテストの入力に割り込まないよう、ウィンドウはマウスを受け付けない
	# （テストの入力は push_input で直接送るので影響しない）
	root.mouse_passthrough = true
	# ウィンドウが他のウィンドウの裏に隠れると、macOSに処理を間引かれて止まることがあるので、
	# 常に最前面に表示する（マウスは受け付けないので、前面にあってもほかの作業の邪魔にはならない）
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	# ウィンドウが他のウィンドウの裏に隠れると、macOSは画面の更新を止めることがある。
	# 垂直同期を待つとそこでフレームが止まってしまうので、テスト中は切って60fpsに制限する
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	# シナリオごとにゲームを起動し直して、前のシナリオの影響を受けないようにする
	# TEST_SHARD で受け持つシナリオを決める（並べて実行するため）
	var shard := OS.get_environment("TEST_SHARD")
	var shard_index := (int(shard.split("/")[0]) - 1) if shard.contains("/") else 0
	var shard_count := int(shard.split("/")[1]) if shard.contains("/") else 1
	var scenario_index := -1
	for scenario in [run_empty_start_scenario, run_build_scenario, run_stairs_scenario, run_camera_scenario, run_ui_scenario, run_elevator_scenario, run_ride_scenario, run_stress_scenario, run_collective_scenario, run_commute_scenario, run_economy_scenario, run_hotel_scenario, run_lunch_scenario, run_recycling_scenario, run_rating_scenario, run_housing_scenario, run_room_types_scenario, run_weekday_scenario, run_event_scenario, run_subway_scenario, run_capacity_scenario, run_multi_car_scenario, run_scroll_sky_scenario, run_night_light_scenario, run_sun_moon_scenario, run_street_lamp_scenario, run_tenant_rating_scenario, run_vacancy_scenario, run_hotel_rating_scenario, run_home_rating_scenario, run_atrium_scenario, run_sky_lobby_scenario, run_express_elevator_scenario, run_support_scenario, run_escalator_scenario, run_home_floor_scenario, run_service_hours_scenario, run_service_elevator_scenario, run_parking_scenario, run_shop_scenario, run_cinema_scenario, run_size_limit_scenario, run_noise_scenario, run_medical_scenario, run_pollution_scenario, run_angry_scenario, run_vip_scenario, run_bomb_scenario, run_fire_scenario, run_roach_scenario, run_treasure_scenario, run_calendar_scenario, run_weather_scenario, run_save_scenario, run_helipad_scenario, run_usability_scenario, run_audio_scenario, run_title_scenario, run_goal_scenario, run_tutorial_scenario, run_effects_scenario, run_garden_scenario, run_fastfood_scenario, run_office_types_scenario, run_frame_scenario, run_large_elevator_scenario, run_routes_scenario, run_menu_scenario, run_demolish_rules_scenario, run_incident_targets_scenario, run_bomb_search_scenario, run_blast_scenario, run_vip_elevator_scenario, run_rent_scenario, run_roach_rooms_scenario, run_review_fixes_scenario, run_entrances_scenario, run_sky_events_scenario, run_save_slots_scenario, run_observatory_scenario, run_overlay_scenario, run_request_scenario, run_season_scenario, run_elevator_stats_scenario, run_tower_name_scenario, run_mood_scenario, run_cache_scenario]:
		scenario_index += 1
		if scenario_index % shard_count != shard_index:
			continue # ほかの組が受け持つシナリオ
		if OS.get_environment("TEST_ONLY") != "" and not scenario.get_method().contains(OS.get_environment("TEST_ONLY")):
			continue
		# 更地から始めるシナリオ以外は、共通のビル（build_standard_block）を建ててから始める
		await start_main(scenario != run_empty_start_scenario and scenario != run_tutorial_scenario)
		if scenario != run_tutorial_scenario:
			main.tutorial_system.finished = true # 案内のバーがほかのシナリオの画面をずらさないようにする
		# シナリオは最後まで進むとtrueを返す。途中でスクリプトエラーが起きるとnullになる
		var started_at := Time.get_ticks_msec()
		var finished = await scenario.call()
		print("    かかった時間: %.1f秒" % ((Time.get_ticks_msec() - started_at) / 1000.0)) # どのシナリオが遅いかを見る
		if finished != true:
			failures.append("%s が途中で中断した（スクリプトエラーを確認）" % scenario.get_method())
	Engine.time_scale = 1.0

	if failures.is_empty():
		print("RESULT: ALL PASSED")
	else:
		print("RESULT: FAILED")
		for f in failures:
			print("  - ", f)
	quit(0 if failures.is_empty() else 1)

func start_main(standard_block := true) -> void:
	if main:
		main.queue_free()
		await wait_frames(1)
	main = load("res://scenes/main.tscn").instantiate()
	main.test_tools = true # 建設メニューに「住人（テスト）」を出す（遊ぶときには出さない）
	root.add_child(main)
	Engine.time_scale = 1.0
	await wait_frames(3) # _ready()が済むまで待つ
	use_test_save_dir() # _ready()で部品ができてから切り替える（ゲームが始まる前なので、まだ何も保存しない）
	main.start_game()    # タイトル画面を閉じて、ゲームを始める
	main.clock.set_process(false) # 社員の出勤で他のシナリオが乱れないよう、時計は止めておく
	if standard_block:
		build_standard_block()
		await wait_frames(1)

# セーブ・オートセーブの保存先を、テスト用のフォルダにする（遊んでいるセーブデータを上書きしないように）。
# 並べて実行する組ごとに分けて、ほかの組の保存とぶつからないようにする
func use_test_save_dir() -> void:
	main.save_system.save_dir = TEST_SAVE_DIR + OS.get_environment("TEST_SHARD").replace("/", "_")

const TEST_SAVE_DIR := "user://test_saves_"

# テストが書いたセーブの枠のファイルを消す。テスト用のフォルダの中でなければ、決して消さない
func remove_test_save(path: String) -> void:
	if not path.begins_with(TEST_SAVE_DIR):
		failures.append("テスト用のフォルダの外のセーブデータを消そうとした: " + path)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# 多くのシナリオで使う共通のビル（ゲームは更地から始まるので、テストで建てておく）
#   1階（y=18）: ロビー（x=-8〜7。入口は左端の (-8,18)）
#   2〜4階（y=17〜15）: 横4マスのオフィスを4棟ずつ（x=-8・-4・0・4 から。社員48人）
# 上の階へ行く階段・エレベーターはないので、上の階の社員は各シナリオで建てる階段やエレベーターを使う。
# 建て終わったら、資金は100万Crにしておく（各シナリオの金額の計算の基準）。
func build_standard_block() -> void:
	main.funds = 100000000
	main.select_mode("lobby")
	for x in range(-8, 8):
		main.build_at(Vector2i(x, 18))
	main.select_mode("office")
	for y in [17, 16, 15]: # 建物は下の階から積み上げる
		for x in [-8, -4, 0, 4]:
			main.build_at(Vector2i(x, y))
	main.funds = 1000000
	main.update_funds_display()
	main.show_message("")

# ---------------------------------------------------
# シナリオ0: 更地からのスタートと、1階はロビー専用のルール
# ---------------------------------------------------
func run_empty_start_scenario() -> bool:
	print("[シナリオ] 更地スタートと1階のルール")
	check(main.building_grid.is_empty(), "ゲームは更地（建物なし）から始まる")
	check(main.funds == 3000000, "最初の資金は300万Cr")
	check(main.ground_y == main.GROUND_FLOOR_Y, "1階の高さは決まっている（y=%d）" % main.GROUND_FLOOR_Y)
	check(main.get_entrance() == null, "ロビーがないうちは入口もない")
	check(main.current_mode == "lobby" and main.mode_select.text.begins_with("ロビー") and main.mode_select.text.ends_with("15,000Cr"), "最初は建設メニューでロビーが選ばれている")
	check(main.camera.position.is_equal_approx(Vector2(0, 272)), "カメラは地面の線が見える位置にある")
	await capture("empty_01_start")
	
	# 1階にはテナントを建てられない
	await choose_mode("office")
	await click_cell(Vector2i(0, 18), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(0, 18)), "1階にはオフィスを建てられない")
	check(main.last_message.contains("1階はロビー専用"), "建てられない理由（1階はロビー専用）がメッセージで出る")
	await hover_cell(Vector2i(0, 18))
	check(not main.can_click_cell(Vector2i(0, 18)), "1階にオフィスを建てようとすると赤く表示される")
	await choose_mode("hotel")
	await click_cell(Vector2i(0, 18), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(0, 18)), "1階にはホテルも建てられない")
	
	# ロビーは1階にだけ建てられ、1マスずつ横に伸ばせる
	await choose_mode("lobby")
	await click_cell(Vector2i(0, 17), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(0, 17)), "ロビーは2階には建てられない")
	check(main.last_message.contains("ロビーは1階にしか建てられません"), "建てられない理由（ロビーは1階だけ）がメッセージで出る")
	for x in range(-3, 4):
		await click_cell(Vector2i(x, 18), MOUSE_BUTTON_LEFT)
	check(main.find_cells_of_type("lobby").size() == 7, "ロビーは1マスずつ横に伸ばせる（7マス）")
	check(main.funds == 3000000 - 7 * 15000, "ロビーは1マス1.5万Cr")
	check(main.get_entrance() == Vector2i(-3, 18), "ロビーの左端が入口になる")
	
	# 1階に置けるのはロビーのほか、階段・エレベーター
	await choose_mode("elevator")
	await click_cell(Vector2i(4, 18), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(4, 18)) == "elevator", "1階にエレベーターを建てられる")
	await choose_mode("stairs")
	await click_cell(Vector2i(-4, 18), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(-4, 18)) == "stairs", "1階に階段を建てられる")
	
	# 2階から上には、今までどおりテナントを建てられる
	await choose_mode("office")
	await click_cell(Vector2i(-3, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(-3, 17)) == "office", "2階にはオフィスを建てられる")
	await capture("empty_02_lobby")
	return true

# ---------------------------------------------------
# シナリオ1: 建設・撤去とモード表示
# ---------------------------------------------------
func run_build_scenario() -> bool:
	print("[シナリオ] 建設・撤去")
	var start_funds: int = main.funds
	await capture("build_01_start")

	# 1. 階段ボタンをクリック → 階段が[選択中]になる
	await choose_mode("stairs")
	check(main.current_mode == "stairs", "建設メニューで階段を選ぶとモードがstairsになる")
	check(main.mode_select.text.begins_with("階段") and main.mode_select.text.ends_with("50,000Cr"), "建設メニューに「階段」が選ばれて表示される")
	check(main.mode_select.text.begins_with("階段") and main.mode_select.text.ends_with("50,000Cr"), "建設メニューに選んだものの名前と建設費が出る")
	await capture("build_02_stairs_selected")

	# 2. 空マスを左クリック → 階段を建設（-5万Cr）
	var stairs_cell := Vector2i(-4, 19) # 1階のロビーの真下（B1階）
	await click_cell(stairs_cell, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(stairs_cell) == "stairs", "左クリックで階段が建つ")
	check(main.funds == start_funds - 50000, "階段の建設費5万Crが引かれる")

	# 3. オフィスに切り替えて左クリック → オフィスを建設（-10万Cr）
	await choose_mode("office")
	var office_cell := Vector2i(2, 19) # 1階のロビーの真下（B1階。x=2〜5）
	await click_cell(office_cell, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(office_cell) == "office", "左クリックでオフィスが建つ")
	check(main.get_building_type(office_cell + Vector2i(3, 0)) == "office", "オフィスは横4マスにまたがって建つ")
	check(main.funds == start_funds - 450000, "オフィス（横4マス）の建設費40万Crが引かれる")
	await capture("build_03_built")

	# 4. 建てた階段を右クリック → 撤去（撤去費用5千Crがかかる。建設費は戻らない）
	await click_cell(stairs_cell, MOUSE_BUTTON_RIGHT)
	check(main.is_cell_empty(stairs_cell), "右クリックで階段が撤去される")
	check(main.tile_map.get_cell_source_id(stairs_cell) == -1, "撤去したマスのタイルが消える")
	check(main.funds == start_funds - 455000, "階段の撤去費用5千Cr（建設費の1割）がかかる")

	# 5. 事前配置のタイルを右クリック → 撤去（撤去費用4万Cr）
	var preset_cell := Vector2i(0, 15)
	await click_cell(preset_cell, MOUSE_BUTTON_RIGHT)
	check(main.is_cell_empty(preset_cell) and main.is_cell_empty(preset_cell + Vector2i(3, 0)), "事前配置のオフィスも横4マスまとめて撤去できる")
	check(main.funds == start_funds - 495000, "オフィスの撤去費用4万Cr（建設費の1割）がかかる")

	# 6. 空マスを右クリック → 何も起きない
	await click_cell(Vector2i(-10, 21), MOUSE_BUTTON_RIGHT)
	check(main.funds == start_funds - 495000, "空マスの右クリックでは資金が変わらない")
	await capture("build_04_demolished")
	return true

# ---------------------------------------------------
# シナリオ2: 階段による移動
# 事前配置のブロック（y=15〜18）の右隣に階段を置き、その上の階に横4マスのオフィス(x=5〜8)を建てる。
# 住人はブロック上段(0,15)から、階段(8,15)→(8,14)を通って上の階(5,14)へ向かう。
# 階段は1階から積み上げるので、(8,18)はロビー、(8,17)〜(8,15)は階段にする。
# ---------------------------------------------------
func run_stairs_scenario() -> bool:
	print("[シナリオ] 階段による移動")
	await choose_mode("stairs")
	# 足場: 階段は1階から積み上げるので、(8,18)はロビー、(8,17)〜(8,16)は階段にしておく
	build_support([Vector2i(8, 18)], "lobby")
	build_support([Vector2i(8, 17), Vector2i(8, 16)])
	await click_cell(Vector2i(8, 15), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	await click_cell(Vector2i(5, 14), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=5〜8。右端が階段の真上）
	await click_cell(Vector2i(-8, 19), MOUSE_BUTTON_LEFT) # ロビーの真下（B1階）の、どこにもつながらない孤立したオフィス
	
	# 移動ルール
	check(main.can_move(Vector2i(8, 15), Vector2i(8, 14)), "階段マスから上の階へ移動できる")
	check(main.can_move(Vector2i(8, 14), Vector2i(8, 15)), "上の階から階段マスへ降りられる")
	check(not main.can_move(Vector2i(7, 15), Vector2i(7, 14)), "オフィス同士は上下に移動できない")
	check(not main.can_move(Vector2i(8, 15), Vector2i(9, 15)), "空マスへは移動できない")
	
	# 住人を配置
	await choose_mode("resident")
	var start := Vector2i(0, 15)
	await click_cell(start, MOUSE_BUTTON_LEFT)
	check(main.residents.size() == 1, "住人モードでクリックすると住人が配置される")
	var resident = main.residents[0]
	check(resident.cell == start and resident.selected, "配置した住人が選択状態になる")
	
	# 経路のない行き先 → 移動しない
	await click_cell(Vector2i(-8, 19), MOUSE_BUTTON_LEFT)
	check(not resident.is_moving(), "経路のない行き先では移動しない")
	check(main.last_message.contains("経路がありません"), "経路がないことがメッセージで表示される")
	
	# 上の階へ移動
	var goal := Vector2i(5, 14)
	await click_cell(goal, MOUSE_BUTTON_LEFT)
	check(resident.is_moving(), "上の階を指定すると移動を始める")
	check(resident.path.has(Vector2i(8, 15)) and resident.path.has(Vector2i(8, 14)), "経路が階段を通っている")
	check(not resident.selected, "移動指示のあと住人の選択が外れる")
	
	set_speed(4.0) # 歩く様子を早送りする
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
	return true

# ---------------------------------------------------
# シナリオ3: カメラのズームと移動
# ---------------------------------------------------
func run_camera_scenario() -> bool:
	print("[シナリオ] カメラ操作")
	var cam = main.camera
	check(is_equal_approx(cam.zoom.x, cam.DEFAULT_ZOOM), "起動時は%.0f倍にズームしている" % cam.DEFAULT_ZOOM)
	check(cam.position.is_equal_approx(Vector2(0, 272)), "起動時はビルが画面中央に来る")
	await capture("camera_01_default")
	
	# ホイールでズームイン → カーソル下の位置は動かない
	var screen_pos := Vector2(900, 500)
	var world_before: Vector2 = cam.screen_to_world(screen_pos)
	await scroll_wheel(screen_pos, MOUSE_BUTTON_WHEEL_UP, 3)
	check(cam.zoom.x > cam.DEFAULT_ZOOM, "Ctrl+ホイール上でズームインする")
	check(cam.screen_to_world(screen_pos).is_equal_approx(world_before), "ズームしてもカーソル下の位置がずれない")
	check(main.funds == 1000000, "ホイール操作で建設されない")
	
	# ズーム後もクリックしたマスに正しく建設できる
	build_support(cells_row(18, 9, 12), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	build_support(cells_row(17, 9, 12)) # 足場: 2階を埋めて、その上の3階に建てられるようにする
	await click_cell(Vector2i(9, 16), MOUSE_BUTTON_LEFT) # 2段の上部バーに隠れない位置
	check(main.get_building_type(Vector2i(9, 16)) == "office", "ズーム後もクリックしたマスに建設できる")
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
	check(main.funds == 600000, "中ボタンドラッグで建設・撤去されない（オフィス40万Crを建てた後のまま）")
	
	# キー操作 → 押している間移動する
	pos_before = cam.position
	await hold_key(KEY_W, 0.2)
	check(cam.position.y < pos_before.y, "Wキーで上に移動する")
	pos_before = cam.position
	await hold_key(KEY_W, 0.2, true)
	check(cam.position == pos_before, "⌘を押しながらのキー（⌘Sのセーブなど）では、画面は動かない")
	await capture("camera_03_moved")
	return true

# ---------------------------------------------------
# シナリオ4: UIバーとマス目の表示
# ---------------------------------------------------
func run_ui_scenario() -> bool:
	print("[シナリオ] UIバーとマス目")
	var overlay = main.grid_overlay
	
	# 上部バーの上をクリックしても、その下のマスには建設されない
	# 上部バー1段目の、時刻の右隣（速度ボタンとの間の、ボタンのない位置）
	var clock_rect: Rect2 = main.clock_label.get_global_rect()
	var bar_pos := Vector2(clock_rect.end.x + 40, clock_rect.get_center().y)
	var cell_under_bar: Vector2i = main.tile_map.local_to_map(main.camera.screen_to_world(bar_pos))
	await click_at(bar_pos, MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(cell_under_bar) and main.funds == 1000000, "上部バーの上をクリックしても建設されない")
	check(main.current_mode == "office", "バーの余白をクリックしてもモードは変わらない")
	check(not overlay.hover_visible, "上部バーの上ではマスを強調表示しない")
	
	# カーソル下のマスの強調表示と情報
	var empty_cell := Vector2i(3, 14) # ブロックの真上の空きマス（支えがあるので建てられる）
	await hover_cell(empty_cell)
	check(overlay.hover_visible and overlay.hover_cell == empty_cell, "カーソル下のマスを強調表示する")
	check(main.can_click_cell(empty_cell), "空きマスは建設可能（緑）と判定される")
	check(main.hover_label.text == "5階: 空き", "空きマスの吹き出しには何階かと「空き」が出る（マスの座標は出さない）")
	await capture("ui_01_hover_empty")
	
	check(not main.hover_tooltip.visible, "空きマスでは吹き出しを出さない")
	var office_cell := Vector2i(0, 16)
	await hover_cell(office_cell)
	check(main.hover_tooltip.visible, "建物のマスにカーソルを合わせると吹き出しが出る")
	var tooltip_rect: Rect2 = main.hover_tooltip.get_global_rect()
	check(tooltip_rect.position.x > 0 and tooltip_rect.end.x <= main.get_viewport_rect().size.x, "吹き出しは画面の中に収まる")
	check(not main.can_click_cell(office_cell), "建物のあるマスは建設不可（赤）と判定される")
	check(main.hover_label.text.contains("オフィス"), "下部バーに建物の種類が出る")
	
	# ★を押すと、くわしい状況が開く（2段目は★と速さだけにして短くしている）
	check(not main.stats_panel.visible, "ビルの状況は最初は閉じている")
	check(not main.stats_button.text.contains("人口"), "★のボタンには★の数だけを出す")
	main.stats_button.pressed.emit()
	check(main.stats_panel.visible, "★を押すとビルの状況が開く")
	check(main.stats_label.text.contains("人口") and main.stats_label.text.contains("目標:"), "中に人口と目標が出る")
	await capture("ui_04_stats")
	main.stats_button.pressed.emit()
	check(not main.stats_panel.visible, "もう一度押すと閉じる")
	check(main.speed_button.get_global_rect().position.y == main.stats_button.get_global_rect().position.y, "速さのボタンは★と同じ行にある")

	# 操作説明の開閉（F1・H）。macOSの⌘H（隠す）とぶつからないよう、⌘は使わない
	check(not main.help_panel.visible, "操作説明は最初は閉じている")
	await press_key(KEY_F1)
	check(main.help_panel.visible, "F1で操作説明が開く")
	await capture("ui_02_help_open")
	# 操作説明を開いている間は、スクロールで動くのは操作説明だけ（一番下まで行っても、後ろの画面は動かない）
	var cam: Camera2D = main.camera
	var help_scroll: ScrollContainer = main.help_panel.get_child(0)
	var help_center: Vector2 = main.help_panel.get_global_rect().get_center()
	var cam_before: Vector2 = cam.position
	await scroll_wheel(help_center, MOUSE_BUTTON_WHEEL_DOWN, 60, false)
	check(help_scroll.scroll_vertical > 0, "操作説明の上でホイールを回すと、操作説明がスクロールする")
	check(cam.position == cam_before, "操作説明が一番下まで行っても、後ろの画面はスクロールしない")
	await pan_gesture(help_center, Vector2(0, 5), 30)
	check(cam.position == cam_before, "2本指スクロールでも、後ろの画面は動かない")
	var world_pos := Vector2(main.get_viewport().get_visible_rect().size.x * 0.2, main.get_viewport().get_visible_rect().size.y * 0.6)
	await scroll_wheel(world_pos, MOUSE_BUTTON_WHEEL_DOWN, 3, false)
	await pan_gesture(world_pos, Vector2(0, 5), 3)
	check(cam.position == cam_before, "操作説明を開いている間は、操作説明の外でスクロールしても後ろの画面は動かない")
	await press_key(KEY_F1)
	check(not main.help_panel.visible, "もう一度F1を押すと閉じる")
	await scroll_wheel(world_pos, MOUSE_BUTTON_WHEEL_DOWN, 1, false)
	check(cam.position != cam_before, "操作説明を閉じると、また画面をスクロールできる")
	cam.position = cam_before
	await press_key(KEY_H)
	check(main.help_panel.visible, "Hキーでも操作説明が開く")
	await press_key(KEY_ESCAPE)
	check(not main.help_panel.visible, "Escで開いているパネルが閉じる")
	await press_shortcut(KEY_H)
	check(not main.help_panel.visible, "⌘Hは受け付けない（macOSのウィンドウを隠す操作を邪魔しない）")
	
	# メッセージの記録（⌘L）
	main.show_message("テストのメッセージ1")
	main.show_message("テストのメッセージ2")
	check(main.last_message == "テストのメッセージ2" and main.message_label.text.contains("テストのメッセージ1"), "下部バーには新しいメッセージが下に出て、前のメッセージも残る")
	check(not main.log_panel.visible, "メッセージの記録は最初は閉じている")
	await press_shortcut(KEY_L)
	await wait_frames(2)
	check(main.log_panel.visible, "⌘Lでメッセージの記録が開く")
	check(main.log_label.text.contains("テストのメッセージ1") and main.log_label.text.contains("テストのメッセージ2"), "記録にはゲーム開始からのメッセージが時刻つきで並ぶ")
	await capture("ui_03_log_open")
	# 開いている間は、スクロールで動くのはメッセージの記録だけ（操作説明と同じ）
	for i in 60:
		main.show_message("スクロールするためのメッセージ %d" % i)
	main.ui.update_log_panel()
	await wait_frames(2)
	var log_center: Vector2 = main.log_panel.get_global_rect().get_center()
	cam_before = cam.position
	main.ui.log_scroll.scroll_vertical = 0
	await scroll_wheel(log_center, MOUSE_BUTTON_WHEEL_DOWN, 200, false)
	check(main.ui.log_scroll.scroll_vertical > 0, "メッセージの記録の上でホイールを回すと、記録がスクロールする")
	await pan_gesture(log_center, Vector2(0, 5), 30)
	await scroll_wheel(world_pos, MOUSE_BUTTON_WHEEL_DOWN, 3, false)
	await pan_gesture(world_pos, Vector2(0, 5), 3)
	check(cam.position == cam_before, "メッセージの記録を開いている間は、一番下まで行っても・記録の外でも、後ろの画面はスクロールしない")
	await press_shortcut(KEY_L)
	check(not main.log_panel.visible, "もう一度⌘Lを押すと閉じる")
	await scroll_wheel(world_pos, MOUSE_BUTTON_WHEEL_DOWN, 1, false)
	check(cam.position != cam_before, "メッセージの記録を閉じると、また画面をスクロールできる")
	cam.position = cam_before
	
	# 画面の拡大・縮小（⌘+ / ⌘- / ⌘0）
	var zoom_before: float = main.camera.zoom.x
	await press_shortcut(KEY_EQUAL)
	check(main.camera.zoom.x > zoom_before, "⌘+で画面が拡大する")
	await press_shortcut(KEY_MINUS)
	await press_shortcut(KEY_MINUS)
	check(main.camera.zoom.x < zoom_before, "⌘-で画面が縮小する")
	await press_shortcut(KEY_0)
	check(is_equal_approx(main.camera.zoom.x, main.camera.DEFAULT_ZOOM), "⌘0で拡大率がもとに戻る")
	
	# 速度のボタンは1つで、押すたびに 1x → 4x → 16x → 1x と切り替わる
	check(main.speed_button.text == "1x" and is_equal_approx(Engine.time_scale, 1.0), "最初は1x")
	await click_button(main.speed_button)
	check(main.speed_button.text == "4x" and is_equal_approx(Engine.time_scale, 4.0), "1回押すと4xになる")
	await click_button(main.speed_button)
	check(main.speed_button.text == "16x" and is_equal_approx(Engine.time_scale, 16.0), "もう1回押すと16xになる")
	await click_button(main.speed_button)
	check(main.speed_button.text == "1x" and is_equal_approx(Engine.time_scale, 1.0), "次に押すと1xに戻る")
	
	# ビルの状況（★の行）は上部バーにある
	check(main.stats_button.text.begins_with("★"), "上部バーの2段目には★だけを出す")
	check(main.stats_button.get_global_rect().position.y == main.mode_select.get_global_rect().position.y, "★・速さ・建設メニュー・経路は同じ行に並ぶ（上部バーは2行）")

	# 一時停止（スペースキー・上部バーのボタン・メニュー）
	check(not main.paused and main.ui.pause_button.visible and main.ui.pause_button.focus_mode == Control.FOCUS_NONE, "上部バーに一時停止のボタンがある（押してもスペースキーを奪わない）")
	main.clock.set_process(true)
	await press_key(KEY_SPACE)
	check(main.paused and Engine.time_scale == 0.0, "スペースキーで一時停止する（時間が止まる）")
	check(main.clock_label.text.ends_with("⏸ 停止中") and logged("一時停止しました"), "一時停止中だと上部バーとメッセージに出る")
	await capture("ui_05_paused")
	# 休日・くもり・大きな金額・前日の収支・一時停止中と、1段目が一番長くなっても画面に収まる
	var funds_saved: int = main.funds
	main.funds = 999999999
	main.economy_system.last_report = {"total": -9999999}
	main.update_funds_display()
	var saved_day: int = main.clock.day
	main.clock.day = 6 # 土曜日（休日）
	await wait_frames(2)
	check(main.clock_label.get_global_rect().end.x <= main.get_viewport_rect().size.x, "1段目が一番長くなっても、時刻の表示は画面に収まる")
	main.clock.day = saved_day
	main.funds = funds_saved
	main.economy_system.last_report = {}
	main.update_funds_display()
	var minute_before: float = main.clock.minute
	await wait_frames(10)
	check(main.clock.minute == minute_before, "一時停止中は時計が進まない")
	cam_before = cam.position
	await hold_key(KEY_W, 0.2)
	check(cam.position.y < cam_before.y, "一時停止中もキーで画面を動かせる")
	main.select_mode("lobby")
	main.build_at(Vector2i(8, 18))
	check(main.get_building_type(Vector2i(8, 18)) == "lobby", "一時停止中も建設できる")
	await press_key(KEY_SPACE)
	check(not main.paused and is_equal_approx(Engine.time_scale, 1.0) and logged("再開しました"), "もう一度スペースキーで、止める前の速さ（1x）で再開する")
	await click_button(main.ui.pause_button)
	check(main.paused, "上部バーのボタンでも一時停止できる")
	await click_button(main.speed_button)
	check(not main.paused and is_equal_approx(Engine.time_scale, 4.0) and main.speed_button.text == "4x", "一時停止中に速さのボタンを押すと、その速さで再開する")
	main.ui.do_menu_action("pause")
	check(main.paused and main.ui.is_menu_on("pause"), "メニューからも一時停止できる（チェックが付く）")
	main.ui.do_menu_action("pause")
	check(not main.paused and is_equal_approx(Engine.time_scale, 4.0), "メニューで再開すると、止める前の速さ（4x）に戻る")
	main.set_speed(1)
	main.clock.set_process(false)
	return true

# ---------------------------------------------------
# シナリオ5: エレベーター（1本のシャフトで1台のカゴが指定階に停まる）
# 事前配置のブロック（x=-8〜7, y=15〜18）の右隣 x=8 に、y=14〜18 のシャフトを建てる。
# ---------------------------------------------------
func run_elevator_scenario() -> bool:
	print("[シナリオ] エレベーター")
	var elevators = main.elevator_system
	var x := 8
	await choose_mode("elevator")
	for y in range(18, 13, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	check(main.funds == 1000000 - 5 * 80000, "シャフト5マスで40万Crかかる")
	check(elevators.cars.size() == 1, "縦につながったシャフトにカゴが1台できる")
	var car = elevators.cars[0]
	check(car.top_y == 14 and car.bottom_y == 18, "シャフトの範囲がy=14〜18になる")
	check(car.current_floor() == 18, "カゴは最下階からスタートする")
	
	# 階を指定して呼ぶ → その階に停まる
	var arrivals: Array[int] = []
	car.arrived.connect(func(y): arrivals.append(y))
	set_speed(4.0)
	await click_cell(Vector2i(x, 15), MOUSE_BUTTON_LEFT)
	check(main.funds == 1000000 - 5 * 80000, "シャフトのクリックでは建設されない（お金も減らない）")
	await wait_until(func(): return car.state == car.State.MOVING, 5.0)
	await capture("elevator_01_moving")
	await wait_until(func(): return arrivals.size() >= 1, 10.0)
	check(arrivals == [15], "呼んだ階(y=15)に停まる")
	check(car.position == main.tile_map.map_to_local(Vector2i(x, 15)), "カゴが階の位置にぴったり停まる")
	check(car.state == car.State.DOORS_OPEN, "停まったら扉が開く")
	check(main.last_message.contains("到着"), "到着メッセージが出る")
	await capture("elevator_02_arrived")
	
	# 集合制御: 下(18)へ向かう途中で17を呼ぶ → 先に17に寄ってから18へ
	Engine.time_scale = 1.0
	await wait_until(func(): return car.state == car.State.IDLE, 5.0)
	await click_cell(Vector2i(x, 18), MOUSE_BUTTON_LEFT)
	await wait_until(func(): return car.state == car.State.MOVING, 5.0)
	check(car.direction == car.Direction.DOWN, "下の階を呼ぶと進行方向が「下」になる")
	await capture("elevator_02b_direction")
	await click_cell(Vector2i(x, 17), MOUSE_BUTTON_LEFT)
	set_speed(4.0)
	await wait_until(func(): return arrivals.size() >= 3, 15.0)
	check(arrivals == [15, 17, 18], "下へ向かう途中で呼ばれた階(17)に寄ってから18に停まる")
	
	# 進行方向を保つ: 上(14)へ向かう途中、通り過ぎた後ろの階(17)を呼んでも引き返さない
	Engine.time_scale = 1.0
	await wait_until(func(): return car.state == car.State.IDLE, 5.0)
	await click_cell(Vector2i(x, 14), MOUSE_BUTTON_LEFT)
	await wait_until(func(): return car.current_floor() <= 16, 5.0)
	await click_cell(Vector2i(x, 17), MOUSE_BUTTON_LEFT)
	set_speed(4.0)
	await wait_until(func(): return arrivals.size() >= 5, 15.0)
	check(arrivals.slice(3) == [14, 17], "上へ進んでいる間は後ろの階に引き返さず、14の後に17へ向かう")
	await wait_until(func(): return car.state == car.State.IDLE, 5.0)
	check(car.direction == car.Direction.NONE, "呼び出しがなくなると進行方向が消える")
	Engine.time_scale = 1.0
	
	# 一番上のマスを撤去 → 同じカゴのまま範囲が縮む
	await click_cell(Vector2i(x, 14), MOUSE_BUTTON_RIGHT)
	check(elevators.cars.size() == 1 and elevators.cars[0] == car, "シャフトを縮めても同じカゴが残る")
	check(car.top_y == 15, "シャフトの範囲がy=15〜18になる")
	
	# 範囲外の階は呼べない
	check(not car.request_floor(14), "シャフトからなくなった階には呼べない")
	await capture("elevator_03_shrunk")
	
	# 途中のマスは上のマスを支えているので、撤去すると空きフロアが残ってシャフトが分かれる
	await click_cell(Vector2i(x, 17), MOUSE_BUTTON_RIGHT)
	check(main.get_building_type(Vector2i(x, 17)) == "frame", "シャフトの途中を撤去すると、空きフロアが残る")
	check(main.last_message.contains("空きフロアになります"), "空きフロアが残ることがメッセージで出る")
	check(main.get_building_type(Vector2i(x, 18)) == "elevator", "下のマスは残る（シャフトが上下に分かれる）")
	await choose_mode("elevator")
	await click_cell(Vector2i(x, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(x, 17)) == "elevator", "空きフロアの上にエレベーターを建て直すと、またつながる")
	return true

# ---------------------------------------------------
# シナリオ6: 住人がエレベーターに乗って移動する
# x=8 に y=13〜18 のシャフト、上の階 y=13 に x=5〜7 のオフィスを建てる。
# 住人はブロック上段(0,15)から、シャフト(8,15)でカゴを待って乗り、(8,13)で降りて(5,13)へ向かう。
# ---------------------------------------------------
func run_ride_scenario() -> bool:
	print("[シナリオ] 住人がエレベーターに乗る")
	main.funds = 10000000 # 建設費を気にせず並べられるようにする
	var x := 8
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	var car = main.elevator_system.cars[0]
	var arrivals: Array[int] = []
	car.arrived.connect(func(y): arrivals.append(y))
	
	await choose_mode("resident")
	await click_cell(Vector2i(0, 15), MOUSE_BUTTON_LEFT)
	var resident = main.residents.back()
	var goal := Vector2i(5, 13)
	await click_cell(goal, MOUSE_BUTTON_LEFT)
	check(resident.is_moving(), "エレベーターのある上の階を指定すると移動を始める")
	var path: Array[Vector2i] = [resident.cell]
	path.append_array(resident.path)
	check(count_rides(path) == 1, "経路にエレベーターの乗車が1回含まれる")
	
	set_speed(4.0)
	await wait_until(func(): return resident.state == resident.State.WAITING, 10.0)
	check(resident.cell == Vector2i(x, 15), "シャフトの前(8,15)でカゴを待つ")
	await capture("ride_01_waiting")
	await wait_until(func(): return resident.state == resident.State.RIDING, 10.0)
	check(car.current_floor() == 15, "カゴが住人の階に来てから乗り込む")
	await wait_until(func(): return car.state == car.State.MOVING, 10.0)
	await capture("ride_02_riding")
	await wait_until(func(): return not resident.is_moving(), 15.0)
	Engine.time_scale = 1.0
	check(arrivals.has(15) and arrivals.has(13), "カゴが乗る階(15)と降りる階(13)に停まる")
	check(resident.cell == goal, "住人がエレベーターを使って目的地に着く")
	await capture("ride_03_arrived")
	
	# 階段とエレベーターの使い分け
	# x=9 に y=13〜18 の階段を積む（x=8のシャフトと並ぶ。一番上の(9,13)が踊り場になる）
	await choose_mode("stairs")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(9, y), MOUSE_BUTTON_LEFT)
	check(count_rides(main.find_path(Vector2i(8, 15), Vector2i(8, 14))) == 0, "1階だけの移動なら階段を使う")
	check(count_rides(main.find_path(Vector2i(8, 18), Vector2i(8, 13))) == 1, "5階離れた移動ならエレベーターを使う")
	return true

# ---------------------------------------------------
# シナリオ7: 待ち時間によるストレス蓄積と色の変化
# シナリオ6と同じ建物で、カゴを止めて住人を長く待たせる。
# ---------------------------------------------------
func run_stress_scenario() -> bool:
	print("[シナリオ] ストレス")
	main.funds = 10000000
	var x := 8
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	var car = main.elevator_system.cars[0]
	
	await choose_mode("resident")
	await click_cell(Vector2i(0, 15), MOUSE_BUTTON_LEFT)
	var resident = main.residents.back()
	var goal := Vector2i(5, 13)
	await click_cell(goal, MOUSE_BUTTON_LEFT)
	check(resident.stress == 0.0 and resident.get_face_color() == resident.BODY_COLORS["s"], "最初はストレス0で、顔はふつうの肌色")
	check(resident.get_body_color() == Color.WHITE, "服の色は種類の色（社員は白）のまま")
	
	car.set_process(false) # カゴを止めて、住人を待たせ続ける
	set_speed(4.0)
	await wait_until(func(): return resident.state == resident.State.WAITING, 10.0)
	var walking_stress: float = resident.stress
	check(walking_stress == 0.0, "歩いている間はストレスがたまらない")
	
	await wait_until(func(): return resident.stress >= resident.STRESS_PINK, 10.0)
	check(resident.get_face_color() == resident.PINK_COLOR and resident.get_body_color() == Color.WHITE, "ストレス40以上で顔がピンクになる（服は白のまま）")
	focus_camera(resident.cell)
	await wait_frames(1)
	await hover_cell(resident.cell)
	check(main.hover_label.text.contains("住人のストレス"), "カーソルを合わせると下部バーにストレスが出る")
	await capture("stress_01_pink")
	
	await wait_until(func(): return resident.stress >= resident.STRESS_RED, 10.0)
	# 激怒（95以上）になると赤と明るい色で点滅するので、どちらでもよいことにする
	check(resident.get_face_color() in [resident.RED_COLOR, resident.ANGRY_COLOR], "ストレス70以上で顔が赤くなる")
	await wait_until(func(): return resident.stress >= resident.MAX_STRESS, 10.0)
	check(resident.stress == resident.MAX_STRESS, "ストレスは100で止まる")
	await capture("stress_02_red")
	
	# カゴを動かす → 乗って目的地へ。着いたら回復していく
	car.set_process(true)
	await wait_until(func(): return not resident.is_moving(), 15.0)
	check(resident.cell == goal, "カゴが動き出すと住人は目的地に着く")
	var arrived_stress: float = resident.stress
	check(arrived_stress == resident.MAX_STRESS, "乗車中はストレスが変わらない")
	await wait_until(func(): return resident.stress < resident.STRESS_RED, 10.0)
	check(resident.stress < arrived_stress and resident.get_face_color() == resident.PINK_COLOR, "目的地に着くとストレスが回復して、顔が赤からピンクに戻る")
	Engine.time_scale = 1.0
	return true

# ---------------------------------------------------
# シナリオ8: 逆方向のカゴは見送る（集合制御での乗り降り）
# カゴが下(18)へ向かっている間に、(8,15)で上へ行きたい住人が待つ。
# 住人は下りのカゴには乗らず、18で折り返して上ってきたカゴに乗る。
# ---------------------------------------------------
func run_collective_scenario() -> bool:
	print("[シナリオ] 集合制御での乗り降り")
	main.funds = 10000000
	var x := 8
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	var car = main.elevator_system.cars[0]
	
	# カゴを最上階(13)に上げてから、最下階(18)へ向かわせる
	await choose_mode("elevator")
	await click_cell(Vector2i(x, 13), MOUSE_BUTTON_LEFT)
	await wait_until(func(): return car.floor_y == 13 and car.state == car.State.IDLE, 10.0)
	var arrivals: Array[int] = []
	car.arrived.connect(func(y): arrivals.append(y))
	await click_cell(Vector2i(x, 18), MOUSE_BUTTON_LEFT)
	
	# 上へ行きたい住人を、シャフトの隣(7,15)に置いて(5,13)へ向かわせる
	await choose_mode("resident")
	await click_cell(Vector2i(7, 15), MOUSE_BUTTON_LEFT)
	var resident = main.residents.back()
	var goal := Vector2i(5, 13)
	await click_cell(goal, MOUSE_BUTTON_LEFT)
	
	# 住人が目的地に着くまで、下りのカゴに乗っていないか毎フレーム見張る
	var boarded_going_down := false
	var captured := false
	var limit := Time.get_ticks_msec() + 20000
	while resident.is_moving() and Time.get_ticks_msec() < limit:
		if resident.state == resident.State.RIDING and car.direction == car.Direction.DOWN:
			boarded_going_down = true
		if not captured and resident.state == resident.State.WAITING and car.direction == car.Direction.DOWN and car.current_floor() > 15:
			await capture("collective_01_let_pass")
			captured = true
		await process_frame
	check(not boarded_going_down, "上へ行きたい住人は下りのカゴに乗らない")
	check(arrivals == [18, 15, 13], "カゴは18で折り返し、上りで15に寄って住人を乗せ、13で降ろす")
	check(resident.cell == goal, "住人が目的地に着く")
	return true

# ---------------------------------------------------
# シナリオ9: オフィスの出退社ラッシュ
# 事前配置のブロック（y=15〜18）＋ x=8 のシャフト（y=13〜18）＋ 上の階 y=13 のオフィス3つ
# ＋ ロビーの真下（B1階）の、どこにもつながらない孤立したオフィス1つ。入口はブロック最下段の左端(-8,18)。
# ---------------------------------------------------
func run_commute_scenario() -> bool:
	print("[シナリオ] 出退社ラッシュ")
	main.funds = 10000000
	var commute = main.commute_system
	var x := 8
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	await click_cell(Vector2i(-8, 19), MOUSE_BUTTON_LEFT) # ロビーの真下（B1階）の、どこにもつながらない孤立したオフィス
	check(main.get_entrance() == Vector2i(-8, 18), "地下にオフィスを建てても、入口は1階の左端のまま")
	check(commute.workers.size() == 56, "オフィス56マス（14棟）に社員56人が登録される")
	
	# 7:59 → 時計を進めて朝のラッシュを見る
	var car = main.elevator_system.cars[0]
	var elevator_stops := [0]
	car.arrived.connect(func(_y): elevator_stops[0] += 1)
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	check(main.clock_label.text != "", "上部バーに時刻が出る")
	set_speed(8.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 8 * 60 + 30, 20.0)
	check(main.clock_label.text.begins_with("4月1日（月） 08:"), "時刻の表示が進む（4月1日（月） 08:xx）")
	check(commute.count_in_building() > 0, "8時台に社員が入口から出勤してくる")
	await capture("commute_01_rush")
	var max_stress := 0.0
	while main.clock.minute_of_day() < 10 * 60 + 45: # 定員8人のカゴ1台では運びきるのに時間がかかるので余裕をもつ
		for r in main.residents:
			if is_instance_valid(r):
				max_stress = maxf(max_stress, r.stress)
		await process_frame
	print("    at_office=", commute.count_at_office(), " in_building=", commute.count_in_building(), " unreachable=", commute.count_unreachable())
	check(commute.count_at_office() == 52, "10時45分には通勤できる52人全員が自分のオフィスに着いている")
	check(commute.count_unreachable() == 4, "孤立したオフィスの4人は通勤できない")
	check(main.stats_label.text.contains("通勤できない社員 4人"), "ビルの状況に通勤できない人数が出る")
	check(elevator_stops[0] > 0, "上の階の社員はエレベーターで出勤する")
	check(max_stress > 0.0, "エレベーター待ちで社員にストレスがたまる")
	await capture("commute_02_at_office")
	
	# 夕方 → 全員帰る
	set_speed(16.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 19 * 60 + 45, 60.0) # 定員8人のカゴ1台では運びきるのに時間がかかるので余裕をもつ
	Engine.time_scale = 1.0
	await wait_frames(2)
	print("    evening in_building=", commute.count_in_building())
	check(commute.count_in_building() == 0, "19時45分には全員が入口から帰っている")
	await capture("commute_03_evening")
	main.clock.set_process(false)
	return true

# ---------------------------------------------------
# シナリオ10: 毎日の決算（賃料収入と維持費）
# シナリオ9と同じ建物で1日目を過ごし、0:00の決算を確かめる。
# 出勤できるオフィス52マス（2〜4階の48マス × 1万Cr ＋ 6階の4マス × 1.1万Cr）− エレベーター6マス × 2千Cr
#   − ゴミ52の外部委託（ゴミ処理場なし）× 1千Cr = +460,000Cr
# ---------------------------------------------------
func run_economy_scenario() -> bool:
	print("[シナリオ] 決算")
	check(main.format_money(1000000) == "1,000,000", "金額は3桁ごとにカンマで区切る")
	check(main.format_money(-1234) == "-1,234" and main.format_money(999) == "999", "マイナスや3桁以下も正しく表示する")
	check(main.format_money(658000, true) == "+658,000", "収支にはプラス記号を付ける")
	
	main.funds = 10000000
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	await click_cell(Vector2i(-8, 19), MOUSE_BUTTON_LEFT) # ロビーの真下（B1階）の孤立したオフィス（賃料は入らない）
	check(main.funds_label.text == "資金: 8,720,000Cr", "資金の表示もカンマ区切りになる")
	
	# 1日目の朝に全員出勤させてから、夜中まで時計を進める
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60, 30.0)
	main.clock.set_time(1, 23, 58)
	var funds_before: int = main.funds
	await wait_until(func(): return not main.economy_system.last_report.is_empty(), 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	var report = main.economy_system.last_report
	check(report.get("day") == 1, "日付が変わると1日目の決算をする")
	check(report.get("rent") == 48 * 10000 + 4 * 11000, "出勤したオフィス52マス分の賃料52.4万Crが入る（6階は高い階なので1.1倍。孤立したオフィスは0）")
	# 高い階ほど賃料が高い（5階ごとに1割。最大2倍）。地下は安い
	var economy = main.economy_system
	check(economy.floor_rent_rate(17) == 1.0 and economy.floor_rent_rate(14) == 1.0, "2〜5階の賃料は1倍")
	check(is_equal_approx(economy.floor_rent_rate(13), 1.1) and is_equal_approx(economy.floor_rent_rate(8), 1.2), "6〜10階は1.1倍、11〜15階は1.2倍")
	check(economy.floor_rent_rate(-200) == economy.FLOOR_RENT_MAX and economy.floor_rent_rate(19) == economy.BASEMENT_RENT_RATE, "とても高い階でも2倍まで。地下は0.8倍")
	check(economy.office_rent(Vector2i(4, 13)) == 11000 and economy.office_rent(Vector2i(-8, 19)) == 8000, "6階のオフィスは1マス1.1万Cr、地下のオフィスは0.8万Cr")
	await hover_cell(Vector2i(5, 13))
	check(main.hover_label.text.contains("家賃 普通・11,000Cr/マス・高い階で1.1倍"), "カーソルを合わせると、高い階の倍率も出る")
	check(report.get("maintenance") == 12000, "エレベーター6マス分の維持費1.2万Crがかかる")
	check(report.get("garbage") == 52 and report.get("garbage_cost") == 52000, "ゴミ処理場がないとゴミ52を外部委託して5.2万Crかかる")
	check(main.funds == funds_before + 460000, "資金が差し引き46万Cr増える")
	check(main.ui.funds_change_label.text == "（前日 +460,000Cr）" and main.ui.funds_change_label.get_theme_color("font_color") == main.ui.GAIN_COLOR, "資金の横に前日の収支が出る（黒字は緑）")
	check(logged("4月1日（1日目）の決算"), "決算の内容が日付つきでメッセージに出る")
	await capture("economy_01_settled")
	
	# 収支のグラフ（⌘G）に、決算の記録がたまっていく
	await run_day(2)
	await run_day(3)
	await press_shortcut(KEY_G)
	await wait_frames(2)
	check(main.chart_panel.visible and main.economy_system.history.size() == 3, "3日ぶんの決算がグラフに出る")
	await capture("economy_02_chart")
	await press_shortcut(KEY_G)
	return true

# ---------------------------------------------------
# シナリオ11: ホテルとハウスキーパー
# 2階(y=17)のブロックの右隣に、シングル3室（横2マスずつ、x=8・10・12から）とハウスキーパー室（横2マス、x=14〜15）を並べる。
# 入口(-8,18)からロビーを歩き、(8,18)の階段で2階へ上がる。右側が画面に入るようにカメラを動かしておく。
# ---------------------------------------------------
func run_hotel_scenario() -> bool:
	print("[シナリオ] ホテルとハウスキーパー")
	main.funds = 10000000
	# 1階はロビー専用なので、ロビーの右隣(8,18)に階段を置いて2階(y=17)へ上がれるようにする
	main.select_mode("stairs")
	main.build_at(Vector2i(8, 18))
	main.funds = 10000000
	var hotel = main.hotel_system
	build_support(cells_row(18, 9, 15), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	var room_cells: Array[Vector2i] = [Vector2i(8, 17), Vector2i(10, 17), Vector2i(12, 17)]
	focus_camera(Vector2i(10, 17))
	await choose_mode("hotel")
	for cell in room_cells:
		await click_cell(cell, MOUSE_BUTTON_LEFT)
	await choose_mode("housekeeping")
	await click_cell(Vector2i(14, 17), MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 3 * 150000 - 200000, "客室15万Cr×3とハウスキーパー室20万Crがかかる")
	check(main.get_unit_cells(Vector2i(9, 17)) == [Vector2i(8, 17), Vector2i(9, 17)], "シングルは横2マスの部屋")
	check(hotel.rooms.size() == 3 and hotel.count_rooms(hotel.RoomState.CLEAN) == 3, "客室が3室でき、最初はきれいな空室")
	check(hotel.housekeepers.size() == 2, "ハウスキーパー室（横2マス）に清掃員が2人いる")
	var keeper = hotel.housekeepers.values()[0].resident
	check(keeper.base_color == hotel.HOUSEKEEPER_COLOR, "清掃員は水色")
	
	# 夕方 → 客が来て泊まる
	main.clock.set_time(1, 16, 59)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 21 * 60 + 30, 30.0)
	check(hotel.count_rooms(hotel.RoomState.OCCUPIED) == 3, "21時半には3室とも宿泊中になる")
	var guests_in_room := 0
	for cell in room_cells:
		var guest = hotel.rooms[cell].guests[0]
		if is_instance_valid(guest) and guest.cell == cell and guest.base_color == hotel.GUEST_COLOR:
			guests_in_room += 1
	check(guests_in_room == 3, "薄紫の宿泊客がそれぞれの部屋に着いている")
	await hover_cell(room_cells[0] + Vector2i(1, 0))
	check(main.hover_label.text.contains("シングル（宿泊中・"), "部屋のどのマスにカーソルを合わせても部屋の状態と騒音が出る")
	check(main.stats_label.text.contains("客室: 宿泊 3"), "ビルの状況に客室の様子が出る")
	var viewport_width: float = main.get_viewport_rect().size.x
	var ui_right := 0.0
	for node in main.find_children("*", "Button", true, false):
		ui_right = maxf(ui_right, node.get_global_rect().end.x)
	check(ui_right <= viewport_width, "文字が増えてもUIのボタンが画面からはみ出さない")
	check(main.stats_button.get_global_rect().end.x <= viewport_width, "上部バーの★のボタンも画面からはみ出さない")
	await capture("hotel_01_night")
	
	# 翌朝 → チェックアウトして帰り、部屋は清掃待ち → 清掃員が掃除する
	# チェックアウトの前から見張る（早送り中は、最後の客が帰るまでに先に帰った部屋の掃除が
	# 終わっていることがあるので、帰るのを待ってから見張ると「清掃待ち」を見逃す）
	main.clock.set_time(2, 6, 59)
	var saw_dirty := [false]
	var saw_cleaning := [false]
	await wait_until(func():
		if hotel.count_rooms(hotel.RoomState.DIRTY) > 0:
			saw_dirty[0] = true
		for cell in room_cells:
			if hotel.get_room_state_text(cell) == "清掃中":
				saw_cleaning[0] = true
		return hotel.count_rooms(hotel.RoomState.OCCUPIED) == 0 and hotel.count_rooms(hotel.RoomState.CLEAN) == 3, 60.0)
	check(hotel.revenue_by_day.get(2, 0) == 60000, "チェックアウトで宿泊料2万Cr×3室が入る")
	check(saw_dirty[0], "チェックアウトした部屋は清掃待ちになる")
	check(saw_cleaning[0], "清掃員が部屋に来て清掃する")
	check(hotel.count_rooms(hotel.RoomState.CLEAN) == 3, "清掃が済むと3室ともきれいな空室に戻る")
	await wait_until(func(): return keeper.cell == Vector2i(14, 17) and not keeper.is_moving(), 20.0)
	check(keeper.cell == Vector2i(14, 17), "仕事が終わると清掃員はハウスキーパー室に戻る")
	
	# 2日目の決算に宿泊料と維持費が入る
	main.clock.set_time(2, 23, 59)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 2, 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(main.economy_system.last_report.get("hotel") == 60000, "2日目の決算に宿泊料6万Crが入る")
	check(main.economy_system.last_report.get("maintenance") == 10000, "ハウスキーパー室の維持費1万Crがかかる")
	check(main.last_message.contains("宿泊料 +60,000Cr"), "決算のメッセージに宿泊料が出る")
	return true

# ---------------------------------------------------
# シナリオ12: 飲食店（社員の昼食）
# シナリオ9と同じ建物（孤立したオフィスなし）＋ 1階のシャフトの右隣(9,18)に飲食店。
# 上の階の社員はエレベーターで1階に降りて食事をし、また戻る。
# ---------------------------------------------------
func run_lunch_scenario() -> bool:
	print("[シナリオ] 飲食店")
	main.funds = 10000000
	var commute = main.commute_system
	var commerce = main.commerce_system
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	var restaurant := Vector2i(9, 17) # 1階はロビー専用なので、2階のシャフトの右隣
	build_support(cells_row(18, 9, 11), "lobby") # 足場: 2階に建てるため、1階にロビーを足す

	await choose_mode("restaurant")
	await click_cell(restaurant, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(restaurant) == "restaurant", "飲食店を建てられる（20万Cr）")
	check(main.funds == 10000000 - 6 * 80000 - 400000 - 200000, "飲食店の建設費20万Crがかかる")
	
	# 朝のうちに全員出勤させる
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60 + 45, 30.0) # 定員8人のカゴ1台では運びきるのに時間がかかるので余裕をもつ
	check(commute.count_at_office() == 52, "10時45分には52人全員がオフィスにいる")
	
	# 昼休み
	var car = main.elevator_system.cars[0]
	var lunch_stops := [0]
	car.arrived.connect(func(_y): lunch_stops[0] += 1)
	main.clock.set_time(1, 11, 59)
	set_speed(16.0)
	var max_eating := [0]
	var captured := [false]
	await wait_until(func():
		var eating: int = commerce.count_eating_at(restaurant)
		max_eating[0] = maxi(max_eating[0], eating)
		return eating >= 10, 30.0)
	await hover_cell(restaurant)
	check(main.hover_label.text.contains("飲食店（客 "), "カーソルを合わせると店にいる客の数が出る")
	await capture("lunch_01_crowd")
	await wait_until(func():
		max_eating[0] = maxi(max_eating[0], commerce.count_eating_at(restaurant))
		return main.clock.minute_of_day() >= 15 * 60 + 45, 30.0) # 店の奥の席まで歩く人・エレベーターの定員待ちがあるので余裕をもつ
	check(max_eating[0] > 0, "昼に社員が飲食店で食事をする")
	check(lunch_stops[0] > 0, "上の階の社員はエレベーターで飲食店へ行き来する")
	check(commerce.revenue_by_day.get(1, 0) == 54000, "社員52人＋外からの客2人が食事をして売上5.4万Crになる")
	check(commute.count_at_office() == 52, "15時45分には全員がオフィスに戻っている")
	
	# 1日目の決算に飲食店の売上が入る
	main.clock.set_time(1, 23, 59)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 1, 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(main.economy_system.last_report.get("food") == 54000, "決算に飲食店の売上5.4万Crが入る")
	check(logged("飲食 +54,000Cr"), "決算のメッセージに飲食の売上が出る") # 同じフレームにエレベーターの到着のメッセージが続くことがあるので、記録から探す
	return true

# ---------------------------------------------------
# シナリオ13: ゴミ処理場
# シナリオ10と同じ建物＋1階のシャフトの右隣にゴミ処理場2施設（横3マスずつ、x=9・12から。処理能力40）。
# ゴミ52のうち40を処理し、残り12を外部委託（1.2万Cr）。維持費はエレベーター1.2万＋ゴミ処理場1万。
# ---------------------------------------------------
func run_recycling_scenario() -> bool:
	print("[シナリオ] ゴミ処理場")
	main.funds = 10000000
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	focus_camera(Vector2i(8, 16))
	build_support(cells_row(18, 9, 14), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	await choose_mode("recycling")
	for rx in [9, 12]:
		await click_cell(Vector2i(rx, 17), MOUSE_BUTTON_LEFT) # 1階はロビー専用なので2階に
	check(main.funds == 10000000 - 6 * 80000 - 400000 - 2 * 150000, "ゴミ処理場の建設費15万Cr×2がかかる")
	check(main.economy_system.recycling_capacity() == 40, "ゴミ処理場2施設で処理能力40/日になる")
	await hover_cell(Vector2i(9, 17))
	check(main.hover_label.text.contains("処理能力 40/日"), "カーソルを合わせると処理能力が出る")
	await capture("recycling_01_built")
	
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60, 30.0)
	main.clock.set_time(1, 23, 58)
	await wait_until(func(): return not main.economy_system.last_report.is_empty(), 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	var report = main.economy_system.last_report
	check(report.get("garbage") == 52, "出勤したオフィス52マスからゴミ52が出る")
	check(report.get("garbage_cost") == 12000, "処理しきれない12を外部委託して1.2万Crかかる")
	check(report.get("maintenance") == 22000, "維持費はエレベーター1.2万Cr＋ゴミ処理場1万Cr")
	check(report.get("total") == 524000 - 22000 - 12000, "合計は+49万Cr（ゴミ処理場なしより3万Cr得）")
	check(main.last_message.contains("ゴミ処理 -12,000Cr（ゴミ52・処理能力40）"), "決算のメッセージにゴミの量と処理能力が出る")
	return true

# ---------------------------------------------------
# シナリオ14: ビルの評価（★）
# シナリオ10と同じ建物（人口52）に警備室を置くと、1日目の決算で★2に上がり、
# 2日目の決算から賃料に25%の評価ボーナスが付く。
# ---------------------------------------------------
func run_rating_scenario() -> bool:
	print("[シナリオ] ビルの評価")
	main.funds = 10000000
	var rating = main.rating_system
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	check(rating.stars == 1 and rating.population() == 52, "最初は★1、人口52（社員52人）")
	check(rating.missing_for_next() == ["警備室"], "★2に足りないのは警備室だけ")
	await wait_frames(2)
	check(main.stats_label.text.split("\n")[1].begins_with("★1 人口52（★2まで: 警備室）"), "ビルの状況に評価と次の★に足りないものが出る（1行目はビルの名前）")
	
	build_support(cells_row(18, 9, 13), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	await choose_mode("security")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT) # 1階はロビー専用なので2階に
	check(rating.missing_for_next().is_empty(), "警備室を置くと★2の条件を満たす")
	check(rating.stars == 1, "★が上がるのは決算のとき")
	
	# 1日目: 決算で★2に上がる（ボーナスはまだ付かない）
	await run_day(1)
	var report = main.economy_system.last_report
	check(rating.stars == 2, "1日目の決算で★2に上がる")
	check(logged("ビルの評価が★2に上がりました！"), "昇格がメッセージで知らされる")
	check(report.get("bonus") == 0, "昇格した日の決算にはまだボーナスが付かない")
	check(report.get("maintenance") == 12000 + 5000, "警備室の維持費5千Crがかかる")
	await capture("rating_01_star2")
	
	# 2日目: 賃料52.4万Crの25% = 13.1万Crのボーナス
	await run_day(2)
	report = main.economy_system.last_report
	check(report.get("bonus") == 131000, "★2では賃料に25%（13.1万Cr）の評価ボーナスが付く")
	check(main.last_message.contains("評価ボーナス +131,000Cr"), "決算のメッセージに評価ボーナスが出る")
	
	# ★3の条件
	check(rating.missing_for_next() == ["人口120", "メディカルセンター", "ゴミ処理場"], "★3には人口120・メディカルセンター・ゴミ処理場が必要")
	await choose_mode("medical")
	await click_cell(Vector2i(11, 17), MOUSE_BUTTON_LEFT) # 警備室（x=9〜10）の右隣
	check(main.get_building_type(Vector2i(11, 17)) == "medical", "メディカルセンターを建てられる")
	check(rating.missing_for_next() == ["人口120", "ゴミ処理場"], "メディカルセンターを置くと★3の条件から外れる")
	return true

# ---------------------------------------------------
# シナリオ15: 住宅
# 2階(y=17)のブロックの右隣に住宅2戸（横3マスずつ、x=8・11から）。(8,18)の階段で2階へ上がる。
# ---------------------------------------------------
func run_housing_scenario() -> bool:
	print("[シナリオ] 住宅")
	main.funds = 10000000
	# 1階はロビー専用なので、ロビーの右隣(8,18)に階段を置いて2階(y=17)へ上がれるようにする
	main.select_mode("stairs")
	main.build_at(Vector2i(8, 18))
	main.funds = 10000000
	var housing = main.housing_system
	build_support(cells_row(18, 9, 13), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	var homes: Array[Vector2i] = [Vector2i(8, 17), Vector2i(11, 17)] # 横3マスずつ（x=8〜10、11〜13）
	focus_camera(Vector2i(8, 17))
	await choose_mode("housing")
	for cell in homes:
		await click_cell(cell, MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 2 * 400000, "住宅（横3マス）の建設費40万Cr×2がかかる")
	check(housing.homes.size() == 2 and housing.count_moved_in() == 0, "建てた直後はまだ入居者がいない")
	check(housing.homes[homes[0]].members.size() == 3, "住宅1戸は3人家族（1人1マス）")
	await hover_cell(homes[0] + Vector2i(2, 0))
	check(main.hover_label.text.contains("住宅（入居者募集中・"), "住宅のどのマスにカーソルを合わせても「入居者募集中」と出る")
	
	# 1日目の夕方: 家族が来て入居し、販売収入が入る
	main.clock.set_time(1, 16, 59)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 20 * 60 + 30, 30.0)
	check(housing.count_moved_in() == 2 and housing.count_at_home() == 6, "夕方に2戸とも入居し、6人が家にいる")
	var rooms := {}
	for m in housing.homes[homes[0]].members:
		if housing.is_at_home(m):
			rooms[m.resident.cell] = true
	check(rooms.size() == 3, "家族3人はそれぞれ別のマス（部屋）にいる")
	check(housing.revenue_by_day.get(1, 0) == 700000, "入居で販売収入35万Cr×2が入る")
	check(housing.homes[homes[0]].members[0].resident.base_color == housing.RESIDENT_COLOR, "入居者は緑の服")
	var others: int = main.commute_system.workers.size() - main.commute_system.count_unreachable() + main.hotel_system.total_capacity()
	check(main.rating_system.population() == others + 6, "入居者6人の分だけ人口が増える")
	await hover_cell(homes[0])
	check(main.hover_label.text.contains("住宅（在宅 3/3人・"), "入居後は在宅の人数が出る")
	await capture("housing_01_moved_in")
	
	# 2日目の朝: 1日目の決算に販売収入が入り、入居者は出かける
	main.clock.set_time(2, 6, 59)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 1, 10.0)
	check(main.economy_system.last_report.get("housing") == 700000, "1日目の決算に住宅販売70万Crが入る")
	check(logged("住宅販売 +700,000Cr"), "決算のメッセージに住宅販売が出る")
	check(main.economy_system.last_report.get("housing_fee") == 2 * housing.MANAGEMENT_FEE and logged("管理費 +6,000Cr"), "入居している住宅2戸から、毎日の管理費（1戸3,000Cr）が入る")
	check(housing.SALE_PRICE < main.BUILDINGS.housing.cost, "販売収入は建設費より安い（建てるだけでお金が増えない）")
	check(main.economy_system.last_report.get("garbage") >= 2, "入居済みの住宅2戸からゴミが出る（1戸につき1）")
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60, 30.0)
	check(housing.count_at_home() == 0, "朝のうちに入居者は全員出かけている")
	var inside := 0
	for m in housing.homes[homes[0]].members:
		if m.resident != null:
			inside += 1
	check(inside == 0, "出かけた入居者はビルの外にいる")
	await hover_cell(homes[0])
	check(main.hover_label.text.contains("住宅（在宅 0/3人"), "外出中は在宅0人と出る（決算の後なので評価も続けて出る）")
	
	# 2日目の夕方: 帰ってくる（販売収入は2回目は入らない）
	main.clock.set_time(2, 16, 59)
	await wait_until(func(): return main.clock.minute_of_day() >= 20 * 60 + 30, 30.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(housing.count_at_home() == 6, "夕方には6人とも帰ってくる")
	check(housing.revenue_by_day.get(2, 0) == 0, "販売収入は入居したときの1回だけ")
	return true

# ---------------------------------------------------
# シナリオ16: ホテルのツイン・スイート
# 2階(y=17)のブロックの右隣に、ツイン（横3マス、x=8〜10）・スイート（横4マス、x=11〜14）・
# ハウスキーパー室（横2マス、x=15〜16）を並べる。
# ---------------------------------------------------
func run_room_types_scenario() -> bool:
	print("[シナリオ] ツイン・スイート")
	main.funds = 10000000
	# 1階はロビー専用なので、ロビーの右隣(8,18)に階段を置いて2階(y=17)へ上がれるようにする
	main.select_mode("stairs")
	main.build_at(Vector2i(8, 18))
	main.funds = 10000000
	var hotel = main.hotel_system
	build_support(cells_row(18, 9, 16), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	var twin := Vector2i(8, 17)
	var suite := Vector2i(11, 17)
	focus_camera(Vector2i(11, 17))
	await choose_mode("hotel_twin")
	await click_cell(twin, MOUSE_BUTTON_LEFT)
	await choose_mode("hotel_suite")
	await click_cell(suite, MOUSE_BUTTON_LEFT)
	await choose_mode("housekeeping")
	await click_cell(Vector2i(15, 17), MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 200000 - 500000 - 200000, "ツイン20万Cr・スイート50万Crがかかる")
	check(main.get_unit_cells(twin).size() == 3 and main.get_unit_cells(suite).size() == 4, "ツインは横3マス、スイートは横4マス")
	check(hotel.total_capacity() == 4, "ツインとスイートは2人ずつ、定員の合計は4人")
	var others: int = main.commute_system.workers.size() - main.commute_system.count_unreachable()
	check(main.rating_system.population() == others + 4, "人口には客室の定員が入る")
	
	# 夕方: それぞれ2人ずつ泊まりに来る
	main.clock.set_time(1, 16, 59)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 21 * 60 + 30, 30.0)
	check(hotel.rooms[twin].guests.size() == 2 and hotel.rooms[suite].guests.size() == 2, "ツインとスイートにそれぞれ2人ずつ泊まる")
	var arrived := 0
	var spots := {}
	for cell in [twin, suite]:
		for guest in hotel.rooms[cell].guests:
			if main.get_unit_cells(cell).has(guest.cell) and not guest.is_moving():
				arrived += 1
				spots[guest.cell] = true
	check(arrived == 4, "4人とも部屋に着いている")
	check(spots.size() == 4, "同じ部屋の2人は別々のマスにいる（重ならない）")
	await hover_cell(suite)
	check(main.hover_label.text.contains("スイート（宿泊中・"), "カーソルを合わせると客室の種類と状態が出る")
	await capture("room_types_01_night")
	
	# 翌朝: チェックアウトで宿泊料 3.5万 + 8万、清掃時間は部屋の種類で違う
	main.clock.set_time(2, 6, 59)
	var clean_start := {}
	var clean_end := {}
	await wait_until(func():
		var now: float = main.clock.day * 1440 + main.clock.minute
		for cell in [twin, suite]:
			if hotel.get_room_state_text(cell) == "清掃中" and not clean_start.has(cell):
				clean_start[cell] = now
			if clean_start.has(cell) and hotel.rooms[cell].state == hotel.RoomState.CLEAN and not clean_end.has(cell):
				clean_end[cell] = now
		return clean_end.size() == 2, 90.0)
	check(hotel.revenue_by_day.get(2, 0) == 35000 + 80000, "チェックアウトでツイン3.5万Cr＋スイート8万Crが入る")
	check(hotel.checkouts_by_day.get(2, 0) == 2, "チェックアウトした部屋は2室と数える")
	check(clean_end.size() == 2, "ツインもスイートも清掃されてきれいな空室に戻る")
	if clean_end.size() == 2:
		var twin_minutes: float = clean_end[twin] - clean_start[twin]
		var suite_minutes: float = clean_end[suite] - clean_start[suite]
		check(absf(twin_minutes - 30.0) <= 2.0, "ツインの清掃は約30分（%.1f分）" % twin_minutes)
		check(absf(suite_minutes - 45.0) <= 2.0, "スイートの清掃は約45分（%.1f分）" % suite_minutes)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	return true

# ---------------------------------------------------
# シナリオ17: 平日・休日のサイクル
# シナリオ10と同じ建物（社員52人）＋ 2階のシャフトの右隣に住宅1戸（横3マス、x=9〜11）。
# 5日目（金）→ 6日目（土・休日）→ 8日目（月）と進めて違いを確かめる。
# ---------------------------------------------------
func run_weekday_scenario() -> bool:
	print("[シナリオ] 平日・休日")
	main.funds = 10000000
	var clock = main.clock
	check(clock.weekday(1) == 0 and not clock.is_holiday(1), "1日目は月曜日で平日")
	check(clock.is_holiday(6) and clock.is_holiday(7) and not clock.is_holiday(8), "6日目（土）・7日目（日）は休日、8日目（月）は平日")
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	var home := Vector2i(9, 17) # 1階はロビー専用なので、2階のシャフトの右隣
	build_support(cells_row(18, 9, 11), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	await choose_mode("housing")
	await click_cell(home, MOUSE_BUTTON_LEFT)
	
	# 5日目（金）: 社員は出勤し、夕方に入居者が入居する
	clock.set_time(5, 7, 59)
	clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return clock.minute_of_day() >= 10 * 60 + 45, 30.0) # 定員8人のカゴ1台では運びきるのに時間がかかるので余裕をもつ
	check(main.commute_system.count_at_office() == 52, "金曜日は52人が出勤する（10時45分）")
	clock.set_time(5, 16, 59)
	set_speed(16.0)
	await wait_until(func(): return main.housing_system.count_at_home() == 3 and clock.minute_of_day() >= 20 * 60, 30.0)
	
	# 6日目（土）: 休日。社員は来ない。入居者は遅めに出かける
	clock.set_time(6, 7, 59)
	await wait_until(func(): return clock.minute_of_day() >= 9 * 60 + 45, 30.0)
	check(main.clock_label.text.begins_with("4月6日（土）休日"), "上部バーに日付・曜日と休日が出る")
	check(main.commute_system.count_in_building() == 0, "休日は社員が出勤しない")
	check(main.housing_system.count_at_home() == 3, "休日の入居者3人は9時45分にはまだ家にいる（平日なら9時までに出かける）")
	await capture("weekday_01_holiday")
	await wait_until(func(): return clock.minute_of_day() >= 12 * 60 + 10, 30.0)
	check(main.housing_system.count_at_home() == 0, "休日の入居者は12時までに出かける")
	clock.set_time(6, 23, 58)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 6, 10.0)
	var report = main.economy_system.last_report
	check(report.get("rent") == 524000, "休日もたどり着けるオフィス52マスの賃料は入る（6階は1.1倍）")
	check(report.get("garbage") == 1, "休日はオフィスからゴミが出ない（住宅の1だけ）")
	
	# 8日目（月）: また出勤する
	clock.set_time(8, 7, 59)
	set_speed(8.0)
	await wait_until(func(): return clock.minute_of_day() >= 10 * 60 + 45, 30.0) # 定員8人のカゴ1台では運びきるのに時間がかかるので余裕をもつ
	Engine.time_scale = 1.0
	clock.set_process(false)
	check(main.commute_system.count_at_office() == 52, "月曜日はまた52人が出勤する（10時45分）")
	return true

# ---------------------------------------------------
# シナリオ18: 結婚式場・イベントホール（休日の大勢の来客）
# x=8 に y=13〜18 のシャフト、1階の右隣に結婚式場（横6マス、x=9〜14）、
# 上の階のシャフトの左にイベントホール（横6マス、x=2〜7）。イベントホールの来客はエレベーターで上がる。
# ---------------------------------------------------
func run_event_scenario() -> bool:
	print("[シナリオ] 結婚式場・イベントホール")
	main.funds = 10000000
	var events = main.event_system
	var clock = main.clock
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	var wedding := Vector2i(9, 17) # 1階はロビー専用なので、2階のシャフトの右隣
	var hall := Vector2i(2, 13)
	build_support(cells_row(18, 9, 14), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	build_support(cells_row(14, 2, 7)) # 足場: 5階(y=14)を埋めて、その上の6階に会場を建てられるようにする
	focus_camera(Vector2i(6, 16))
	await choose_mode("wedding")
	await click_cell(wedding, MOUSE_BUTTON_LEFT)
	await choose_mode("event_hall")
	await click_cell(hall, MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 6 * 80000 - 1000000 - 800000, "結婚式場100万Cr・イベントホール80万Crがかかる")
	
	# 平日（月曜日）は催しがない
	clock.set_time(1, 9, 59)
	clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return clock.minute_of_day() >= 14 * 60 + 30, 30.0)
	check(events.count_in_building() == 0, "平日は結婚式場・イベントホールに来客がない")
	
	# 休日（土曜日）: 午前は結婚式、午後はイベント
	var car = main.elevator_system.cars[0]
	var stops := [0]
	car.arrived.connect(func(_y): stops[0] += 1)
	clock.set_time(6, 9, 59)
	await wait_until(func(): return clock.minute_of_day() >= 11 * 60 + 40, 30.0)
	check(main.commute_system.count_in_building() == 0, "月曜日に出勤した社員は、日付が変わったら帰っている")
	check(events.count_at_hall(wedding) == 12, "休日の結婚式には12人が来ている")
	var spots := {}
	for v in events.halls[wedding].visitors:
		if is_instance_valid(v.resident):
			spots[v.resident.cell] = true
	check(spots.size() == 6, "来客は結婚式場の6マスに分かれている")
	await hover_cell(wedding)
	check(main.hover_label.text.contains("結婚式場（来客 12人）"), "カーソルを合わせると来客の人数が出る")
	await capture("event_01_wedding")
	await wait_until(func(): return clock.minute_of_day() >= 14 * 60 + 40, 30.0)
	check(events.count_at_hall(wedding) == 0, "結婚式が終わると来客は帰っている")
	check(events.count_at_hall(hall) == 15, "午後のイベントには15人が来ている")
	check(stops[0] > 0, "上の階のイベントホールへはエレベーターで上がる")
	await capture("event_02_hall")
	# 早送り中にフレームレートが下がると移動が遅れるので、判定は余裕をもって18時半にする
	await wait_until(func(): return clock.minute_of_day() >= 18 * 60 + 30, 30.0)
	check(events.count_in_building() == 0, "イベントが終わると来客は全員帰っている")
	check(events.revenue_by_day.get(6, 0) == 12 * 10000 + 15 * 3000, "来客の料金は12万Cr＋4.5万Cr")
	
	clock.set_time(6, 23, 58)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 6, 10.0)
	Engine.time_scale = 1.0
	clock.set_process(false)
	check(main.economy_system.last_report.get("event") == 165000, "決算にイベントの売上16.5万Crが入る")
	check(main.last_message.contains("イベント +165,000Cr"), "決算のメッセージにイベントの売上が出る")
	check(main.economy_system.last_report.get("garbage") == 2, "来客27人分のゴミ2が出る")
	return true

# ---------------------------------------------------
# シナリオ19: 地下鉄駅（地下からの入口）
# x=8 のシャフトを y=13〜19（地下1階まで）にし、地下1階のシャフトの右隣(9,19)に地下鉄駅。
# 右寄りの社員は近い地下鉄駅から、左寄りの社員は1階の入口から出勤する。
# ---------------------------------------------------
func run_subway_scenario() -> bool:
	print("[シナリオ] 地下鉄駅")
	main.funds = 100000000
	check(main.ground_y == 18, "1階の高さは y=18")
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	for y in range(19, 24): # 地下は1階のシャフトを建ててから、地下5階(y=23)まで掘り下げる
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT) # 横4マスのオフィス（x=4〜7、社員4人）
	# 左側: ロビーの左隣(-9,18)の階段で2階へ上がれるようにする（上に x=-12〜-9 のオフィス）
	# 足場: オフィス(x=-12〜-9)の下の1階に階段を足す。(-9,18)の階段は、2階へ上がる道にもなる
	build_support(cells_row(18, -12, -9))
	main.select_mode("office")
	main.build_at(Vector2i(-12, 17))
	check(main.get_entrance() == Vector2i(-12, 18), "ロビーの左に階段が続いていれば、1階の左の出入り口はその一番端（フロアの端）")
	
	# 地下鉄駅は、地下5階より深いところにしか建てられない
	await choose_mode("subway")
	await click_cell(Vector2i(9, 18), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(9, 18)), "1階には地下鉄駅を建てられない")
	check(main.last_message.contains("地下鉄駅は地下5階より深いところにしか建てられません（ここは1階）"), "建てられない理由がメッセージで出る")
	# 足場: 駅の上（1階〜地下4階）を埋めて、地下5階まで掘り下げる
	build_support(cells_row(18, 9, 12), "lobby")
	for y in range(19, 23):
		build_support(cells_row(y, 9, 12))
	await click_cell(Vector2i(9, 19), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 19)) != "subway", "地下1階では浅すぎて建てられない")
	var station := Vector2i(9, 23) # 地下5階
	await click_cell(station, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(station) == "subway", "地下5階(y=23)には地下鉄駅を建てられる")
	check(main.get_entrance() == Vector2i(-12, 18), "地下に建物ができても、1階の入口は変わらない")
	check(main.get_entrances() == [Vector2i(-12, 18), Vector2i(12, 18), station], "入口は1階の左右の出入り口と地下鉄駅")
	check(main.nearest_entrance(Vector2i(6, 13)) == station, "上の階のオフィスからは地下鉄駅の方が近い")
	check(main.nearest_entrance(Vector2i(-6, 17)) == Vector2i(-12, 18), "左寄りのオフィスからは、階段で上がれる1階の入口の方が近い")
	await capture("subway_01_built")

	
	# 平日の朝: それぞれ近い入口から出勤してくる
	var first_cells := {}
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	# 定員8人のカゴ1台では運びきるのに時間がかかるので、全員が着くか11時半になるまで待つ
	while main.clock.minute_of_day() < 11 * 60 + 30 and (main.clock.minute_of_day() < 10 * 60 or main.commute_system.count_at_office() < 56):
		for r in main.residents:
			if is_instance_valid(r) and not first_cells.has(r):
				first_cells[r] = r.cell
		await process_frame
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	var from_station := 0
	var from_main := 0
	for r in first_cells:
		if first_cells[r] == station:
			from_station += 1
		elif first_cells[r] == Vector2i(-12, 18):
			from_main += 1
	check(from_station > 0 and from_main > 0, "地下鉄駅と1階の入口の両方から社員が来る（駅 %d人・1階 %d人）" % [from_station, from_main])
	check(from_station + from_main == 56, "56人全員がどちらかの入口から来る")
	check(main.commute_system.count_at_office() == 56, "11時半までには56人全員がオフィスに着いている（%d:%02d）" % [main.clock.minute_of_day() / 60, main.clock.minute_of_day() % 60])
	
	# ★4の条件に地下鉄駅がある
	main.rating_system.stars = 3
	check(main.rating_system.missing_for_next() == ["人口250", "VIPの宿泊"], "★4の条件（人口250・地下鉄駅・VIPの宿泊）のうち、地下鉄駅は満たしている")
	main.rating_system.stars = 1
	
	# 駅があると、店へ来る外からのお客さんが増える
	var visitors = main.visitor_system
	check(is_equal_approx(visitors.subway_rate(), 1.0 + visitors.SUBWAY_BONUS), "地下鉄駅1つで、外から来るお客さんが5割増える")
	main.select_mode("shop")
	main.build_at(Vector2i(9, 17))
	main.clock.set_time(1, 11, 0)
	visitors.plan_day = 0
	main.clock.set_process(true)
	await wait_frames(3)
	var with_station: int = visitors.visits.size()
	await click_cell(station, MOUSE_BUTTON_RIGHT) # 駅を撤去する
	check(main.is_cell_empty(station), "地下鉄駅を撤去できる")
	visitors.plan_day = 0
	visitors.visits.clear()
	await wait_frames(3)
	main.clock.set_process(false)
	print("    駅あり=", with_station, "人 / 駅なし=", visitors.visits.size(), "人")
	check(with_station > visitors.visits.size(), "駅があるときの方が、店に来る人数が多い")
	check(is_equal_approx(visitors.subway_rate(), 1.0), "駅がなくなると、増え方ももとに戻る")
	return true

# ---------------------------------------------------
# シナリオ20: カゴの定員
# x=8 に y=13〜18 のシャフト、上の階 y=13 にオフィス。(7,15) に住人12人を置き、全員を (5,13) へ向かわせる。
# カゴの定員は8人なので、8人が乗り、残り4人は見送って次に来たカゴに乗る。
# ---------------------------------------------------
func run_capacity_scenario() -> bool:
	print("[シナリオ] カゴの定員")
	main.funds = 10000000
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT)
	var car = main.elevator_system.cars[0]
	check(car.capacity == 8, "カゴの定員は8人")
	
	var goal := Vector2i(5, 13)
	var people := []
	for i in 12:
		var r = main.spawn_resident(Vector2i(7, 15))
		r.go_to(goal)
		people.append(r)
	
	var max_passengers := 0
	var left_behind := false # 満員のカゴが動いている間に、乗れずに待っている人がいたか
	var captured := false
	var limit := Time.get_ticks_msec() + 30000
	set_speed(4.0)
	while Time.get_ticks_msec() < limit:
		max_passengers = maxi(max_passengers, car.passengers.size())
		var waiting := 0
		for r in people:
			if r.state == r.State.WAITING:
				waiting += 1
		if car.is_full() and car.state == car.State.MOVING and waiting > 0:
			left_behind = true
			if not captured:
				await capture("capacity_01_full")
				captured = true
		var arrived := 0
		for r in people:
			if r.cell == goal and not r.is_moving():
				arrived += 1
		if arrived == people.size():
			break
		await process_frame
	Engine.time_scale = 1.0
	check(max_passengers == 8, "カゴには最大で定員の8人までしか乗らない（最大 %d人）" % max_passengers)
	check(left_behind, "満員のカゴは乗れなかった人を残して動く")
	var arrived_all := true
	for r in people:
		if r.cell != goal or r.is_moving():
			arrived_all = false
	check(arrived_all, "乗れなかった4人も次のカゴで上がり、12人全員が目的地に着く")
	check(car.passengers.is_empty(), "全員降りたらカゴは空になる")
	await hover_cell(Vector2i(8, 16))
	check(main.hover_label.text.contains("カゴ1台: 0/8人"), "エレベーターにカーソルを合わせるとカゴの人数が出る")
	return true

# ---------------------------------------------------
# シナリオ21: 1本のシャフトに複数のカゴ
# シナリオ10と同じ建物（社員68人、x=8 のシャフト y=13〜18）に、カゴを3台追加して4台にする。
# 群管理（乗り場呼びを到着までの手間が一番小さいカゴに割り当てる）で4台が分担して運ぶので、
# カゴ1台（定員8人）では10時15分ごろまでかかった朝のラッシュが、9時45分までに終わる。
# ---------------------------------------------------
func run_multi_car_scenario() -> bool:
	print("[シナリオ] 複数のカゴ")
	main.funds = 10000000
	var elevators = main.elevator_system
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT)
	check(elevators.get_cars_at(Vector2i(8, 15)).size() == 1, "シャフトを建てるとカゴが1台できる")
	
	# カゴ追加モードでシャフトをクリックすると、その階にカゴが増える
	var funds_before: int = main.funds
	await choose_mode("add_car")
	await click_cell(Vector2i(8, 13), MOUSE_BUTTON_LEFT)
	var cars: Array = elevators.get_cars_at(Vector2i(8, 15))
	check(cars.size() == 2, "カゴ追加でシャフトのカゴが2台になる")
	check(cars[1].floor_y == 13, "追加したカゴはクリックした階(13)にいる")
	check(main.funds == funds_before - 50000, "カゴの追加に5万Crかかる")
	await click_cell(Vector2i(8, 15), MOUSE_BUTTON_LEFT)
	await click_cell(Vector2i(8, 16), MOUSE_BUTTON_LEFT)
	check(elevators.get_cars_at(Vector2i(8, 15)).size() == 4, "カゴを4台まで増やせる")
	await click_cell(Vector2i(8, 17), MOUSE_BUTTON_LEFT)
	check(elevators.get_cars_at(Vector2i(8, 15)).size() == 4, "5台目は追加できない")
	check(main.last_message.contains("4台まで"), "追加できない理由がメッセージで出る")
	await click_cell(Vector2i(6, 13), MOUSE_BUTTON_LEFT)
	check(main.last_message.contains("シャフトに追加します"), "シャフト以外をクリックすると理由がメッセージで出る")
	await hover_cell(Vector2i(8, 14))
	check(main.hover_label.text.contains("カゴ4台: 0/8・0/8・0/8・0/8人"), "カーソルを合わせると各カゴの人数が出る")
	
	# 群管理: 乗り場の呼び出しは、到着までの手間が一番小さいカゴに割り当てる
	var all_cars: Array = elevators.get_cars_at(Vector2i(8, 15)) # 18階・13階・15階・16階にいる
	elevators.request_hall(Vector2i(8, 14), ElevatorCar.Direction.UP)
	var assigned = elevators.hall_assignments.get([Vector2i(8, 14), ElevatorCar.Direction.UP])
	check(assigned != null and assigned.floor_y in [13, 15], "止まっているカゴなら、一番近いカゴ（13階か15階）に割り当てる")
	assigned.up_calls.clear() # 確認用の呼び出しを取り消す
	elevators.hall_assignments.clear()
	# 17階から18階へ下っている途中のカゴと、18階で止まっているカゴ: 16階の「上へ」は18階のカゴの方が早い
	var moving = all_cars[3] # 16階のカゴを17階へ動かしたことにする
	moving.floor_y = 17
	moving.position = moving.floor_position(17)
	moving.direction = ElevatorCar.Direction.DOWN
	moving.car_calls[18] = true
	var idle_bottom = all_cars[0]
	check(moving.estimate_cost(16, ElevatorCar.Direction.UP) > idle_bottom.estimate_cost(16, ElevatorCar.Direction.UP), "逆方向に進んでいるカゴは、折り返す分だけ手間が大きいと見積もる")
	check(elevators.choose_car(Vector2i(8, 16), ElevatorCar.Direction.UP) == idle_bottom or elevators.choose_car(Vector2i(8, 16), ElevatorCar.Direction.UP).floor_y == 15, "近くても逆方向に進んでいるカゴは選ばない")
	# 満員のカゴは選ばない
	for i in 8:
		moving.passengers.append(main.spawn_resident(Vector2i(7, 18)))
	moving.direction = ElevatorCar.Direction.UP
	moving.car_calls.clear()
	moving.car_calls[13] = true
	check(elevators.choose_car(Vector2i(8, 16), ElevatorCar.Direction.UP) != moving, "満員のカゴには割り当てない")
	for r in moving.passengers:
		r.queue_free()
	moving.passengers.clear()
	moving.car_calls.clear()
	moving.direction = ElevatorCar.Direction.NONE
	await wait_frames(2)
	
	# 朝のラッシュ: 4台で分担して運ぶ
	var done_time := ""
	var done_minute := 0
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	var captured := false
	while main.clock.minute_of_day() < 10 * 60 + 45:
		if not captured and main.clock.minute_of_day() >= 8 * 60 + 40:
			await capture("multi_car_01_rush")
			captured = true
		if done_time == "" and main.commute_system.count_at_office() == 52:
			done_time = main.clock.get_time_text()
			done_minute = main.clock.minute_of_day()
		await process_frame
	print("    rush done at ", done_time)
	check(done_time != "" and done_minute <= 9 * 60 + 45, "4台の群管理なら9時45分までに52人全員がオフィスに着く（全員着いた時刻: %s）" % done_time)
	
	# 追加したカゴの維持費: 3台 × 3千Cr
	main.clock.set_time(1, 23, 58)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 1, 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(main.economy_system.last_report.get("maintenance") == 12000 + 3 * 3000, "追加したカゴ3台の維持費9千Crがかかる")
	return true

# ---------------------------------------------------
# シナリオ22: 建設メニュー・上下スクロール・時刻で変わる空の色
# ---------------------------------------------------
func run_scroll_sky_scenario() -> bool:
	print("[シナリオ] 建設メニュー・スクロール・空の色")
	main.funds = 100000000
	var cam = main.camera
	
	# 建設メニュー: 見出しごとに並び、クリックするとリストが開く
	var select: OptionButton = main.mode_select
	var headers: Array[String] = []
	for i in select.item_count:
		if select.is_item_separator(i):
			headers.append(select.get_item_text(i))
	check(headers == ["テナント", "ロビー・移動", "設備", "その他"], "建設メニューは見出し（テナント・ロビー・移動・設備・その他）ごとに並ぶ")
	# 押した瞬間にリストが開く（離す位置がリストの項目の上だと、その項目が選ばれて閉じるので、押すだけにする）
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = select.get_global_rect().get_center()
	press.global_position = press.position
	root.push_input(press)
	await wait_frames(2)
	check(select.get_popup().visible, "建設メニューをクリックするとリストが開く")
	select.get_popup().hide()
	await choose_mode("hotel_suite")
	check(select.text.begins_with("スイート") and select.text.ends_with("500,000Cr"), "選んだ建物の名前と建設費が出る")
	
	# マウスホイール: 上下スクロール（ズームはしない）
	var screen_pos := Vector2(600, 400)
	var zoom_before: float = cam.zoom.x
	var y_before: float = cam.position.y
	await scroll_wheel(screen_pos, MOUSE_BUTTON_WHEEL_UP, 3, false)
	check(is_equal_approx(cam.zoom.x, zoom_before), "Ctrlなしのホイールではズームしない")
	check(is_equal_approx(cam.position.y, y_before - 3 * cam.WHEEL_SCROLL / cam.zoom.y), "ホイール上で画面が上へスクロールする")
	var x_before: float = cam.position.x
	await scroll_wheel(screen_pos, MOUSE_BUTTON_WHEEL_DOWN, 2, false, true)
	check(cam.position.x > x_before, "Shift+ホイールで左右にスクロールする")
	
	# 高く建てると、スクロールバーの範囲が上に広がる
	var min_before: float = main.v_scroll.min_value
	main.select_mode("elevator")
	for y in range(18, 2, -1):
		main.build_at(Vector2i(8, y))
	await wait_frames(2)
	check(main.v_scroll.min_value < min_before, "上へ建てるとスクロールできる範囲が上に広がる")
	check(is_equal_approx(main.v_scroll.min_value, (3 - main.SCROLL_MARGIN_ROWS) * 16.0), "一番上の建物(y=3)の上に10行分スクロールできる")
	# スクロールバーを一番上へ動かすと、カメラも一番上へ
	main.v_scroll.value = main.v_scroll.min_value
	await wait_frames(2)
	check(is_equal_approx(cam.position.y - main.v_scroll.page / 2.0, main.v_scroll.min_value), "スクロールバーを動かすとカメラが動く")
	await capture("scroll_01_top")
	focus_camera(Vector2i(6, 15))
	
	# 空の色: 時刻とともに変わる
	var clock = main.clock
	var colors := {}
	for t in [[3, 0, "night"], [6, 0, "dawn"], [12, 0, "noon"], [17, 45, "evening"], [21, 0, "late"]]:
		clock.set_time(1, t[0], t[1])
		colors[t[2]] = clock.sky_color()
		await wait_frames(2)
		await capture("sky_%02d%02d_%s" % [t[0], t[1], t[2]])
	check(colors.night.get_luminance() < 0.1, "深夜の空は暗い")
	check(colors.noon.b > colors.noon.r and colors.noon.get_luminance() > 0.5, "昼の空は明るい青")
	check(colors.dawn.r > colors.dawn.b, "朝焼けは赤みがある")
	check(colors.evening.r > colors.evening.g and colors.evening.r > colors.evening.b, "夕方の空はオレンジ")
	check(clock.darkness() > 0.5, "夜は暗く、星が見える")
	clock.set_time(1, 12, 0)
	check(clock.darkness() == 0.0, "昼は星が見えない")
	clock.set_time(1, 12, 1)
	var c1: Color = clock.sky_color()
	clock.set_time(1, 17, 0)
	var c2: Color = clock.sky_color()
	clock.set_time(1, 17, 1)
	check(clock.sky_color().is_equal_approx(c2) == false and c2.lerp(clock.sky_color(), 0.5).is_equal_approx(c2.lerp(clock.sky_color(), 0.5)), "空の色は1分ごとに少しずつ変わる")
	check(not c1.is_equal_approx(c2), "昼と夕方前で空の色が違う")
	return true

# ---------------------------------------------------
# シナリオ23: 夜の明かり
# 2階(y=17)のブロックの右隣に、シングル（x=8〜9）・住宅（x=10〜12）・警備室（x=13〜14）。(8,18)の階段で上がる。
# 昼は明かりの重ね描きなし。夜は建物が暗くなり、人がいる部屋・設備にだけ明かりが灯る。
# ---------------------------------------------------
func run_night_light_scenario() -> bool:
	print("[シナリオ] 夜の明かり")
	main.funds = 100000000
	# 1階はロビー専用なので、ロビーの右隣(8,18)に階段を置いて2階(y=17)へ上がれるようにする
	main.select_mode("stairs")
	main.build_at(Vector2i(8, 18))
	main.funds = 100000000
	var lighting = main.lighting
	build_support(cells_row(18, 9, 14), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	var room := Vector2i(8, 17)
	var home := Vector2i(10, 17)
	var security := Vector2i(13, 17)
	focus_camera(Vector2i(8, 16))
	await choose_mode("hotel")
	await click_cell(room, MOUSE_BUTTON_LEFT)
	await choose_mode("housing")
	await click_cell(home, MOUSE_BUTTON_LEFT)
	await choose_mode("security")
	await click_cell(security, MOUSE_BUTTON_LEFT)
	
	# 昼: 建物は暗くならない。社員がいるオフィスには明かりの判定がある（昼は描かない）
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60 + 45, 30.0)
	check(main.tile_map.self_modulate == Color.WHITE, "昼は建物が暗くならない")
	var lit: Dictionary = lighting.get_lit_cells()
	check(lit.has(Vector2i(0, 17)) and lit.has(security), "社員がいるオフィス・設備は明かりが灯る扱いになる")
	check(not lit.has(room) and not lit.has(home), "客や住人がいない客室・住宅は明かりが灯らない")
	
	# 夜: 宿泊客・住人が帰ってくる。オフィスは誰もいない
	main.clock.set_time(1, 16, 59)
	set_speed(16.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 21 * 60 + 30, 30.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	lit = lighting.get_lit_cells()
	check(main.clock.darkness() > 0.5, "21時半は暗い")
	check(main.tile_map.self_modulate.get_luminance() < 0.6, "夜は建物のタイルが暗くなる")
	check(lit.has(room) and lit.has(room + Vector2i(1, 0)), "宿泊客がいる客室は部屋全体に明かりが灯る")
	check(lit.has(home) and lit.has(home + Vector2i(2, 0)), "家にいる人の部屋に明かりが灯る")
	check(lit.has(security), "警備室は一晩中明かりが灯る")
	check(not lit.has(Vector2i(0, 17)), "社員が帰ったオフィスは暗いまま")
	await capture("night_01_lights")
	return true

# ---------------------------------------------------
# シナリオ24: 太陽と月
# 太陽は5:30に昇って18:30に沈み、月は18:30に昇って翌朝5:30に沈む。空の中を弧を描いて動く。
# ---------------------------------------------------
func run_sun_moon_scenario() -> bool:
	print("[シナリオ] 太陽と月")
	var clock = main.clock
	var soil = main.grid_overlay.soil
	clock.set_time(1, 12, 0)
	check(is_equal_approx(clock.sun_progress(), 0.5) and clock.moon_progress() < 0.0, "昼の12時は太陽が真ん中にあり、月は出ていない")
	clock.set_time(1, 3, 0)
	check(clock.sun_progress() < 0.0 and clock.moon_progress() > 0.0, "深夜は月が出ていて、太陽は出ていない")
	clock.set_time(1, 5, 30)
	check(is_equal_approx(clock.sun_progress(), 0.0) and is_equal_approx(clock.moon_progress(), 1.0), "5時30分に太陽が昇り、月が沈む")
	clock.set_time(1, 18, 30)
	check(is_equal_approx(clock.sun_progress(), 1.0) and is_equal_approx(clock.moon_progress(), 0.0), "18時30分に太陽が沈み、月が昇る")
	
	# 位置: 昇る・沈むときは低く左右の端、真ん中の時刻は高い
	var rect := Rect2(0, 0, 400, 200)
	var rise: Vector2 = soil.celestial_position(0.0, rect, 200.0)
	var noon: Vector2 = soil.celestial_position(0.5, rect, 200.0)
	var sunset: Vector2 = soil.celestial_position(1.0, rect, 200.0)
	check(rise.x < noon.x and noon.x < sunset.x, "左から昇って右へ沈む")
	check(noon.y < rise.y and noon.y < sunset.y, "真ん中の時刻が一番高い")
	
	focus_camera(Vector2i(0, 14))
	for t in [[6, 30, "sunrise"], [12, 0, "noon"], [18, 0, "sunset"], [23, 0, "moon"]]:
		clock.set_time(1, t[0], t[1])
		await wait_frames(2)
		await capture("sun_moon_%02d%02d_%s" % [t[0], t[1], t[2]])
	return true

# ---------------------------------------------------
# シナリオ25: 夜の演出（街灯・入口の照明）
# 街灯はビルの外の地面（1階の高さの空きマス）に4マスおきに立ち、夜に灯る。入口の扉の周りも光る。
# ---------------------------------------------------
func run_street_lamp_scenario() -> bool:
	print("[シナリオ] 街灯・入口の照明")
	var lighting = main.lighting
	var view := Rect2(-30 * 16, 0, 60 * 16, 400)
	var lamps: Array[Vector2] = lighting.get_street_lamps(view)
	check(not lamps.is_empty(), "ビルの外の地面に街灯が立つ")
	var on_building := false
	var spacing_ok := true
	for lamp in lamps:
		var x := int(floor(lamp.x / 16.0))
		if not main.is_cell_empty(Vector2i(x, main.ground_y)):
			on_building = true
		if posmod(x, lighting.LAMP_SPACING) != 0:
			spacing_ok = false
	check(not on_building, "建物があるマスには街灯を立てない（ブロックの x=-8〜7 には立たない）")
	check(spacing_ok, "街灯は4マスおきに立つ")
	check(is_equal_approx(lamps[0].y + lighting.LAMP_HEIGHT, (main.ground_y + 1) * 16.0), "街灯は地面の線の上に立つ")
	
	# 建物を建てると、そのマスの街灯はなくなる
	main.funds = 10000000
	var lamp_x := 12 # 4の倍数なので街灯が立つ位置
	check(lighting.get_street_lamps(view).any(func(p): return int(floor(p.x / 16.0)) == lamp_x), "x=12 に街灯がある")
	main.select_mode("lobby")
	main.build_at(Vector2i(12, main.ground_y))
	check(not lighting.get_street_lamps(view).any(func(p): return int(floor(p.x / 16.0)) == lamp_x), "建物を建てるとそのマスの街灯はなくなる")
	
	# 入口の照明: 入口の数だけ
	check(lighting.get_entrance_lights().size() == main.get_entrances().size(), "入口ごとに照明がある")
	
	focus_camera(Vector2i(2, 15))
	main.clock.set_time(1, 22, 0)
	await wait_frames(3)
	await capture("street_lamp_01_night")
	main.clock.set_time(1, 12, 0)
	await wait_frames(3)
	await capture("street_lamp_02_day")
	return true

# ---------------------------------------------------
# シナリオ26: テナント（オフィス）の評価
# シナリオ10と同じ建物（x=8 のシャフトにカゴ1台）。朝のラッシュで、エレベーターを待つ上の階の
# 社員はストレスがたまり、歩くだけの1階の社員はたまらない。決算でオフィスごとの評価が分かれる。
# ---------------------------------------------------
func run_tenant_rating_scenario() -> bool:
	print("[シナリオ] オフィスの評価")
	main.funds = 10000000
	var tenants = main.tenant_system
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT)
	check(tenants.offices.is_empty(), "最初の決算まではオフィスの評価がない")
	check(tenants.rating_for(10.0) == tenants.Rating.GOOD and tenants.rating_for(45.0) == tenants.Rating.NORMAL \
		and tenants.rating_for(80.0) == tenants.Rating.BAD, "平均ストレス30未満は良い・60未満は普通・それ以上は悪い")
	
	await run_day(1)
	for origin in tenants.offices:
		print("    ", origin, " ", tenants.get_rating_text(origin))
	check(tenants.offices.size() == 13, "決算で13棟すべてのオフィスに評価が付く")
	# エレベーターで1階分だけ上がる2階（y=17）は、一番上の階（y=13）より待ち時間が短く、ストレスが低い
	var second_floor := 0.0
	for x in [-8, -4, 0, 4]:
		second_floor += tenants.offices[Vector2i(x, 17)].average / 4.0
	check(second_floor < tenants.offices[Vector2i(4, 13)].average, "2階のオフィスの平均ストレス（%d）は一番上の階（%d）より低い" % [int(second_floor), int(tenants.offices[Vector2i(4, 13)].average)])
	var upper_bad := 0
	for origin in tenants.offices:
		if tenants.offices[origin].rating == tenants.Rating.BAD:
			upper_bad += 1
	check(upper_bad > 0, "カゴ1台でエレベーター待ちが長いので、評価が悪いオフィスがある（%d棟）" % upper_bad)
	await hover_cell(Vector2i(6, 13))
	check(main.hover_label.text.contains("オフィス（家賃 普通") and main.hover_label.text.contains("評価: "), "カーソルを合わせるとオフィスの家賃・評価・平均ストレスが出る")
	check(main.stats_label.text.contains("オフィス: 良い"), "ビルの状況に評価ごとのオフィスの数が出る")
	await capture("tenant_rating_01")
	
	# 休日は出勤がないので評価は変わらない
	var before := {}
	for origin in tenants.offices:
		before[origin] = tenants.offices[origin].rating
	await run_day(6)
	var unchanged := true
	for origin in before:
		if tenants.offices[origin].rating != before[origin]:
			unchanged = false
	check(unchanged, "休日は出勤がないので、オフィスの評価はそのまま")
	return true

# ---------------------------------------------------
# シナリオ27: オフィスの退去と新しいテナントの入居
# シナリオ26と同じ建物（カゴ1台）で平日を3日続けると、評価の悪いオフィスは3日目の決算で退去して空室になる。
# 空室の間は社員が出勤せず賃料も入らない。空室になって2日後の決算で新しいテナントが入居する。
# ---------------------------------------------------
func run_vacancy_scenario() -> bool:
	print("[シナリオ] オフィスの退去と入居")
	main.funds = 10000000
	var tenants = main.tenant_system
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7)) # 足場: 5階(y=14)を埋めて、その上に6階のオフィスを建てられるようにする
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT)
	
	await run_day(1)
	await run_day(2)
	var bad_twice := []
	for origin in tenants.offices:
		if tenants.offices[origin].bad_days == 2:
			bad_twice.append(origin)
	check(not bad_twice.is_empty() and tenants.count_vacant() == 0, "悪い日が2日続いても、まだ退去しない（悪い2日目: %d棟）" % bad_twice.size())
	await hover_cell(Vector2i(4, 13))
	check(main.hover_label.text.contains("悪い日が2日続いている"), "悪い日が続いている日数がカーソルで出る")
	
	# 3日目の決算: 悪い日が3日続いたオフィスは退去
	await run_day(3)
	var vacant := []
	for origin in tenants.offices:
		if tenants.offices[origin].vacant:
			vacant.append(origin)
	check(vacant.size() == mini(bad_twice.size(), tenants.MAX_LEAVE_PER_DAY), "悪い日が3日続いたオフィスが退去して空室になる（1日%d棟まで）" % tenants.MAX_LEAVE_PER_DAY)
	check(main.last_message.contains("オフィス退去 %d棟" % vacant.size()), "決算のメッセージに退去した数が出る")
	check(main.rating_system.population() == 52 - 4 * vacant.size(), "空室のオフィスの社員は人口に数えない")
	await hover_cell(vacant[0])
	check(main.hover_label.text.contains("空室・2日後から入居者を募集"), "空室にカーソルを合わせると入居者の募集までの日数が出る")
	check(main.stats_label.text.contains("空室%d" % vacant.size()), "ビルの状況に空室の数が出る")
	await capture("vacancy_01_vacant")
	
	# 4日目: 空室の社員は出勤せず、賃料も入らない
	await run_day(4)
	var came := 0
	for origin in vacant:
		for cell in main.get_unit_cells(origin):
			if main.commute_system.workers[cell].arrived_day == 4:
				came += 1
	check(came == 0, "空室のオフィスには社員が出勤しない")
	check(main.economy_system.last_report.get("rent") < 520000, "空室のオフィスからは賃料が入らない（賃料 %dCr）" % main.economy_system.last_report.get("rent"))
	check(tenants.offices[vacant[0]].vacant, "空室になって1日目はまだ空室")
	# 4日目の決算では、2日目から悪い日が続いていたオフィスも退去する
	var second_wave: int = tenants.count_vacant() - vacant.size()
	print("    4日目に退去: %d棟" % second_wave)
	
	# 5日目の決算: 3日目に空室になったオフィスは2日たったので、新しいテナントが入居する
	#（ゴミ処理場がないので衛生の悪化が進み、ゴキブリも出ている。汚れたビルには入居が決まりにくいので、きれいに戻しておく）
	check(tenants.move_in_chance(vacant[0]) < 1.0, "衛生の悪化やゴキブリのあるビルは、入居が決まりにくい（%d%%）" % int(tenants.move_in_chance(vacant[0]) * 100))
	main.economy_system.pollution = 0
	main.incident_system.roaches.clear()
	build_support([Vector2i(-8, 19), Vector2i(-5, 19), Vector2i(-2, 19)], "recycling") # ゴミ処理場3つ（1日60まで処理）で、きれいなまま保つ
	check(tenants.move_in_chance(vacant[0]) == 1.0, "きれいなビルで家賃が普通なら、募集を始めた日に入居が決まる")
	await run_day(5)
	var moved_in := true
	for origin in vacant:
		if tenants.offices[origin].vacant:
			moved_in = false
	check(moved_in, "空室になって2日たつと、新しいテナントが入居する（%d棟）" % vacant.size())
	check(tenants.count_vacant() >= second_wave, "後から退去したオフィスは、まだ空室のまま（%d棟）" % tenants.count_vacant())
	check(tenants.offices[vacant[0]].rating == tenants.Rating.GOOD and tenants.offices[vacant[0]].bad_days == 0, "新しいテナントの評価は「良い」から始まる")
	check(main.last_message.contains("入居 %d棟" % vacant.size()), "決算のメッセージに入居した数が出る")
	return true

# ---------------------------------------------------
# シナリオ28: ホテルの客室の評価
# 2階(y=17)のブロックの右隣にシングル（x=8〜9）とハウスキーパー室（x=10〜11）。(8,18)の階段で上がる。
# 泊まった客のストレスが高いと、チェックアウトで部屋の評価が悪くなり、客が来にくくなる。
# ---------------------------------------------------
func run_hotel_rating_scenario() -> bool:
	print("[シナリオ] ホテルの客室の評価")
	main.funds = 10000000
	main.select_mode("stairs")
	main.build_at(Vector2i(8, 18))
	var tenants = main.tenant_system
	var hotel = main.hotel_system
	build_support(cells_row(18, 9, 11), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	var room := Vector2i(8, 17)
	main.select_mode("hotel")
	main.build_at(room)
	main.select_mode("housekeeping")
	main.build_at(Vector2i(10, 17))
	check(tenants.hotel_checkin_chance(room) == 1.0, "まだ評価のない部屋には、客が必ず来る")
	
	# 1日目の夜: 客が泊まりに来る。客をイライラさせておく（エレベーター待ちでストレスがたまった想定）
	main.clock.set_time(1, 16, 59)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 21 * 60 + 30, 30.0)
	check(hotel.rooms[room].state == hotel.RoomState.OCCUPIED, "客が泊まっている")
	for guest in hotel.rooms[room].guests:
		guest.stress = 90.0
	await wait_frames(2)
	# 2日目の朝: チェックアウトで部屋の評価が決まる
	main.clock.set_time(2, 6, 59)
	await wait_until(func(): return hotel.rooms[room].state != hotel.RoomState.OCCUPIED, 30.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(tenants.rooms.has(room) and tenants.rooms[room].rating == tenants.Rating.BAD, "ストレスの高い客が泊まった部屋は、評価が悪くなる")
	await hover_cell(room + Vector2i(1, 0))
	check(main.hover_label.text.contains("評価: 悪い"), "客室にカーソルを合わせると評価が出る")
	check(is_equal_approx(tenants.hotel_checkin_chance(room), 0.2), "評価の悪い部屋に客が来る確率は20%")
	var nights := 0
	for day in range(1, 101):
		if hotel.checkin_roll(room, day) < tenants.hotel_checkin_chance(room):
			nights += 1
	check(nights > 5 and nights < 40, "評価の悪い部屋には、100日のうち2割くらいしか客が来ない（%d日）" % nights)
	tenants.rate_hotel_stay(room, 10.0)
	check(tenants.rooms[room].rating == tenants.Rating.GOOD and tenants.hotel_checkin_chance(room) == 1.0, "次の客が快適に泊まれば評価は良くなり、また毎晩客が来る")
	await capture("hotel_rating_01")
	return true

# ---------------------------------------------------
# シナリオ29: 住宅の評価と退去
# 2階(y=17)のブロックの右隣に住宅（x=8〜10）。(8,18)の階段で上がる。
# 家族のストレスが高い日が3日続くと退去して販売収入を返金し、2日後にまた入居者を募集する。
# ---------------------------------------------------
func run_home_rating_scenario() -> bool:
	print("[シナリオ] 住宅の評価と退去")
	main.funds = 10000000
	main.select_mode("stairs")
	main.build_at(Vector2i(8, 18))
	var tenants = main.tenant_system
	var housing = main.housing_system
	build_support(cells_row(18, 9, 10), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	var home := Vector2i(8, 17)
	main.select_mode("housing")
	main.build_at(home)
	
	# 1〜3日目（平日）: 夕方に家族が帰ってくる。家族をイライラさせておき、その日の決算まで進める
	for day in [1, 2, 3]:
		await run_home_evening(day, true)
	check(tenants.homes[home].vacant, "家族のストレスが高い日が3日続くと、家族が退去する")
	check(not housing.homes[home].moved_in and housing.count_at_home() == 0, "退去すると住宅は空になる")
	check(main.economy_system.last_report.get("refund") == 350000, "退去した住宅の販売収入35万Crを返金する")
	check(logged("住宅の返金 -350,000Cr（1戸退去）"), "決算のメッセージに返金が出る")
	await hover_cell(home)
	check(main.hover_label.text.contains("退去・2日後に入居者を募集"), "カーソルを合わせると、入居者の募集までの日数が出る")
	await capture("home_rating_01_moved_out")
	
	# 4日目: 退去した後は、次の入居者を募集するまで誰も来ない
	await run_home_evening(4, false)
	check(not housing.homes[home].moved_in, "退去した後の2日間は、新しい家族は来ない")
	# 5日目の決算で募集を再開し、6日目（土・休日）の夕方に新しい家族が入居する
	await run_home_evening(5, false)
	check(not tenants.homes[home].vacant, "退去して2日たつと、また入居者を募集する")
	await run_home_evening(6, false)
	check(housing.homes[home].moved_in, "新しい家族が入居する")
	check(main.economy_system.last_report.get("housing") == 350000, "新しい家族の入居で、また販売収入35万Crが入る")
	return true

# 指定した日の夕方に住宅の家族を帰らせ（stressed なら全員のストレスを高くする）、その日の決算まで進める
func run_home_evening(day: int, stressed: bool) -> void:
	var start := 14 * 60 + 59 if main.clock.is_holiday(day) else 16 * 60 + 59
	main.clock.set_time(day, start / 60, start % 60)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 20 * 60 + 30, 30.0)
	if stressed:
		for home in main.housing_system.homes.values():
			for m in home.members:
				if is_instance_valid(m.resident):
					m.resident.stress = 90.0
		await wait_frames(2)
	main.clock.set_time(day, 23, 58)
	await wait_until(func(): return main.economy_system.last_report.get("day") == day, 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)

# ---------------------------------------------------
# シナリオ30: 吹き抜けロビー（高さのある建物）
# 共通のビルの1階ロビー（x=-8〜7）の右隣に、2階分（x=8）と3階分（x=9）の吹き抜けロビーを建てる。
# ---------------------------------------------------
func run_atrium_scenario() -> bool:
	print("[シナリオ] 吹き抜けロビー")
	main.funds = 10000000
	focus_camera(Vector2i(8, 16))
	await choose_mode("lobby2")
	check(main.mode_select.tooltip_text == "建設費 30,000Cr・横1マス・高さ2階分", "カーソルを合わせると高さが出る")
	await click_cell(Vector2i(8, 17), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(8, 17)), "吹き抜けロビーも1階からしか建てられない")
	await click_cell(Vector2i(8, 18), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(8, 18)) == "lobby2" and main.get_building_type(Vector2i(8, 17)) == "lobby2", "2階分の吹き抜けロビーは1階と2階のマスを使う")
	check(main.funds == 10000000 - 30000, "2階分の吹き抜けロビーは3万Cr")
	await choose_mode("lobby3")
	await click_cell(Vector2i(9, 18), MOUSE_BUTTON_LEFT)
	check(main.get_unit_cells(Vector2i(9, 16)) == [Vector2i(9, 18), Vector2i(9, 17), Vector2i(9, 16)], "3階分の吹き抜けロビーは1〜3階のマスを使う")
	
	# 上の部分には床がないので、ほかの建物は建てられず、人も歩けない
	await choose_mode("office")
	await click_cell(Vector2i(8, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(8, 17)) == "lobby2", "吹き抜けの上の部分にはほかの建物を建てられない")
	check(main.is_walkable(Vector2i(8, 18)) and not main.is_walkable(Vector2i(8, 17)), "歩けるのは吹き抜けロビーの1階だけ")
	check(main.can_move(Vector2i(7, 18), Vector2i(8, 18)), "1階では、ロビーから吹き抜けロビーへ歩いて行ける")
	check(not main.can_move(Vector2i(7, 17), Vector2i(8, 17)), "2階のオフィスから吹き抜けの上の部分へは入れない")
	check(main.get_entrance() == Vector2i(-8, 18), "入口は今までどおりロビーの左端")
	await capture("atrium_01")
	
	# どのマスを右クリックしても、吹き抜けロビー全体を撤去する
	await click_cell(Vector2i(9, 16), MOUSE_BUTTON_RIGHT)
	check(main.is_cell_empty(Vector2i(9, 18)) and main.is_cell_empty(Vector2i(9, 16)), "上の部分を右クリックしても、吹き抜けロビー全体を撤去する")
	return true

# ---------------------------------------------------
# シナリオ31: スカイロビー（15階・30階…だけに建てられる乗り換えフロア）
# 1階は y=18 なので、15階は y=4、30階は y=-11。
# ---------------------------------------------------
func run_sky_lobby_scenario() -> bool:
	print("[シナリオ] スカイロビー")
	main.funds = 10000000
	check(main.get_floor_name(18) == "1階" and main.get_floor_name(4) == "15階" and main.get_floor_name(20) == "B2階", "階の名前: y=18 は1階、y=4 は15階、y=20 はB2階")
	check(main.is_sky_lobby_floor(4) and main.is_sky_lobby_floor(-11) and not main.is_sky_lobby_floor(5) and not main.is_sky_lobby_floor(18), "スカイロビーを建てられるのは15階・30階…だけ")
	focus_camera(Vector2i(2, 5))
	# 足場: スカイロビーを建てる x=0〜4 の下（5階〜14階）を埋めて、15階まで積み上げる
	for y in range(14, 4, -1):
		build_support(cells_row(y, 0, 4))
	await choose_mode("sky_lobby")
	await click_cell(Vector2i(6, 5), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(6, 5)), "14階にはスカイロビーを建てられない")
	check(main.last_message.contains("15階・30階・45階…にしか建てられません（ここは14階）"), "建てられる階と、今の階がメッセージで出る")
	for x in range(0, 5):
		await click_cell(Vector2i(x, 4), MOUSE_BUTTON_LEFT)
	check(main.find_cells_of_type("sky_lobby").size() == 5, "15階にはスカイロビーを1マスずつ横に伸ばせる")
	check(main.funds == 10000000 - 5 * 50000, "スカイロビーは1マス5万Cr")
	check(main.is_walkable(Vector2i(2, 4)) and main.can_move(Vector2i(1, 4), Vector2i(2, 4)), "スカイロビーは歩いて移動できる")
	check(main.get_entrances() == [Vector2i(-8, 18), Vector2i(7, 18)], "スカイロビーは入口にはならない（入口は1階の左右の出入り口だけ）")
	await hover_cell(Vector2i(2, 4))
	check(main.hover_label.text.begins_with("15階: スカイロビー"), "吹き出しの先頭に何階かが出る")
	await capture("sky_lobby_01")
	return true

# ---------------------------------------------------
# シナリオ32: 急行エレベーター（1階とスカイロビーの階だけに停まる）
#   共通のビルの上に14階（y=5）までオフィスを積み、x=8 の急行シャフト（1階〜15階。y=18〜4）で
#   15階のスカイロビー（x=3〜7）へ上がり、x=2 の標準シャフト（15階〜18階。y=4〜1）に乗り換えて、
#   17階のオフィス（y=2、x=-2〜1）へ行く。建物の支えのルールを守って、下の階から建てる。
# ---------------------------------------------------
func run_express_elevator_scenario() -> bool:
	print("[シナリオ] 急行エレベーター")
	main.funds = 100000000
	main.select_mode("office")
	for y in range(14, 4, -1):
		for x in [-8, -4, 0, 4]:
			main.build_at(Vector2i(x, y))
	main.funds = 10000000
	await choose_mode("express_elevator")
	check(main.mode_select.tooltip_text == "建設費 120,000Cr・横1マス（1階とスカイロビーの階だけに停まる）", "カーソルを合わせると停まる階の説明が出る")
	for y in range(18, 3, -1):
		main.build_at(Vector2i(8, y))
	check(main.funds == 10000000 - 15 * 120000, "急行エレベーターは1マス12万Cr")
	main.select_mode("sky_lobby")
	for x in range(3, 8):
		main.build_at(Vector2i(x, 4))
	main.select_mode("elevator")
	for y in range(4, 0, -1):
		main.build_at(Vector2i(2, y))
	main.select_mode("office")
	for y in [4, 3, 2]:
		main.build_at(Vector2i(-2, y))
	check(main.get_building_type(Vector2i(0, 2)) == "office" and main.get_building_type(Vector2i(2, 1)) == "elevator", "15階から上も、下の階から積み上げて建てられる")
	
	# 急行のカゴは速く、定員が多い
	var express = main.elevator_system.get_car_at(Vector2i(8, 18))
	var standard = main.elevator_system.get_car_at(Vector2i(2, 4))
	check(express.shaft_type == "express_elevator" and express.top_y == 4 and express.bottom_y == 18, "急行のシャフトは1階〜15階")
	check(express.speed == standard.speed * 3 and express.capacity == 20 and standard.capacity == 8, "急行は標準の3倍の速さで、定員は20人")
	check(main.elevator_system.get_cars_at(Vector2i(2, 4)) == [standard], "急行と標準のシャフトは別々にカゴを持つ")
	
	# 乗り降りできるのは1階とスカイロビーの階だけ
	check(main.can_move(Vector2i(8, 18), Vector2i(8, 4)) and main.can_move(Vector2i(8, 4), Vector2i(8, 18)), "急行は1階と15階の間を行き来できる")
	check(not main.can_move(Vector2i(8, 18), Vector2i(8, 10)), "急行は途中の階（9階）には停まらない")
	check(not main.can_move(Vector2i(8, 10), Vector2i(8, 4)), "途中の階からは急行に乗れない")
	check(main.find_path(Vector2i(-8, 18), Vector2i(4, 10)).is_empty(), "急行のシャフトの途中の階（9階）の隣のオフィスには、急行では行けない")
	check(not express.request_floor(10), "急行のカゴは途中の階の行き先ボタンを受け付けない")
	
	focus_camera(Vector2i(8, 10))
	await wait_frames(1)
	await hover_cell(Vector2i(8, 10))
	check(main.hover_label.text.contains("急行エレベーター（この階には停まりません）"), "途中の階のシャフトには、停まらないことが出る")
	await choose_mode("express_elevator")
	check(not main.can_click_cell(Vector2i(8, 10)), "急行モードで途中の階のシャフトは赤く表示される")
	check(main.can_click_cell(Vector2i(8, 18)), "1階のシャフトはクリックでカゴを呼べる")
	await click_cell(Vector2i(8, 10), MOUSE_BUTTON_LEFT)
	check(main.last_message == "急行エレベーターは1階とスカイロビーの階にしか停まりません", "途中の階ではカゴを呼べない")
	check(main.get_building_type(Vector2i(8, 10)) == "express_elevator", "シャフトをクリックしても建て直さない")
	
	# 1階の入口から、急行 → 15階で標準に乗り換え → 17階のオフィスへ
	var goal := Vector2i(0, 2)
	var route: Array[Vector2i] = main.find_path(Vector2i(-8, 18), goal)
	check(count_rides(route) == 2 and route.has(Vector2i(8, 4)) and route.has(Vector2i(2, 4)), "経路は急行で15階へ上がり、スカイロビーで標準に乗り換える")
	var r = main.spawn_resident(Vector2i(-8, 18))
	r.go_to(goal)
	set_speed(4.0)
	var rode_express := false
	var captured := false
	var limit := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < limit and not (r.cell == goal and r.path.is_empty()):
		if r.state == r.State.RIDING and r.car == express:
			rode_express = true
			if not captured and express.position.y < main.tile_map.map_to_local(Vector2i(8, 12)).y:
				focus_camera(Vector2i(6, 7))
				Engine.time_scale = 1.0
				await capture("express_01_riding")
				set_speed(4.0)
				captured = true
		await wait_frames(1)
	Engine.time_scale = 1.0
	check(rode_express, "住人は急行に乗った")
	check(r.cell == goal and r.path.is_empty(), "住人は乗り換えて17階のオフィスに着いた")
	focus_camera(Vector2i(4, 6))
	await wait_frames(2)
	await capture("express_02_arrived")
	return true

# ---------------------------------------------------
# シナリオ33: 建物の支え（下の階に建物がないと建てられない）
#   共通のビルは 1階（y=18）が x=-8〜7 のロビー、2〜4階（y=17〜15）が x=-8〜7 のオフィス。
# ---------------------------------------------------
func run_support_scenario() -> bool:
	print("[シナリオ] 建物の支え")
	main.funds = 10000000
	focus_camera(Vector2i(2, 16))
	await wait_frames(1)
	await choose_mode("office")
	# 5階（y=14）: 下の4階のオフィスの上なら建てられる
	await click_cell(Vector2i(0, 14), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(0, 14)) == "office", "下の階が全部埋まっていれば建てられる")
	# 右にはみ出す（x=8・9 の下が空いている）と建てられない
	await click_cell(Vector2i(6, 14), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(6, 14)), "一部でも下が空いていると建てられない")
	check(main.last_message.begins_with("下の階に建物がないと建てられません"), "建てられない理由（支えがない）がメッセージで出る")
	await hover_cell(Vector2i(6, 14))
	check(not main.can_click_cell(Vector2i(6, 14)), "支えがない場所は赤く表示される")
	await click_cell(Vector2i(0, 12), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(0, 12)), "空中（下の階が空き）には建てられない")
	await choose_mode("elevator")
	await click_cell(Vector2i(-9, 17), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(-9, 17)), "エレベーターも下から積み上げる（ロビーの外の2階には建てられない）")
	await click_cell(Vector2i(8, 18), MOUSE_BUTTON_LEFT)
	await click_cell(Vector2i(8, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(8, 17)) == "elevator", "1階から上へ積み上げれば建てられる")
	
	# 地下は上の階から掘り進める
	await choose_mode("office")
	await click_cell(Vector2i(0, 19), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(0, 19)) == "office", "ロビーの真下のB1階には建てられる")
	await click_cell(Vector2i(0, 20), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(0, 20)) == "office", "B1階の真下のB2階にも建てられる")
	await click_cell(Vector2i(10, 19), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(10, 19)), "上の階に建物がない地下には建てられない")
	check(main.last_message == "地下は、上の階に建物がある場所にしか建てられません", "建てられない理由（地下）がメッセージで出る")
	await capture("support_01")
	
	# 支えている建物を撤去すると、支えを保つために「空きフロア」が残る
	var funds_before: int = main.funds
	await click_cell(Vector2i(2, 15), MOUSE_BUTTON_RIGHT)
	check(main.get_building_type(Vector2i(2, 15)) == "frame", "上の階を支えているオフィスを撤去すると、空きフロアが残る")
	check(main.get_building_type(Vector2i(0, 14)) == "office", "上の階のオフィスはそのまま残る")
	check(main.last_message.contains("空きフロアになります"), "空きフロアが残ることがメッセージで出る")
	check(main.funds == funds_before - 40000, "跡地が残るときも撤去費用（4万Cr）がかかる")
	await click_cell(Vector2i(0, 18), MOUSE_BUTTON_RIGHT)
	check(main.get_building_type(Vector2i(0, 18)) == "frame", "上に建物が乗っているロビーも、空きフロアになる")
	await click_cell(Vector2i(0, 19), MOUSE_BUTTON_RIGHT)
	check(main.get_building_type(Vector2i(0, 19)) == "frame", "下にB2階があるB1階も、空きフロアになる")
	check(main.get_building_type(Vector2i(0, 20)) == "office", "地下も、下の階はそのまま残る")
	await click_cell(Vector2i(0, 19), MOUSE_BUTTON_RIGHT)
	check(main.get_building_type(Vector2i(0, 19)) == "frame", "跡地そのものは、支えている間は撤去できない")
	check(main.last_message.begins_with("下の階の建物を支えているため撤去できません"), "撤去できない理由がメッセージで出る")
	await click_cell(Vector2i(0, 14), MOUSE_BUTTON_RIGHT)
	check(main.is_cell_empty(Vector2i(0, 14)), "一番上の建物は、跡地を残さず撤去できる")
	await click_cell(Vector2i(2, 15), MOUSE_BUTTON_RIGHT)
	check(main.is_cell_empty(Vector2i(2, 15)), "上が空けば、跡地も更地に戻せる")
	await click_cell(Vector2i(8, 18), MOUSE_BUTTON_RIGHT)
	check(main.get_building_type(Vector2i(8, 18)) == "frame", "シャフトの途中のマスも、空きフロアになる（シャフトが分かれる）")
	await click_cell(Vector2i(8, 17), MOUSE_BUTTON_RIGHT)
	await click_cell(Vector2i(8, 18), MOUSE_BUTTON_RIGHT)
	check(main.is_cell_empty(Vector2i(8, 18)), "上が空けば、シャフトの跡地も更地に戻せる")
	return true

# ---------------------------------------------------
# シナリオ34: エスカレーター（左下の乗り口と、1つ上の階の右のマスを斜めにつなぐ）
#   ロビーの右（x=10〜13）にロビーを足し、x=8 のエスカレーターで2階の x=9 へ、
#   x=9 のエスカレーターで3階の x=10 へ上がる。3階（y=16）には x=10〜13 のオフィス。
# ---------------------------------------------------
func run_escalator_scenario() -> bool:
	print("[シナリオ] エスカレーター")
	main.funds = 10000000
	focus_camera(Vector2i(9, 17))
	await wait_frames(1)
	main.select_mode("lobby")
	for x in range(10, 14):
		main.build_at(Vector2i(x, 18))
	await choose_mode("escalator")
	check(main.mode_select.text.begins_with("エスカレーター") and main.mode_select.text.ends_with("100,000Cr"), "エスカレーターは10万Cr")
	await click_cell(Vector2i(8, 18), MOUSE_BUTTON_LEFT)
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT)
	check(main.get_unit_cells(Vector2i(9, 18)) == [Vector2i(8, 18), Vector2i(9, 18)], "1階にエスカレーター（横2マス）を建てられる")
	check(main.get_building_type(Vector2i(10, 17)) == "escalator", "2階にもエスカレーターを重ねて建てられる")
	check(main.funds == 10000000 - 4 * 15000 - 2 * 100000, "エスカレーター2基で20万Cr")
	main.select_mode("security")
	main.build_at(Vector2i(11, 17))
	main.select_mode("stairs")
	main.build_at(Vector2i(13, 17))
	main.select_mode("office")
	main.build_at(Vector2i(10, 16))
	check(main.get_building_type(Vector2i(10, 16)) == "office", "3階のオフィスはエスカレーター・警備室・階段の上に建つ")
	
	# 乗り口（左のマス）と、上の階の右のマスの上（降り口）を斜めにつなぐ。上りも下りも使える
	check(main.can_move(Vector2i(8, 18), Vector2i(9, 17)) and main.can_move(Vector2i(9, 17), Vector2i(8, 18)), "1階の乗り口と2階の降り口を上り下りできる")
	check(main.can_move(Vector2i(9, 17), Vector2i(10, 16)), "降り口がそのまま上のエスカレーターの乗り口になる")
	check(not main.can_move(Vector2i(9, 18), Vector2i(9, 17)) and not main.can_move(Vector2i(8, 18), Vector2i(8, 17)), "右のマスや真上には上がれない")
	check(main.is_escalator_ride(Vector2i(8, 18), Vector2i(9, 17)) and not main.is_elevator_ride(Vector2i(8, 18), Vector2i(9, 17)), "エスカレーターの移動はエレベーターとは別")
	var route: Array[Vector2i] = main.find_path(Vector2i(-8, 18), Vector2i(12, 16))
	check(route.has(Vector2i(8, 18)) and route.has(Vector2i(9, 17)) and route.has(Vector2i(10, 16)), "3階のオフィスへはエスカレーターを2回乗り継いで行く")
	check(count_rides(route) == 0, "エレベーターには乗らない")
	
	# 定員がないので、大勢でも待たずに上がれる
	var people := []
	for i in 12:
		var r = main.spawn_resident(Vector2i(4, 18))
		r.go_to(Vector2i(12, 16))
		people.append(r)
	set_speed(2.0)
	var captured := false
	var waited := false
	var limit := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < limit and people.any(func(r): return r.is_moving()):
		for r in people:
			if r.state != r.State.WALKING:
				waited = true
		if not captured and people.any(func(r): return r.cell == Vector2i(9, 17)):
			Engine.time_scale = 1.0
			await capture("escalator_01")
			set_speed(2.0)
			captured = true
		await wait_frames(1)
	Engine.time_scale = 1.0
	check(people.all(func(r): return r.cell == Vector2i(12, 16)), "12人全員が3階のオフィスに着いた")
	check(not waited, "エスカレーターでは誰も待たされない（ストレスがたまらない）")
	check(main.economy_system.MAINTENANCE["escalator"] == 2000, "エスカレーターの維持費は1基2,000Cr/日")
	return true

# ---------------------------------------------------
# シナリオ35: エレベーターの待機階（呼び出しがないとカゴが戻る階）
#   x=8 に 1階〜6階（y=18〜13）のシャフトを建て、3階（y=16）を待機階にする。
# ---------------------------------------------------
func run_home_floor_scenario() -> bool:
	print("[シナリオ] エレベーターの待機階")
	main.funds = 10000000
	var elevators = main.elevator_system
	focus_camera(Vector2i(8, 16))
	await wait_frames(1)
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	var car = elevators.cars[0]
	check(car.floor_y == 18 and not car.has_home_floor, "最初は待機階がなく、カゴは建てた階で止まったまま")
	
	await choose_mode("set_home")
	check(main.mode_select.text.begins_with("待機階を設定") and main.mode_select.text.ends_with("無料") and main.mode_select.tooltip_text.begins_with("無料"), "建設メニューに「待機階を設定」がある")
	await click_cell(Vector2i(0, 17), MOUSE_BUTTON_LEFT)
	check(main.last_message == "待機階はエレベーターのシャフトに設定します", "シャフト以外をクリックすると理由がメッセージで出る")
	check(not main.can_click_cell(Vector2i(0, 17)) and main.can_click_cell(Vector2i(8, 16)), "シャフトのマスだけ操作できる（緑）")
	await click_cell(Vector2i(8, 16), MOUSE_BUTTON_LEFT)
	check(elevators.get_home(Vector2i(8, 18)) == 16, "クリックした階がシャフトの待機階になる")
	check(main.last_message.begins_with("3階を待機階にしました"), "何階を待機階にしたかがメッセージで出る")
	check(car.has_home_floor and car.home_y == 16, "シャフトのカゴに待機階が伝わる")
	check(elevators.get_home_cells() == [Vector2i(8, 16)], "待機階のマスに印を描く")
	await hover_cell(Vector2i(8, 16))
	check(main.hover_label.text.contains("エレベーター（待機階）"), "カーソルを合わせると待機階と出る")
	
	# 呼び出しがなくなると、カゴは待機階に戻る
	set_speed(4.0)
	await wait_until(func(): return car.floor_y == 16 and car.state == car.State.IDLE, 20.0)
	check(car.floor_y == 16, "呼び出しがないカゴは待機階（3階）に戻って待つ")
	await hover_cell(Vector2i(12, 16)) # 印が見えるように、カーソルはシャフトから外しておく
	await capture("home_floor_01")
	await choose_mode("elevator")
	await click_cell(Vector2i(8, 13), MOUSE_BUTTON_LEFT) # 6階に呼ぶ
	await wait_until(func(): return car.floor_y == 13, 20.0)
	check(car.floor_y == 13, "呼ばれた階には行く")
	await wait_until(func(): return car.floor_y == 16 and car.state == car.State.IDLE, 20.0)
	check(car.floor_y == 16, "用事が済むとまた待機階に戻る")
	Engine.time_scale = 1.0
	
	# 同じ階をもう一度クリックすると解除
	await choose_mode("set_home")
	await click_cell(Vector2i(8, 16), MOUSE_BUTTON_LEFT)
	check(elevators.get_home(Vector2i(8, 18)) == null and not car.has_home_floor, "同じ階をもう一度クリックすると待機階を解除する")
	check(main.last_message.begins_with("待機階を解除しました"), "解除したことがメッセージで出る")
	check(elevators.get_home_cells().is_empty(), "印も消える")
	return true

# ---------------------------------------------------
# シナリオ36: エレベーターの稼働時間帯（決めた時間帯の外では動かない）
#   x=8 に 1階〜6階（y=18〜13）のシャフト、6階（y=13）にオフィス。
# ---------------------------------------------------
func run_service_hours_scenario() -> bool:
	print("[シナリオ] エレベーターの稼働時間帯")
	main.funds = 10000000
	var elevators = main.elevator_system
	focus_camera(Vector2i(8, 16))
	await wait_frames(1)
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	build_support(cells_row(14, 4, 7))
	await click_cell(Vector2i(4, 13), MOUSE_BUTTON_LEFT)
	var car = elevators.cars[0]
	check(elevators.get_service(Vector2i(8, 16)).name == "終日" and car.in_service, "最初は終日動いている")
	
	# クリックするたびに 終日 → 6時〜24時 → 8時〜20時 と切り替わる
	await choose_mode("service")
	check(main.mode_select.text.begins_with("稼働時間帯") and main.mode_select.text.ends_with("無料"), "建設メニューに「稼働時間帯」（無料）がある")
	await click_cell(Vector2i(0, 17), MOUSE_BUTTON_LEFT)
	check(main.last_message == "稼働時間帯はエレベーターのシャフトに設定します", "シャフト以外をクリックすると理由がメッセージで出る")
	await click_cell(Vector2i(8, 16), MOUSE_BUTTON_LEFT)
	check(elevators.get_service(Vector2i(8, 16)).name == "6時〜24時", "1回クリックすると6時〜24時になる")
	await click_cell(Vector2i(8, 16), MOUSE_BUTTON_LEFT)
	check(elevators.get_service(Vector2i(8, 16)).name == "8時〜20時", "もう1回クリックすると8時〜20時になる")
	check(main.last_message.contains("「8時〜20時」にしました"), "切り替えた時間帯がメッセージで出る")
	
	# 時間帯の外（朝7時）: 呼べず、経路にも使われない
	main.clock.set_time(1, 7, 0)
	await wait_frames(2)
	check(not car.in_service, "7時はシャフトが止まっている")
	check(not main.can_move(Vector2i(8, 18), Vector2i(8, 13)), "止まっている間はエレベーターで移動できない")
	check(main.find_path(Vector2i(-8, 18), Vector2i(5, 13)).is_empty(), "止まっている間は6階のオフィスへの経路がなくなる")
	check(not car.request_floor(13), "止まっている間は行き先ボタンを受け付けない")
	await hover_cell(Vector2i(8, 16))
	check(main.hover_label.text.contains("（稼働 8時〜20時・今は停止中）"), "カーソルを合わせると稼働時間帯と停止中が出る")
	await capture("service_hours_01_stopped")
	
	# 時間帯の中（昼12時）: いつもどおり動く
	main.clock.set_time(1, 12, 0)
	await wait_frames(2)
	check(car.in_service, "12時はシャフトが動いている")
	check(main.can_move(Vector2i(8, 18), Vector2i(8, 13)), "動いている間はエレベーターで移動できる")
	check(not main.find_path(Vector2i(-8, 18), Vector2i(5, 13)).is_empty(), "6階のオフィスへも行ける")
	await hover_cell(Vector2i(8, 16))
	check(main.hover_label.text.contains("（稼働 8時〜20時）") and not main.hover_label.text.contains("停止中"), "動いている間は停止中と出ない")
	
	# 時間帯の外になると、カゴは待機階に戻って止まる
	await choose_mode("set_home")
	await click_cell(Vector2i(8, 17), MOUSE_BUTTON_LEFT) # 2階を待機階に
	await choose_mode("elevator")
	await click_cell(Vector2i(8, 13), MOUSE_BUTTON_LEFT) # 6階にカゴを呼んでおく
	set_speed(4.0)
	await wait_until(func(): return car.floor_y == 13, 20.0)
	main.clock.set_time(1, 21, 0)
	await wait_until(func(): return car.floor_y == 17 and car.state == car.State.IDLE, 20.0)
	Engine.time_scale = 1.0
	check(car.floor_y == 17, "時間帯の外になると、カゴは待機階（2階）に戻って止まる")
	return true

# ---------------------------------------------------
# シナリオ37: サービスエレベーター（裏方＝清掃員だけが乗れる）
#   x=8 に1階〜3階（y=18〜16）のサービスシャフト、2階にハウスキーパー室（x=9〜10）、
#   3階に客室（x=9〜10）。客はこのシャフトに乗れないので3階の客室へは行けない。
# ---------------------------------------------------
func run_service_elevator_scenario() -> bool:
	print("[シナリオ] サービスエレベーター")
	main.funds = 10000000
	var hotel = main.hotel_system
	focus_camera(Vector2i(9, 16))
	await wait_frames(1)
	build_support(cells_row(18, 9, 10), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	await choose_mode("service_elevator")
	check(main.mode_select.text.begins_with("サービスエレベーター") and main.mode_select.text.ends_with("80,000Cr"), "サービスエレベーターは1マス8万Cr")
	for y in range(18, 15, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 3 * 80000, "1階から3階までのシャフトで24万Cr")
	var car = main.elevator_system.cars[0]
	check(car.shaft_type == "service_elevator" and car.capacity == 8, "サービスのシャフトにカゴが1台できる（定員は標準と同じ8人）")
	main.select_mode("housekeeping")
	main.build_at(Vector2i(9, 17))
	main.select_mode("hotel")
	main.build_at(Vector2i(9, 16))
	check(hotel.housekeepers.size() == 2 and hotel.rooms.size() == 1, "2階に清掃員が2人、3階に客室が1室")
	
	# 乗れるのは裏方だけ
	check(main.can_move(Vector2i(8, 18), Vector2i(8, 16), true), "清掃員はサービスエレベーターに乗れる")
	check(not main.can_move(Vector2i(8, 18), Vector2i(8, 16)), "社員や客はサービスエレベーターに乗れない")
	check(main.find_path(Vector2i(-8, 18), Vector2i(9, 16)).is_empty(), "客は3階の客室にたどり着けない")
	check(not main.find_path(Vector2i(-8, 18), Vector2i(9, 16), true).is_empty(), "清掃員なら3階の客室まで行ける")
	check(main.get_moves(Vector2i(8, 18)).size() < main.get_moves(Vector2i(8, 18), true).size(), "裏方かどうかで移動できる先が変わる")
	await hover_cell(Vector2i(8, 17))
	check(main.hover_label.text.contains("サービスエレベーター"), "カーソルを合わせると種類が出る")
	
	# 汚れた客室を、清掃員がサービスエレベーターで上がって掃除する
	hotel.rooms[Vector2i(9, 16)].state = hotel.RoomState.DIRTY
	main.clock.set_process(true) # 清掃はゲーム内の時間で進むので、時計を動かす
	set_speed(8.0)
	var rode := false
	var limit := Time.get_ticks_msec() + 60000
	var captured := false
	while Time.get_ticks_msec() < limit and hotel.rooms[Vector2i(9, 16)].state == hotel.RoomState.DIRTY:
		for cell in hotel.housekeepers:
			var keeper: Dictionary = hotel.housekeepers[cell]
			if is_instance_valid(keeper.resident) and keeper.resident.state == keeper.resident.State.RIDING:
				rode = true
				if not captured:
					Engine.time_scale = 1.0
					await capture("service_elevator_01_riding")
					set_speed(8.0)
					captured = true
		await wait_frames(1)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(rode, "清掃員はサービスエレベーターに乗って上の階へ行く")
	check(hotel.rooms[Vector2i(9, 16)].state == hotel.RoomState.CLEAN, "3階の客室が掃除されてきれいになる")
	check(main.economy_system.MAINTENANCE["service_elevator"] == 1500, "サービスエレベーターの維持費は1マス1,500Cr/日")
	return true

# ---------------------------------------------------
# シナリオ38: 地下駐車場とスロープ（車で来るお客さん）
#   地下1階（y=19）に スロープ(x=9〜10)・階段(x=11)・駐車場(x=12〜15)、
#   2階（y=17）に飲食店(x=9〜11)。車で来た客は階段で1階へ上がり、飲食店で食事して帰る。
# ---------------------------------------------------
func run_parking_scenario() -> bool:
	print("[シナリオ] 地下駐車場とスロープ")
	main.funds = 10000000
	var parking = main.parking_system
	focus_camera(Vector2i(10, 18))
	await wait_frames(1)
	# 足場: 地下を掘るため1階にロビーを足し、(9,18)は2階へ、(11,19)は1階へ上がる階段にする
	build_support([Vector2i(8, 18)] + cells_row(18, 10, 15), "lobby")
	build_support([Vector2i(9, 18), Vector2i(11, 19)])
	main.select_mode("restaurant")
	main.build_at(Vector2i(9, 17))
	
	# スロープは地下にだけ建てられる
	await choose_mode("ramp")
	check(main.mode_select.text.begins_with("スロープ") and main.mode_select.text.ends_with("200,000Cr"), "スロープは20万Cr")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 17)) == "restaurant", "スロープは地上には建てられない")
	await click_cell(Vector2i(9, 19), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 19)) == "ramp", "地下1階にはスロープを建てられる")
	await hover_cell(Vector2i(9, 19))
	check(main.hover_label.text.contains("車が下りてこられます"), "地下1階のスロープは1階から車が下りてこられる")
	
	# 駐車場は、同じ階のスロープまで行けるときだけ使える
	await choose_mode("parking")
	await click_cell(Vector2i(12, 19), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(15, 19)) == "parking", "地下駐車場は横4マス")
	check(main.funds == 10000000 - 200000 - 300000 - 200000, "スロープ20万Cr・駐車場30万Crがかかる（飲食店20万Crを含む）")
	check(parking.usable_units == [Vector2i(12, 19)] and parking.car_capacity() == 4, "スロープにつながった駐車場は4台使える")
	await hover_cell(Vector2i(14, 19))
	check(main.hover_label.text.contains("地下駐車場（4台）"), "カーソルを合わせると停められる台数が出る")
	await click_cell(Vector2i(12, 20), MOUSE_BUTTON_LEFT) # 地下2階の、スロープのない駐車場
	check(parking.usable_units == [Vector2i(12, 19)] and parking.car_capacity() == 4, "同じ階にスロープがない駐車場は使えない")
	await hover_cell(Vector2i(12, 20))
	check(main.hover_label.text.contains("車で下りてこられるスロープにつながっていないので使えません"), "使えない理由がカーソルで出る")
	await capture("parking_01_built")
	
	
	# 昼に車で来て、飲食店で食事をして帰る
	main.clock.set_time(1, 10, 59)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return parking.count_visitors() > 0, 30.0)
	check(parking.count_visitors() > 0, "昼になると、車で来たお客さんが駐車場に現れる")
	await wait_until(func(): return parking.visitors_by_day.get(1, 0) > 0, 30.0)
	await capture("parking_02_visitors")
	await wait_until(func(): return main.clock.minute_of_day() >= 16 * 60, 60.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(parking.visitors_by_day.get(1, 0) == 8, "4台×2人＝8人が飲食店で食事をする")
	check(main.commerce_system.revenue_by_day.get(1, 0) >= 8000, "食事の代金8,000Crが飲食店の売上になる")
	check(parking.count_visitors() == 0, "食事が済んだお客さんは車で帰る")
	check(main.economy_system.MAINTENANCE["parking"] == 5000 and main.economy_system.MAINTENANCE["ramp"] == 2000, "維持費は駐車場5,000Cr・スロープ2,000Cr")
	
	# 地下3階にスロープを建てても、地下2階にスロープがなければ車は下りてこられない
	await choose_mode("ramp")
	await click_cell(Vector2i(12, 21), MOUSE_BUTTON_LEFT)
	await hover_cell(Vector2i(12, 21))
	check(main.hover_label.text.contains("車が下りてこられません"), "上の階のスロープが抜けていると、車は下りてこられない")
	await click_cell(Vector2i(12, 21), MOUSE_BUTTON_RIGHT)
	
	# 地下2階にもスロープを足すと、地下2階の駐車場も使えるようになる
	build_support([Vector2i(11, 20)]) # スロープと駐車場の間をつなぐ階段
	await choose_mode("ramp")
	await click_cell(Vector2i(9, 20), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 20)) == "ramp", "地下2階にもスロープを建てられる")
	check(parking.car_capacity() == 8, "地下1階から順にスロープをつなぐと、地下2階の駐車場も使える（8台）")
	await hover_cell(Vector2i(9, 20))
	check(main.hover_label.text.contains("車が下りてこられます"), "つながったスロープはカーソルでわかる")
	await click_cell(Vector2i(9, 19), MOUSE_BUTTON_RIGHT)
	check(main.get_building_type(Vector2i(9, 19)) == "frame", "上のスロープを撤去すると空きフロアが残り、下の階へは車で行けなくなる")
	check(parking.car_capacity() == 0, "途中のスロープがなくなると、下の階の駐車場も使えなくなる")
	await capture("parking_03_two_floors")
	return true

# ---------------------------------------------------
# シナリオ39: ショップと、外から来るお客さん（休日営業）
#   2階（y=17）にショップ(x=9〜11)と飲食店(x=12〜14)。入口から外のお客さんが来る。
#   平日はショップ3人・飲食店2人、休日はショップ10人・飲食店8人。
# ---------------------------------------------------
func run_shop_scenario() -> bool:
	print("[シナリオ] ショップと外からのお客さん")
	main.funds = 10000000
	var visitors = main.visitor_system
	focus_camera(Vector2i(11, 17))
	await wait_frames(1)
	# 足場: 1階にロビーを足し、(9,18)はショップへ上がる階段にする
	build_support([Vector2i(8, 18)] + cells_row(18, 10, 14), "lobby")
	build_support([Vector2i(9, 18)])
	await choose_mode("shop")
	check(main.mode_select.text.begins_with("ショップ") and main.mode_select.text.ends_with("250,000Cr"), "ショップは25万Cr")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(11, 17)) == "shop", "2階にショップを建てられる")
	main.select_mode("restaurant")
	main.build_at(Vector2i(12, 17))
	check(main.funds == 10000000 - 250000 - 200000, "ショップ25万Cr・飲食店20万Crがかかる")
	
	# 平日（1日目・月曜）: ショップ3人・飲食店2人が入口から来る
	main.clock.set_time(1, 10, 59)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return visitors.count_visitors() > 0, 30.0)
	check(visitors.count_visitors() > 0, "昼になると、外からお客さんが入口に現れる")
	await wait_until(func(): return main.clock.minute_of_day() >= 15 * 60, 60.0)
	check(visitors.customers_by_day.get(1, 0) == 5, "平日はショップ3人・飲食店2人の計5人が来る")
	check(visitors.revenue_by_day.get(1, 0) == 3 * 1500, "ショップの売上は1人1,500Cr")
	check(main.commerce_system.revenue_by_day.get(1, 0) >= 2 * 1000, "飲食店の外からの客の代金は飲食の売上に入る")
	await capture("shop_01_weekday")
	
	# 休日（6日目・土曜）: 社員は来ないが、店にはもっとお客さんが来る
	main.clock.set_time(6, 9, 59)
	set_speed(16.0)
	await wait_until(func(): return visitors.count_visitors() > 0, 30.0)
	check(main.clock.is_holiday(6), "6日目は休日")
	await wait_until(func(): return main.clock.minute_of_day() >= 19 * 60, 90.0)
	Engine.time_scale = 1.0
	check(visitors.customers_by_day.get(6, 0) == 18, "休日はショップ10人・飲食店8人の計18人が来る")
	check(visitors.revenue_by_day.get(6, 0) == 10 * 1500, "休日のショップの売上は1.5万Cr")
	await hover_cell(Vector2i(10, 17))
	check(main.hover_label.text.contains("ショップ（客"), "カーソルを合わせると店にいる客の数が出る")
	
	# 決算にショップの売上が出る
	main.clock.set_time(6, 23, 58)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 6, 20.0)
	main.clock.set_process(false)
	check(main.economy_system.last_report.get("shop") == 15000, "決算にショップの売上1.5万Crが入る")
	check(main.last_message.contains("ショップ +15,000Cr"), "決算のメッセージにショップの売上が出る")
	check(main.economy_system.MAINTENANCE["shop"] == 3000, "ショップの維持費は3,000Cr/日")
	return true

# ---------------------------------------------------
# シナリオ40: 映画館（上映時刻に客が一斉に来て、終わると一斉に帰る）
#   2階（y=17）に映画館（x=9〜16、高さ2階分）。入口から階段(9,18)で上がる。
# ---------------------------------------------------
func run_cinema_scenario() -> bool:
	print("[シナリオ] 映画館")
	main.funds = 10000000
	var visitors = main.visitor_system
	focus_camera(Vector2i(13, 16))
	await wait_frames(1)
	# 足場: 1階にロビーを足し、(9,18)は映画館へ上がる階段にする
	build_support([Vector2i(8, 18)] + cells_row(18, 10, 16), "lobby")
	build_support([Vector2i(9, 18)])
	await choose_mode("cinema")
	check(main.mode_select.text.begins_with("映画館") and main.mode_select.text.ends_with("1,500,000Cr"), "映画館は150万Cr")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(16, 17)) == "cinema" and main.get_building_type(Vector2i(16, 16)) == "cinema", "映画館は横8マス・上下2階分を使う")
	check(main.funds == 10000000 - 1500000, "建設費150万Crがかかる")
	check(main.is_walkable(Vector2i(12, 17)) and not main.is_walkable(Vector2i(12, 16)), "人が歩くのは下の階だけ")
	check(visitors.showtimes(1) == [13 * 60, 16 * 60, 19 * 60], "平日は13時・16時・19時の3回上映")
	check(visitors.showtimes(6) == [11 * 60, 14 * 60, 17 * 60, 20 * 60], "休日は11時・14時・17時・20時の4回上映")
	await hover_cell(Vector2i(12, 17))
	check(main.hover_label.text.contains("映画館（閉館・次の上映 13:00）"), "カーソルを合わせると、閉館中と次の上映時刻が出る")
	
	# 平日1回目の上映（13時）: 30分前から集まり、15時に一斉に帰る
	main.clock.set_time(1, 12, 25)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return visitors.count_at_shop(Vector2i(12, 17)) >= 10, 40.0)
	check(visitors.count_at_shop(Vector2i(12, 17)) >= 10, "上映前に客が10人集まる")
	await capture("cinema_01_showtime")
	await wait_until(func(): return main.clock.minute_of_day() >= 15 * 60 + 20, 40.0)
	check(visitors.count_at_shop(Vector2i(12, 17)) == 0, "上映（2時間）が終わると一斉に帰る")
	check(visitors.cinema_audience_by_day.get(1, 0) == 10, "1回の上映の客は10人")
	check(visitors.cinema_revenue_by_day.get(1, 0) == 10 * 1800, "料金は1人1,800Cr")
	
	# 駐車場があると客が増える（この日はもう予定が決まっているので、翌日から効く）
	main.clock.set_process(false)
	Engine.time_scale = 1.0
	main.funds = 10000000
	build_support(cells_row(18, 17, 22), "lobby") # 足場: スロープと駐車場の真上の1階
	main.select_mode("ramp")
	main.build_at(Vector2i(17, 19))
	main.select_mode("parking")
	main.build_at(Vector2i(19, 19))
	check(main.parking_system.car_capacity() == 4, "スロープにつながった駐車場で4台停められる")
	main.clock.set_time(2, 12, 25)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return visitors.cinema_audience_by_day.get(2, 0) >= 14, 40.0)
	check(visitors.cinema_audience_by_day.get(2, 0) == 14, "駐車場4台ぶん、1回の客が10人から14人に増える")
	await wait_until(func(): return main.clock.minute_of_day() >= 23 * 60 + 58, 90.0)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 2, 20.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(main.economy_system.last_report.get("cinema") == 3 * 14 * 1800, "決算に3回の上映の売上（75,600Cr）が入る")
	check(main.last_message.contains("映画館 +75,600Cr"), "決算のメッセージに映画館の売上が出る")
	check(main.economy_system.MAINTENANCE["cinema"] == 20000, "映画館の維持費は2万Cr/日")
	focus_camera(Vector2i(13, 16))
	# スクリーンの見た目（3日目・平日）: 閉館は幕が閉じ、開場中は幕が開いて白いスクリーン、上映中は映画が映る
	var screen = main.cinema_screen
	main.clock.set_time(3, 9, 0)
	check(visitors.cinema_state() == visitors.CinemaState.CLOSED, "上映の30分前より前は閉館")
	await wait_frames(2)
	await capture("cinema_00_closed")
	main.clock.set_time(3, 12, 40)
	check(visitors.cinema_state() == visitors.CinemaState.OPEN, "上映の30分前からは開場中")
	await hover_cell(Vector2i(12, 17))
	check(main.hover_label.text.contains("開場中・次の上映 13:00"), "開場中は、カーソルを合わせると次の上映時刻が出る")
	await capture("cinema_00_open")
	main.clock.set_time(3, 13, 50)
	check(visitors.cinema_state() == visitors.CinemaState.SHOWING and visitors.current_show() == 13 * 60, "上映が始まると上映中")
	await hover_cell(Vector2i(12, 17))
	check(main.hover_label.text.contains("上映中・15:00 まで"), "上映中は、カーソルを合わせると終わる時刻が出る")
	await capture("cinema_00_showing")
	main.clock.set_time(3, 15, 30)
	check(visitors.cinema_state() == visitors.CinemaState.OPEN, "上映と上映の間は開場中")
	main.clock.set_time(3, 21, 30)
	check(visitors.cinema_state() == visitors.CinemaState.CLOSED and visitors.next_show() == -1, "最後の上映が終わると閉館")
	await hover_cell(Vector2i(12, 17))
	check(main.hover_label.text.contains("閉館・今日の上映は終わり"), "閉館後は、今日の上映が終わったことが出る")
	check(screen.visible and screen.z_index > main.grid_overlay.z_index, "スクリーンの表示は建物のタイルより手前に描く")
	return true

# ---------------------------------------------------
# シナリオ41: ビルの大きさの上限（地上150階・地下50階・横100マス）
#   1階は y=18 なので、150階は y=-131、地下50階は y=68。横は x=-50〜49。
# ---------------------------------------------------
func run_size_limit_scenario() -> bool:
	print("[シナリオ] ビルの大きさの上限")
	main.funds = 100000000
	check(main.MAX_FLOORS_ABOVE == 150 and main.MAX_FLOORS_BELOW == 50 and main.MAX_WIDTH == 100, "上限は地上150階・地下50階・横100マス")
	var top: int = main.ground_y - (main.MAX_FLOORS_ABOVE - 1) # 150階
	check(main.get_floor_name(top) == "150階" and main.get_floor_name(top - 1) == "151階", "150階より上は151階")
	main.select_mode("elevator")
	check(main.get_size_limit_problem(Vector2i(0, top), "elevator") == "", "150階は上限の中")
	check(main.get_build_problem(Vector2i(0, top - 1), "elevator") == "ビルは地上150階までです", "151階には建てられない")
	var bottom: int = main.ground_y + main.MAX_FLOORS_BELOW # 地下50階
	check(main.get_floor_name(bottom) == "B50階", "一番下は地下50階")
	check(main.get_size_limit_problem(Vector2i(0, bottom), "elevator") == "", "地下50階は上限の中")
	check(main.get_build_problem(Vector2i(0, bottom + 1), "elevator") == "地下は50階までです", "地下51階には建てられない")
	
	# 横幅（x=-50〜49）。横に長い建物は、右端がはみ出すと建てられない
	check(main.get_size_limit_problem(Vector2i(-50, 17), "elevator") == "", "左端（x=-50）は上限の中")
	check(main.get_build_problem(Vector2i(-51, 17), "elevator").begins_with("ビルの幅は100マスまでです"), "左端より外には建てられない")
	check(main.get_size_limit_problem(Vector2i(49, 17), "elevator") == "", "右端（x=49）は上限の中")
	check(main.get_build_problem(Vector2i(50, 17), "elevator").begins_with("ビルの幅は100マスまでです"), "右端より外には建てられない")
	check(main.get_build_problem(Vector2i(47, 17), "office").begins_with("ビルの幅は100マスまでです"), "横4マスのオフィスは、右端がはみ出すと建てられない")
	
	# 実際にクリックしても建たず、理由がメッセージで出る
	focus_camera(Vector2i(49, 17))
	await wait_frames(1)
	await choose_mode("elevator")
	await click_cell(Vector2i(50, 18), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(50, 18)), "上限の外はクリックしても建たない")
	check(main.last_message.begins_with("ビルの幅は100マスまでです"), "建てられない理由がメッセージで出る")
	check(not main.can_click_cell(Vector2i(50, 18)), "上限の外は赤く表示される")
	return true

# ---------------------------------------------------
# シナリオ42: 騒音（ノイズ）と、住宅・ホテルの評価への影響
#   2階（y=17）に 映画館(x=9〜16)・住宅(x=17〜19)・客室(x=20〜21) を建て、
#   離れた静かな場所（x=28〜31）にも住宅と客室を建てて比べる。
# ---------------------------------------------------
func run_noise_scenario() -> bool:
	print("[シナリオ] 騒音")
	main.funds = 10000000
	var noise = main.noise_system
	focus_camera(Vector2i(14, 17))
	await wait_frames(1)
	# 足場: 1階にロビーを足し、(9,18)は2階へ上がる階段にする
	build_support([Vector2i(8, 18)] + cells_row(18, 10, 32), "lobby")
	build_support([Vector2i(9, 18)])
	check(noise.get_noise(Vector2i(12, 17)) > 0, "ロビーの上の階にも、ロビーの騒音が少し届く")
	var lobby_noise: int = noise.get_noise(Vector2i(12, 17))
	
	# うるさい建物（映画館）を建てると、まわりのマスの騒音が増える
	main.select_mode("cinema")
	main.build_at(Vector2i(9, 17))
	check(noise.get_noise(Vector2i(12, 17)) > lobby_noise, "映画館のマスは騒音が大きい")
	check(noise.get_noise(Vector2i(17, 17)) > lobby_noise, "隣のマスにも騒音が広がる")
	check(noise.get_noise(Vector2i(28, 17)) == lobby_noise, "離れたマスには映画館の騒音は届かない")
	check(noise.NOISE_SOURCES["cinema"] > noise.NOISE_SOURCES["restaurant"], "映画館は飲食店よりうるさい")
	
	# 住宅: うるさい場所と静かな場所を建て比べる
	main.select_mode("housing")
	main.build_at(Vector2i(17, 17)) # 映画館の隣（うるさい）
	main.build_at(Vector2i(28, 17)) # 離れた場所（静か）
	var noisy := Vector2i(17, 17)
	var quiet := Vector2i(28, 17)
	check(noise.get_unit_noise(noisy) > noise.get_unit_noise(quiet), "飲食店の隣の住宅の方が騒音が大きい")
	check(noise.noise_stress(noisy) > noise.noise_stress(quiet), "騒音のぶん、評価に足されるストレスも大きい")
	await hover_cell(noisy + Vector2i(1, 0))
	check(main.hover_label.text.contains("騒音"), "カーソルを合わせると住宅の騒音が出る")
	await hover_cell(quiet + Vector2i(1, 0))
	check(main.hover_label.text.contains("静か"), "静かな住宅は「静か」と出る")
	await capture("noise_01_housing")
	
	# 同じストレスでも、うるさい住宅の方が評価が悪くなる
	var tenants = main.tenant_system
	var housing = main.housing_system
	for origin in [noisy, quiet]:
		housing.homes[origin].moved_in = true
		for m in housing.homes[origin].members:
			tenants.day_peak_stress[m.room] = 25.0 # 「良い」の範囲（30未満）のストレス
	tenants.evaluate_day(1)
	print("    noisy=", tenants.homes[noisy].average, " quiet=", tenants.homes[quiet].average)
	check(tenants.homes[quiet].rating == tenants.Rating.GOOD, "静かな住宅の評価は「良い」")
	check(tenants.homes[noisy].rating != tenants.Rating.GOOD, "同じストレスでも、うるさい住宅は評価が下がる")
	check(tenants.homes[noisy].average > tenants.homes[quiet].average, "評価に使う値に騒音のぶんが足されている")
	
	# ホテルの客室も、うるさいと評価が悪くなる
	main.select_mode("hotel")
	main.build_at(Vector2i(20, 17)) # 映画館から少し離れた部屋（まだうるさい）
	main.build_at(Vector2i(31, 17)) # 静かな部屋
	tenants.rate_hotel_stay(Vector2i(20, 17), 20.0)
	tenants.rate_hotel_stay(Vector2i(31, 17), 20.0)
	check(tenants.rooms[Vector2i(20, 17)].average > tenants.rooms[Vector2i(31, 17)].average, "うるさい客室は、同じストレスでも評価の値が悪くなる")
	check(tenants.hotel_checkin_chance(Vector2i(31, 17)) >= tenants.hotel_checkin_chance(Vector2i(20, 17)), "静かな部屋の方が客が来やすい")
	return true

# ---------------------------------------------------
# シナリオ43: メディカルセンターのストレス緩和
#   メディカルセンターがあると、立ち止まっている人のストレスの回復が速くなる。
# ---------------------------------------------------
func run_medical_scenario() -> bool:
	print("[シナリオ] メディカルセンターのストレス緩和")
	main.funds = 10000000
	focus_camera(Vector2i(10, 17))
	await wait_frames(1)
	build_support(cells_row(18, 8, 19), "lobby") # 足場: 2階に建てるため、1階にロビーを足す
	var resident = main.spawn_resident(Vector2i(0, 17))
	resident.stress = 90.0
	check(is_equal_approx(main.stress_recover_rate(), 1.0), "メディカルセンターがないと、回復の速さは標準（1.0倍）")
	resident.update_stress(1.0)
	var base_recover: float = 90.0 - resident.stress
	check(is_equal_approx(base_recover, resident.STRESS_RECOVER_RATE), "1秒で標準の量だけ回復する")
	
	# 1施設で1.5倍
	await choose_mode("medical")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 17)) == "medical", "2階にメディカルセンターを建てられる")
	check(is_equal_approx(main.stress_recover_rate(), 1.5), "1施設で回復が1.5倍になる")
	resident.stress = 90.0
	resident.update_stress(1.0)
	check(is_equal_approx(90.0 - resident.stress, base_recover * 1.5), "同じ1秒でも、1.5倍の量だけ回復する")
	await hover_cell(Vector2i(10, 17))
	check(main.hover_label.text.contains("ストレスの回復 1.5倍"), "カーソルを合わせると回復の速さが出る")
	await capture("medical_01")
	
	# 増やすほど速くなるが、上限がある
	await click_cell(Vector2i(12, 17), MOUSE_BUTTON_LEFT)
	await click_cell(Vector2i(15, 17), MOUSE_BUTTON_LEFT)
	check(is_equal_approx(main.stress_recover_rate(), 2.5), "3施設で2.5倍になる")
	await click_cell(Vector2i(18, 17), MOUSE_BUTTON_LEFT)
	check(is_equal_approx(main.stress_recover_rate(), main.MEDICAL_RECOVER_MAX), "それ以上増やしても2.5倍で頭打ち")
	
	# 待っている間は回復しない（メディカルセンターがあっても）
	resident.stress = 50.0
	resident.state = resident.State.WAITING
	resident.update_stress(1.0)
	check(resident.stress > 50.0, "エレベーターを待っている間はストレスがたまる（回復はしない）")
	return true

# ---------------------------------------------------
# シナリオ44: 衛生の悪化（ゴミ処理が追いつかないとテナントの評価が下がる）
#   ゴミ処理場がないままオフィスを動かすと、ゴミがあふれて衛生が悪化する。
# ---------------------------------------------------
func run_pollution_scenario() -> bool:
	print("[シナリオ] 衛生の悪化")
	main.funds = 10000000
	var economy = main.economy_system
	var tenants = main.tenant_system
	focus_camera(Vector2i(0, 16))
	await wait_frames(1)
	await choose_mode("elevator")
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	check(economy.pollution == 0 and economy.recycling_capacity() == 0, "最初は衛生の悪化がなく、ゴミの処理能力も0")
	
	# 1日目: ゴミ処理場がないので、出勤したオフィスのぶんのゴミがあふれる
	await run_day(1)
	var report: Dictionary = economy.last_report
	print("    garbage=", report.garbage, " pollution=", economy.pollution)
	check(report.garbage > 0 and report.garbage_cost > 0, "処理しきれないゴミは外部委託になる")
	check(economy.pollution == mini(report.garbage / economy.GARBAGE_PER_POLLUTION, economy.POLLUTION_MAX), "あふれたゴミ5につき、衛生の悪化が1レベル進む")
	check(economy.pollution == economy.POLLUTION_MAX, "ゴミが多いと、悪化はすぐ上限（レベル5）になる")
	check(main.last_message.contains("衛生の悪化 レベル5"), "決算のメッセージに衛生の悪化が出る")
	await wait_frames(2) # 上部バーの表示は次のフレームで更新される
	check(main.stats_label.text.contains("衛生の悪化 レベル5"), "ビルの状況にも衛生の悪化が出る")
	check(is_equal_approx(economy.pollution_stress(), 5 * economy.POLLUTION_STRESS), "悪化のレベル1につきストレス5ぶん、評価が悪くなる")
	await capture("pollution_01")
	
	# 同じストレスでも、ビルが汚れていると評価が悪くなる
	var origin := Vector2i(0, 17)
	tenants.offices[origin] = tenants.new_tenant()
	for cell in main.get_unit_cells(origin):
		tenants.day_peak_stress[cell] = 10.0 # 本来なら「良い」のストレス
	for cell in main.get_unit_cells(origin):
		main.commute_system.workers[cell].arrived_day = 2
	tenants.evaluate_day(2)
	check(tenants.offices[origin].average > 10.0, "評価に使う値に、衛生の悪化のぶんが足されている")
	check(tenants.offices[origin].rating != tenants.Rating.GOOD, "汚れたビルでは、ストレスが低くても評価が「良い」にならない")
	
	# ゴミ処理場を建てて処理が足りるようにすると、1日ごとに悪化が1レベル戻る
	main.funds = 10000000
	build_support(cells_row(18, 9, 20), "lobby")
	main.select_mode("recycling")
	for x in [9, 12, 15, 18]:
		main.build_at(Vector2i(x, 17))
	check(economy.recycling_capacity() == 4 * economy.RECYCLING_CAPACITY, "ゴミ処理場4施設で処理能力80/日")
	var before: int = economy.pollution
	await run_day(2)
	check(economy.last_report.garbage <= economy.recycling_capacity(), "処理能力がゴミの量を上回る")
	check(economy.pollution == before - 1, "ゴミが足りている日は、悪化が1レベル戻る")
	await run_day(3)
	check(economy.pollution == before - 2, "次の日もまた1レベル戻る")

	# 汚れたビルは、レベルに応じて茶色くくすんで見える
	economy.pollution = 4
	focus_camera(Vector2i(0, 16))
	await wait_frames(2)
	await capture("pollution_02_grimy")

	# 掃除が追いつかない客室（ハウスキーパー室がない）も、衛生を悪くする
	economy.pollution = 0
	main.select_mode("hotel")
	build_support(cells_row(16, 9, 12), "frame")
	main.build_at(Vector2i(9, 15))
	main.build_at(Vector2i(11, 15))
	var hotel = main.hotel_system
	for room in [Vector2i(9, 15), Vector2i(11, 15)]:
		hotel.rooms[room].state = hotel.RoomState.DIRTY # チェックアウトしたまま、掃除されていない
	await run_day(4)
	check(economy.last_report.unclean == 2, "決算のときに掃除されていない客室を数える（2室）")
	check(economy.pollution == 1, "掃除されていない客室が2室あると、ゴミが足りていても衛生が1レベル悪化する")
	check(logged("掃除の済んでいない客室 2室（ハウスキーパー室が足りません）"), "決算のメッセージに原因が出る")
	return true

# ---------------------------------------------------
# シナリオ45: テナントの激怒（ストレスが限界を超えると赤く点滅）
#   人はストレス95以上で「激怒」して顔が点滅し、退去が近いテナントはマークが点滅する。
# ---------------------------------------------------
func run_angry_scenario() -> bool:
	print("[シナリオ] テナントの激怒")
	var tenants = main.tenant_system
	focus_camera(Vector2i(0, 16))
	await wait_frames(1)
	var resident = main.spawn_resident(Vector2i(0, 17))
	resident.stress = 50.0
	check(not resident.is_angry() and resident.get_face_color() == resident.PINK_COLOR, "ストレス50では激怒しない（顔はピンク）")
	resident.stress = 80.0
	check(not resident.is_angry() and resident.get_face_color() == resident.RED_COLOR, "ストレス80でも顔は赤いだけ")
	resident.stress = resident.MAX_STRESS
	check(resident.is_angry(), "ストレスが95以上になると激怒する")
	
	# 激怒した人の顔は、赤と明るい色で点滅する
	var seen := {}
	var limit := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < limit and seen.size() < 2:
		seen[resident.get_face_color()] = true
		await wait_frames(1)
	check(seen.has(resident.RED_COLOR) and seen.has(resident.ANGRY_COLOR), "激怒した人の顔は赤と明るい色で点滅する")
	await wait_frames(2)
	check(main.stats_label.text.contains("怒っている人 1人"), "ビルの状況に怒っている人の数が出る")
	await capture("angry_01_resident")
	
	# 退去が近いテナントは、評価のマークが点滅する
	var origin := Vector2i(0, 17)
	tenants.offices[origin] = tenants.new_tenant()
	tenants.offices[origin].rating = tenants.Rating.BAD
	check(not tenants.is_about_to_leave(origin), "評価が悪くなった初日は、まだ点滅しない")
	tenants.offices[origin].bad_days = tenants.LEAVE_AFTER_BAD_DAYS - 1
	check(tenants.is_about_to_leave(origin), "あと1日で退去のテナントは点滅して知らせる")
	check(tenants.count_about_to_leave() == 1, "退去しそうなテナントの数を数えられる")
	await wait_frames(2)
	check(main.stats_label.text.contains("退去しそうなテナント 1件"), "ビルの状況に退去しそうなテナントの数が出る")
	
	# 点滅は、表示する周期と消す周期が交互に来る
	var blinks := {}
	limit = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < limit and blinks.size() < 2:
		blinks[tenants.blink_on()] = true
		await wait_frames(1)
	check(blinks.size() == 2, "マークは点いたり消えたりする")
	await capture("angry_02_tenant")
	
	# 退去して空室になると、点滅は止まる
	tenants.offices[origin].vacant = true
	check(not tenants.is_about_to_leave(origin) and tenants.count_about_to_leave() == 0, "退去して空室になると点滅しない")
	return true

# ---------------------------------------------------
# シナリオ46: VIPの宿泊（★4への昇格イベント）
#   人口250と地下鉄駅をそろえると、17時にVIPが来館する。
#   きれいな空きスイートまでストレス30以下で着けば合格で、★4に昇格できる。
# ---------------------------------------------------
func run_vip_scenario() -> bool:
	print("[シナリオ] VIPの宿泊")
	main.funds = 100000000
	var vips = main.vip_system
	var rating = main.rating_system
	# 人口250のために、5階から18階まで x=-8〜7 にオフィスを積む（1階あたり16人）
	main.select_mode("office")
	for y in range(14, 0, -1):
		for x in [-8, -4, 0, 4]:
			main.build_at(Vector2i(x, y))
	main.select_mode("elevator")
	for y in range(18, 0, -1):
		main.build_at(Vector2i(8, y))
	# スイートは、入口から階段1つで行ける2階に置く（エレベーター待ちがない＝VIPのストレスがたまらない）
	build_support([Vector2i(9, 18)] + cells_row(18, 11, 16), "lobby") # 足場: 1階のロビー
	build_support([Vector2i(10, 18)]) # 足場: 2階へ上がる階段
	main.select_mode("hotel_suite")
	main.build_at(Vector2i(10, 17))
	# 地下鉄駅は地下5階より深くにしか建てられないので、足場で掘り下げてから建てる
	for y in range(19, 23):
		build_support(cells_row(y, 11, 14))
	main.select_mode("subway")
	main.build_at(Vector2i(11, 23))
	rating.stars = 3
	await wait_frames(2)
	check(rating.population() >= 250, "人口が250以上ある（%d人）" % rating.population())
	check(rating.waiting_for_vip(), "★4に足りないのはVIPの宿泊だけ")
	check(rating.waiting_for_vip() and not vips.passed, "VIPの来館を待っている状態")
	check(not rating.evaluate(), "VIPが来るまでは★4に昇格できない")
	
	# 9時: 来館の予告が届く
	focus_camera(Vector2i(6, 17))
	main.clock.set_time(1, 8, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return vips.state == vips.State.ANNOUNCED, 20.0)
	check(vips.state == vips.State.ANNOUNCED and logged("本日16時にVIPが来館します"), "朝のうちに、来館の予告が届く")
	check(not vips.is_visiting(), "予告の時点では、まだ来ていない")

	# 16時: VIPが来館して、スイートへ向かう
	main.clock.set_time(1, 15, 59)
	await wait_until(func(): return vips.is_visiting(), 30.0)
	check(vips.is_visiting(), "16時にVIPが来館する")
	check(logged("VIPが来館しました"), "来館がメッセージで知らされる")
	check(vips.vip.base_color == vips.VIP_COLOR, "VIPは金色の服")
	await wait_frames(2)
	check(main.stats_label.text.contains("VIPが来館中"), "ビルの状況にVIPの来館が出る")
	await capture("vip_01_arrived")

	# スイートに着くとチェックインして一泊する（まだ合否は決まらない）
	await wait_until(func(): return vips.state == vips.State.STAYING or not vips.is_visiting(), 40.0)
	var hotel = main.hotel_system
	check(vips.state == vips.State.STAYING and hotel.rooms[Vector2i(10, 17)].state == hotel.RoomState.OCCUPIED, "VIPはスイートにチェックインする")
	check(not vips.passed, "チェックインした時点では、まだ合否は決まらない")
	await wait_frames(2)
	check(main.stats_label.text.contains("VIPが宿泊中"), "ビルの状況にVIPの宿泊が出る")

	# 翌朝のチェックアウトで合否が決まる
	main.clock.set_time(2, 6, 59)
	await wait_until(func(): return vips.state == vips.State.NONE, 40.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(vips.passed, "待たせずに泊まってもらえたので、チェックアウトのときに合格")
	check(logged("大満足です"), "合格がメッセージで知らされる")
	check(rating.missing_for_next().is_empty(), "★4の条件がそろう")
	check(rating.evaluate() and rating.stars == 4, "次の決算で★4に昇格する")
	await capture("vip_02_passed")

	# 待たせてしまったときは、チェックアウトのときに不合格になる
	vips.passed = false
	vips.visit_day = 0
	rating.stars = 3
	await wait_frames(2)
	hotel.rooms[Vector2i(10, 17)].state = hotel.RoomState.CLEAN
	hotel.rooms[Vector2i(10, 17)].guests = []
	main.clock.set_time(3, 15, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return vips.is_visiting(), 30.0)
	vips.vip.stress = 80.0 # エレベーターで待たされた想定
	await wait_until(func(): return vips.state == vips.State.STAYING or not vips.is_visiting(), 40.0)
	check(vips.state == vips.State.STAYING, "ストレスが高くても、その日は泊まっていく")
	main.clock.set_time(4, 6, 59)
	await wait_until(func(): return vips.state == vips.State.NONE, 40.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(not vips.passed, "ストレスが高かったので、チェックアウトのときに不合格")
	check(logged("待たされて不満でした"), "不合格の理由がメッセージで出る")
	check(rating.waiting_for_vip(), "★4にはまたVIPの宿泊が必要")
	return true

# ---------------------------------------------------
# シナリオ47: 爆破予告（テロ）と警備員による解体
#   2階（y=17）に警備室(x=9〜10)と飲食店(x=12〜14)を建て、飲食店に爆弾を仕掛ける。
# ---------------------------------------------------
func run_bomb_scenario() -> bool:
	print("[シナリオ] 爆破予告")
	main.funds = 10000000
	var incidents = main.incident_system
	focus_camera(Vector2i(11, 17))
	await wait_frames(1)
	# 足場: 1階にロビーを足し、(9,18)は2階へ上がる階段にする
	build_support([Vector2i(8, 18)] + cells_row(18, 10, 15), "lobby")
	build_support([Vector2i(9, 18)])
	check(incidents.guard_count() == 0, "警備室がないうちは警備員もいない")
	main.select_mode("security")
	main.build_at(Vector2i(9, 17))
	await wait_frames(2)
	check(incidents.guard_count() == 1, "警備室1つにつき警備員が1人常駐する")
	var guard = incidents.guards[Vector2i(9, 17)].resident
	check(guard.base_color == incidents.GUARD_COLOR and guard.staff, "警備員は青い服の裏方（サービスエレベーターに乗れる）")
	main.select_mode("restaurant")
	main.build_at(Vector2i(11, 17)) # 警備室(x=9〜10)の隣（x=11〜13）
	
	# 爆破予告 → 身代金を要求される
	main.clock.set_time(1, 10, 0)
	main.clock.set_process(true)
	main.funds = 10000000
	incidents.start_bomb(Vector2i(11, 17))
	check(incidents.has_bomb(), "爆破予告が出ている")
	check(logged("爆破予告！") and logged("ビルのどこかに爆弾") and logged("身代金"), "予告と身代金の要求がメッセージで知らされる")
	check(not logged("飲食店に爆弾") and not main.ui.ransom_text.text.contains("飲食店"), "爆弾の場所は知らされない")
	check(incidents.bomb.ransom == 2000000, "身代金は資金の2割（1,000万Crなら200万Cr）")
	check(main.ui.ransom_panel.visible, "払うか払わないかを選ぶ画面が出る")
	check(main.ui.ransom_pay_button.text.contains("2,000,000Cr") and not main.ui.ransom_pay_button.disabled, "「支払う」ボタンに身代金の額が出る")
	await capture("bomb_00_ransom")
	await wait_frames(30)
	check(incidents.bomb.left == incidents.BOMB_LIMIT and incidents.bomb.guard == null, "決めるまでは、爆発までの時間は進まず、警備員も動かない")

	# 支払わない → 警備員が現場へ向かい、解体する
	main.ui.ransom_refuse_button.pressed.emit()
	check(not main.ui.ransom_panel.visible, "選ぶと画面が閉じる")
	check(logged("支払いを断りました") and logged("捜索を始めます"), "断ったことと、捜索を始めることがメッセージで出る")
	await wait_frames(2)
	check(incidents.bomb.search.has(Vector2i(9, 17)) and not incidents.bomb.found, "警備員が捜索に出る（まだ場所は分からない）")
	await wait_frames(2)
	check(main.stats_label.text.contains("爆破予告！"), "ビルの状況に爆破予告と残り時間が出る")
	await capture("bomb_01_alert")
	set_speed(16.0)
	await wait_until(func(): return not incidents.has_bomb(), 60.0)
	Engine.time_scale = 1.0
	check(logged("爆弾を見つけました"), "警備員が爆弾を見つける")
	check(main.get_building_type(Vector2i(11, 17)) == "restaurant", "解体が間に合い、飲食店は無事")
	check(logged("爆弾を解体しました"), "解体の成功がメッセージで出る")
	
	# 警備員がいないと、時間切れでテナントが吹き飛ぶ
	main.select_mode("security")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_RIGHT) # 警備室を撤去
	await wait_frames(2)
	check(incidents.guard_count() == 0, "警備室を撤去すると警備員もいなくなる")

	# 身代金を支払うと、爆弾は取り除かれる（確実に安全）
	var funds_before: int = main.funds
	incidents.start_bomb(Vector2i(11, 17))
	var ransom: int = incidents.bomb.ransom
	main.ui.ransom_pay_button.pressed.emit()
	check(not incidents.has_bomb() and main.funds == funds_before - ransom, "身代金を払うと爆弾が取り除かれ、資金が減る")
	check(main.get_building_type(Vector2i(11, 17)) == "restaurant", "払えば、テナントは確実に無事")
	check(logged("身代金") and logged("取り除かれました"), "支払ったことがメッセージで出る")

	# 資金が足りなければ払えない（払わずに解体するしかない）
	main.funds = 100000
	incidents.start_bomb(Vector2i(11, 17))
	check(incidents.bomb.ransom == incidents.RANSOM_MIN, "身代金には最低額がある")
	check(main.ui.ransom_pay_button.disabled and main.ui.ransom_pay_button.text.contains("資金が足りません"), "資金が足りないと「支払う」は押せない")
	check(not incidents.pay_ransom() and incidents.has_bomb(), "資金が足りないと支払えない")
	main.ui.ransom_refuse_button.pressed.emit()
	check(logged("爆弾を探せる警備員がいません"), "警備員がいないと、その旨がメッセージで出る")
	set_speed(16.0)
	await wait_until(func(): return not incidents.has_bomb(), 60.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(main.get_building_type(Vector2i(11, 17)) == "ruin", "時間切れで飲食店が吹き飛び、焼け跡が残る")
	check(logged("爆発！"), "爆発がメッセージで知らされる")
	await capture("bomb_02_exploded")
	
	# 予告は★3以上で、資金が潤沢なビルにだけ届く（身代金をねらうので）
	check(incidents.BOMB_MIN_STARS == 3 and main.rating_system.stars == 1, "今は★1")
	main.funds = incidents.BOMB_MIN_FUNDS
	var bomb_days := func() -> int:
		var n := 0
		for day in range(1, 366): # 1日3%なので、1年ぶんで数える
			if incidents.roll_bomb(day):
				n += 1
		return n
	check(bomb_days.call() == 0, "★1のうちは爆破予告が来ない")
	main.rating_system.stars = 2
	check(bomb_days.call() == 0, "★2でも、まだ爆破予告は来ない")
	main.rating_system.stars = 3
	var days: int = bomb_days.call()
	print("    1年のうち爆破予告が来た日: ", days)
	check(days > 0 and days < 365 * incidents.BOMB_CHANCE * 3, "★3以上では、ときどき爆破予告が届く（1年のうち%d日）" % days)
	main.funds = incidents.BOMB_MIN_FUNDS - 1
	check(bomb_days.call() == 0, "★3でも、資金が%s未満のうちは来ない" % main.money_text(incidents.BOMB_MIN_FUNDS))
	incidents.last_incident_day = 10
	check(incidents.is_incident_on_cooldown(11) and incidents.is_incident_on_cooldown(13) and not incidents.is_incident_on_cooldown(14), "事故の後は3日間、新しい事故が起きない")
	return true

# ---------------------------------------------------
# シナリオ48: 火災の発生・延焼・消火
#   2階（y=17）に警備室(x=9〜10)・飲食店(x=11〜13)・ショップ(x=14〜16)を建てて燃やす。
# ---------------------------------------------------
func run_fire_scenario() -> bool:
	print("[シナリオ] 火災")
	main.funds = 10000000
	var incidents = main.incident_system
	focus_camera(Vector2i(12, 17))
	await wait_frames(1)
	# 足場: 1階にロビーを足し、(9,18)は2階へ上がる階段にする
	build_support([Vector2i(8, 18)] + cells_row(18, 10, 17), "lobby")
	build_support([Vector2i(9, 18)])
	main.select_mode("security")
	main.build_at(Vector2i(9, 17))
	main.select_mode("restaurant")
	main.build_at(Vector2i(11, 17))
	main.select_mode("shop")
	main.build_at(Vector2i(14, 17))
	await wait_frames(2)
	check(incidents.guard_count() == 1, "警備員が1人いる")
	
	# 出火 → 警備員が消火に向かう
	main.clock.set_time(1, 20, 0)
	main.clock.set_process(true)
	incidents.start_fire(Vector2i(12, 17))
	check(incidents.has_fire() and incidents.fire.has(Vector2i(12, 17)), "そのマスが燃えはじめる")
	check(logged("火事だ！"), "出火がメッセージで知らされる")
	await wait_frames(2)
	check(main.stats_label.text.contains("火災！"), "ビルの状況に火災と燃えているマスの数が出る")
	await capture("fire_01_burning")
	set_speed(16.0)
	await wait_until(func(): return not incidents.has_fire(), 60.0)
	Engine.time_scale = 1.0
	check(logged("火を消し止めました"), "警備員が消し止める")
	check(main.get_building_type(Vector2i(12, 17)) == "restaurant", "消火が間に合い、飲食店は残る")
	
	# 警備員がいないと、燃え広がって焼け落ちる
	main.select_mode("security")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_RIGHT)
	await wait_frames(2)
	check(incidents.guard_count() == 0, "警備室を撤去すると警備員もいなくなる")
	incidents.start_fire(Vector2i(12, 17))
	incidents.spread_fire(true) # 燃え移りは確率なので、ここでは必ず1回燃え移らせる（確率は「事件の的」のシナリオで確かめる）
	set_speed(16.0)
	await wait_until(func(): return incidents.fire.size() > 1, 30.0)
	check(incidents.fire.size() > 1, "隣のマスへ燃え広がる")
	await capture("fire_02_spreading")
	await wait_until(func(): return main.get_building_type(Vector2i(12, 17)) == "ruin", 60.0)
	check(main.get_building_type(Vector2i(12, 17)) == "ruin", "燃え続けたテナントは焼け落ちて、焼け跡が残る")
	check(logged("焼け落ちました"), "焼失がメッセージで知らされる")
	await wait_until(func(): return not incidents.has_fire(), 90.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	
	# 出火は★2以上のビルだけ
	check(incidents.MIN_STARS == 2 and main.rating_system.stars == 1, "今は★1")
	check(not incidents.roll_fire(1) and not incidents.roll_fire(5), "★1のうちは出火しない")
	main.rating_system.stars = 2
	var days := 0
	for day in range(1, 366): # 1日2%なので、1年ぶんで数える
		if incidents.roll_fire(day):
			days += 1
	print("    1年のうち出火した日: ", days)
	check(days > 0 and days < 365 * incidents.fire_chance() * 3, "★2以上では、ときどき出火する（1年のうち%d日）" % days)
	# 大きなビルほど火が出やすい（テナントが多いほど出火の確率が上がる。上限あり）
	var small_chance: float = incidents.fire_chance()
	main.funds = 100000000
	main.select_mode("office")
	for y in range(14, 4, -1):
		for x in [-8, -4, 0, 4]:
			main.build_at(Vector2i(x, y))
	check(incidents.fire_chance() > small_chance, "テナントが増えると、出火しやすくなる（%.1f%% → %.1f%%）" % [small_chance * 100, incidents.fire_chance() * 100])
	check(incidents.fire_chance() <= incidents.FIRE_CHANCE_MAX, "出火の確率には上限がある（%d%%）" % int(incidents.FIRE_CHANCE_MAX * 100))
	return true

# ---------------------------------------------------
# シナリオ49: ゴキブリの大繁殖（衛生の悪化が続くと発生）
# ---------------------------------------------------
func run_roach_scenario() -> bool:
	print("[シナリオ] ゴキブリの大繁殖")
	var incidents = main.incident_system
	var economy = main.economy_system
	var tenants = main.tenant_system
	focus_camera(Vector2i(0, 16))
	await wait_frames(1)
	check(not incidents.has_roaches(), "最初はゴキブリがいない")
	
	# 衛生の悪化が続くと発生する
	economy.pollution = incidents.ROACH_POLLUTION
	incidents.update_roaches(1)
	check(not incidents.has_roaches(), "悪化1日目では、まだ出ない")
	incidents.update_roaches(2)
	check(incidents.has_roaches(), "悪化が2日続くとゴキブリが大繁殖する")
	check(incidents.roaches.size() == incidents.ROACH_SPAWN, "1日にちょうど%d棟に広がる（同じ棟を2度選ばない）" % incidents.ROACH_SPAWN)
	check(logged("ゴキブリが大繁殖しました"), "発生がメッセージで知らされる")
	await wait_frames(2)
	check(main.stats_label.text.contains("ゴキブリ"), "ビルの状況にゴキブリのいる棟数が出る")
	var infested: Vector2i = incidents.roaches.keys()[0]
	await hover_cell(infested)
	check(main.hover_label.text.contains("ゴキブリ発生中"), "カーソルを合わせるとゴキブリがいると出る")
	await capture("roach_01")
	
	# 日がたつと、さらに広がる
	var before: int = incidents.roaches.size()
	incidents.update_roaches(3)
	check(incidents.roaches.size() == before + incidents.ROACH_SPAWN, "悪化が続くと、さらに%d棟に広がる" % incidents.ROACH_SPAWN)
	
	# ゴキブリがいるテナントは評価が下がる
	check(is_equal_approx(incidents.roach_stress(infested), incidents.ROACH_STRESS), "ゴキブリのいるテナントはストレス15ぶんの上乗せ")
	tenants.offices[infested] = tenants.new_tenant()
	for cell in main.get_unit_cells(infested):
		tenants.day_peak_stress[cell] = 5.0
		main.commute_system.workers[cell].arrived_day = 4
	economy.pollution = 0 # 衛生の悪化ぶんを外して、ゴキブリの影響だけを見る
	tenants.evaluate_day(4)
	check(tenants.offices[infested].average >= incidents.ROACH_STRESS, "評価に使う値に、ゴキブリのぶんが足されている")
	
	# ゴミの処理が追いつくと、いなくなる
	incidents.update_roaches(5)
	check(not incidents.has_roaches(), "衛生の悪化が0に戻ると、ゴキブリはいなくなる")
	check(logged("ゴキブリはいなくなりました"), "いなくなったことがメッセージで出る")
	return true

# ---------------------------------------------------
# シナリオ50: 埋蔵金の発見（地下を掘ると、ときどき見つかる）
# ---------------------------------------------------
func run_treasure_scenario() -> bool:
	print("[シナリオ] 埋蔵金の発見")
	main.funds = 100000000
	var incidents = main.incident_system
	check(incidents.treasure_total == 0, "最初は埋蔵金を見つけていない")
	check(incidents.treasure_chance(1) < incidents.treasure_chance(10), "深いほど見つかりやすい")
	check(is_equal_approx(incidents.treasure_chance(100), incidents.TREASURE_CHANCE_MAX), "確率には上限がある")
	
	# 地下を掘っていくと、いくつかのマスで見つかる
	var found := 0
	var dug := 0
	for y in range(19, 41):
		for x in range(-20, 20):
			incidents.dig(Vector2i(x, y))
			dug += 1
			if incidents.treasure_total > 0 and found == 0:
				found = incidents.treasure_total
	print("    掘ったマス=", dug, " 合計=", incidents.treasure_total)
	check(incidents.treasure_total > 0, "地下を掘ると埋蔵金が見つかる（合計 %sCr）" % main.format_money(incidents.treasure_total))
	check(logged("埋蔵金を発見！"), "発見がメッセージで知らされる")
	check(main.funds > 100000000, "見つけた埋蔵金は資金に入る")
	var chests: Array = main.effects.effects.filter(func(e): return e.type == "treasure")
	check(not chests.is_empty(), "掘り当てたマスから、宝箱と金塊が飛び出す")
	check(chests[0].text.begins_with("+") and chests[0].text.ends_with("Cr"), "宝箱の上に、見つけた金額が出る")
	
	# 同じマスからは二度は出ない
	var total_before: int = incidents.treasure_total
	for y in range(19, 41):
		for x in range(-20, 20):
			incidents.dig(Vector2i(x, y))
	check(incidents.treasure_total == total_before, "一度掘ったマスからは、もう見つからない")
	
	# 実際に地下へ建てると、そのマスを掘ったことになる
	focus_camera(Vector2i(0, 19))
	await wait_frames(1)
	var funds_before: int = main.funds
	await choose_mode("office")
	await click_cell(Vector2i(0, 19), MOUSE_BUTTON_LEFT) # ロビーの真下（B1階。x=0〜3）
	check(main.get_building_type(Vector2i(0, 19)) == "office", "地下にオフィスを建てられる")
	check(incidents.dug.has(Vector2i(0, 19)) and incidents.dug.has(Vector2i(3, 19)), "建てたマスは掘ったことになる")
	check(main.funds == funds_before - 400000 + (incidents.treasure_total - total_before), "建設費と、見つかった埋蔵金が資金に反映される")
	# 見えるところで掘り当てて、宝箱の絵を確かめる
	main.effects.clear()
	incidents.dug.erase(Vector2i(0, 19))
	var lucky := Vector2i(0, 19)
	for y in range(19, 60): # 掘り当てるマスを探す（まだ掘っていないマス）
		for x in range(-20, 20):
			var cell := Vector2i(x, y)
			if not incidents.dug.has(cell):
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([cell, "treasure"])
				if rng.randf() < incidents.treasure_chance(cell.y - main.ground_y):
					lucky = cell
					break
		if lucky != Vector2i(0, 19):
			break
	incidents.dig(lucky)
	focus_camera(lucky)
	await wait_frames(8)
	await capture("treasure_01")
	return true

# ---------------------------------------------------
# シナリオ51: カレンダー（月・日）とサンタクロースの飛来
#   1日目は4月1日（月）。12月24日・25日の夜には、サンタクロースが空を横切る。
# ---------------------------------------------------
func run_calendar_scenario() -> bool:
	print("[シナリオ] カレンダーとサンタクロース")
	var clock = main.clock
	check(clock.date(1) == [4, 1], "1日目は4月1日")
	check(clock.date(30) == [4, 30] and clock.date(31) == [5, 1], "月が変わると日付も変わる（4月30日の次は5月1日）")
	check(clock.date_text(245) == "12月1日", "245日目は12月1日")
	check(clock.date(366) == [4, 1], "1年（365日）たつと、また4月1日に戻る")
	check(clock.date_text(335) == "3月1日", "2月は28日まで（335日目は3月1日）")
	
	# サンタクロースが飛ぶ日
	var santa_day := 268 # 12月24日
	check(clock.date(santa_day) == [12, 24] and clock.is_santa_day(santa_day), "12月24日はサンタクロースが飛ぶ日")
	check(clock.is_santa_day(santa_day + 1) and not clock.is_santa_day(santa_day + 2), "12月25日も飛ぶが、26日は飛ばない")
	check(not clock.is_santa_day(1), "4月1日は飛ばない")
	
	# 21時〜24時のあいだ、空を左から右へ横切る
	clock.set_time(santa_day, 20, 0)
	check(clock.santa_progress() < 0.0, "20時にはまだ飛んでいない")
	clock.set_time(santa_day, 21, 0)
	check(is_equal_approx(clock.santa_progress(), 0.0), "21時に空の左端から飛び始める")
	clock.set_time(santa_day, 22, 30)
	check(is_equal_approx(clock.santa_progress(), 0.5), "22時半には空の真ん中")
	clock.set_time(santa_day, 23, 59)
	check(clock.santa_progress() > 0.9, "24時ちかくに右端へ抜ける")
	
	# 飛んでいるところを撮る
	clock.set_time(santa_day, 22, 30)
	await wait_frames(3)
	check(main.clock_label.text.begins_with("12月24日"), "上部バーに12月24日と出る")
	await capture("calendar_01_santa")
	clock.set_time(1, 7, 30)
	return true

# ---------------------------------------------------
# シナリオ52: 天気（晴れ・くもり・雨）
#   天気は日ごとに決まり、雨の日は店へ来る外からのお客さんが半分になる。
# ---------------------------------------------------
func run_weather_scenario() -> bool:
	print("[シナリオ] 天気")
	var weather = main.weather_system
	var clock = main.clock
	# 日ごとに天気が決まり、同じ日なら何度見ても同じ
	check(weather.weather_for(1) == weather.weather_for(1), "同じ日の天気は何度見ても同じ")
	var counts := {weather.Weather.SUNNY: 0, weather.Weather.CLOUDY: 0, weather.Weather.RAINY: 0}
	for day in range(1, 101):
		counts[weather.weather_for(day)] += 1
	print("    100日の天気: 晴れ=", counts[weather.Weather.SUNNY], " くもり=", counts[weather.Weather.CLOUDY], " 雨=", counts[weather.Weather.RAINY])
	check(counts[weather.Weather.SUNNY] > counts[weather.Weather.RAINY], "晴れの日が一番多い")
	check(counts[weather.Weather.RAINY] > 0 and counts[weather.Weather.CLOUDY] > 0, "くもりや雨の日もある")
	
	# 梅雨（6月）は雨が多い
	var june := 0
	var april := 0
	for day in range(1, 31):
		if weather.weather_for(day) == weather.Weather.RAINY:
			april += 1 # 4月
	for day in range(62, 92):
		if weather.weather_for(day) == weather.Weather.RAINY:
			june += 1 # 6月
	print("    4月の雨=", april, "日 / 6月の雨=", june, "日")
	check(june > april, "6月（梅雨）は雨の日が多い")
	
	# 雨の日を探して、見た目と客足を確かめる
	var rainy_day := 0
	for day in range(1, 60):
		if weather.weather_for(day) == weather.Weather.RAINY:
			rainy_day = day
			break
	var sunny_day := 0
	for day in range(1, 60):
		if weather.weather_for(day) == weather.Weather.SUNNY:
			sunny_day = day
			break
	clock.set_time(sunny_day, 12, 0)
	check(not weather.is_rainy() and is_equal_approx(weather.visitor_rate(), 1.0), "晴れの日はお客さんが減らない")
	check(weather.sky_tint() == Color.WHITE, "晴れの日は空の色をそのまま使う")
	clock.set_time(rainy_day, 12, 0)
	check(weather.is_rainy() and is_equal_approx(weather.visitor_rate(), weather.RAINY_VISITOR_RATE), "雨の日は店のお客さんが半分になる")
	check(weather.sky_tint().get_luminance() < 1.0, "雨の日は空が暗くなる")
	await wait_frames(2)
	check(main.clock_label.text.contains("雨"), "上部バーに天気が出る")
	focus_camera(Vector2i(0, 14))
	await wait_frames(2)
	await capture("weather_01_rain")
	
	# 実際に、雨の日は店に来る人数が減る
	main.funds = 10000000
	build_support([Vector2i(8, 18)] + cells_row(18, 10, 14), "lobby")
	build_support([Vector2i(9, 18)])
	main.select_mode("shop")
	main.build_at(Vector2i(9, 17))
	var visitors = main.visitor_system
	visitors.plan_day = 0
	clock.set_time(sunny_day, 11, 0)
	main.clock.set_process(true)
	await wait_frames(3)
	var sunny_plan: int = visitors.visits.size()
	visitors.plan_day = 0
	visitors.visits.clear()
	clock.set_time(rainy_day, 11, 0)
	await wait_frames(3)
	main.clock.set_process(false)
	print("    晴れの日の予定=", sunny_plan, "人 / 雨の日=", visitors.visits.size(), "人")
	check(sunny_plan > 0 and visitors.visits.size() < sunny_plan, "雨の日は、店に来る予定の人数が少ない")
	clock.set_time(1, 7, 30)
	return true

# ---------------------------------------------------
# シナリオ53: セーブ／ロード（ビルの状態を保存して、続きから遊ぶ）
# ---------------------------------------------------
func run_save_scenario() -> bool:
	print("[シナリオ] セーブとロード")
	var save_path := "user://test_save.json"
	main.funds = 5000000
	focus_camera(Vector2i(8, 16))
	await wait_frames(1)
	# ビルを少し作る（エレベーター・カゴ・待機階・稼働時間帯・客室・住宅）
	await choose_mode("elevator")
	for y in range(18, 13, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await choose_mode("add_car")
	await click_cell(Vector2i(8, 15), MOUSE_BUTTON_LEFT)
	await choose_mode("set_home")
	await click_cell(Vector2i(8, 16), MOUSE_BUTTON_LEFT)
	await choose_mode("service")
	await click_cell(Vector2i(8, 16), MOUSE_BUTTON_LEFT)
	build_support(cells_row(18, 9, 14), "lobby")
	main.select_mode("hotel")
	main.build_at(Vector2i(9, 17))
	main.select_mode("housing")
	main.build_at(Vector2i(12, 17))
	main.clock.set_time(7, 15, 30)
	main.rating_system.stars = 2
	main.economy_system.pollution = 3
	main.hotel_system.rooms[Vector2i(9, 17)].state = main.hotel_system.RoomState.DIRTY
	main.housing_system.homes[Vector2i(12, 17)].moved_in = true
	main.tenant_system.offices[Vector2i(0, 17)] = {"rating": main.tenant_system.Rating.BAD, "average": 70.0, "bad_days": 2, "vacant": false, "vacant_days": 0}
	# カゴを別々の階に動かしておく（読み込んだときに同じ階へ戻るか確かめる）
	var cars_before: Array = main.elevator_system.get_cars_at(Vector2i(8, 16))
	cars_before[0].place_at_floor(14)
	cars_before[1].place_at_floor(16)
	var funds_before: int = main.funds
	var buildings_before: int = main.building_grid.size()
	
	# セーブする
	check(main.save_system.save_game(save_path), "セーブできる")
	check(FileAccess.file_exists(save_path), "セーブデータのファイルができる")
	check(logged("セーブしました"), "セーブしたことがメッセージで出る")
	
	# ビルを壊してから読み込むと、元に戻る
	# セーブした後に起きた火災・爆破予告は、読み込んだビルに持ち込まない
	main.incident_system.fire[Vector2i(9, 17)] = {"burn_left": 30.0, "work_left": 0.0}
	main.incident_system.bomb = {"cell": Vector2i(12, 17), "left": 60.0, "defuse_left": 0.0, "guard": null,
		"ransom": 0, "decided": true, "found": false, "searched": {}, "search": {}}
	main.incident_system.fire_day = 7
	main.clear_world()
	main.funds = 0
	main.clock.set_time(1, 7, 30)
	main.rating_system.stars = 1
	main.economy_system.pollution = 0
	check(main.building_grid.is_empty(), "いったん更地にする")
	check(main.save_system.load_game(save_path), "セーブデータを読み込める")
	check(main.building_grid.size() == buildings_before, "建物が元どおりになる")
	check(main.funds == funds_before, "資金が戻る")
	check(main.clock.day == 7 and main.clock.minute_of_day() == 15 * 60 + 30, "日付と時刻が戻る")
	check(main.rating_system.stars == 2, "ビルの評価（★）が戻る")
	check(main.economy_system.pollution == 3, "衛生の悪化が戻る")
	check(main.get_building_type(Vector2i(9, 17)) == "hotel" and main.get_building_type(Vector2i(12, 17)) == "housing", "客室と住宅が元の場所に戻る")
	check(main.hotel_system.rooms[Vector2i(9, 17)].state == main.hotel_system.RoomState.DIRTY, "客室が清掃待ちのまま戻る")
	check(main.housing_system.homes[Vector2i(12, 17)].moved_in, "住宅の入居ずみの状態が戻る")
	check(main.tenant_system.offices[Vector2i(0, 17)].bad_days == 2, "テナントの評価（悪い日が続いた日数）も戻る")
	
	# エレベーターの設定も戻る
	var elevators = main.elevator_system
	check(elevators.get_cars_at(Vector2i(8, 16)).size() == 2, "カゴの台数が戻る")
	var floors: Array = elevators.get_cars_at(Vector2i(8, 16)).map(func(car): return car.current_floor())
	floors.sort()
	check(floors == [14, 16], "カゴがそれぞれ元の階に戻る（最下階に集まらない）")
	check(not main.incident_system.has_fire() and not main.incident_system.has_bomb(), "読み込んだ後に、前の火災・爆破予告は残らない")
	check(main.incident_system.fire_day == 0, "その日の出火の判定は、読み込んだ日にやり直す")
	check(elevators.get_home(Vector2i(8, 16)) == 16, "待機階が戻る")
	check(elevators.get_service(Vector2i(8, 16)).name == "6時〜24時", "稼働時間帯が戻る")
	await capture("save_01_loaded")
	
	# セーブデータがないときは、読み込んでも何も起きない
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	check(not main.save_system.load_game(save_path), "セーブデータがなければ読み込まない")
	check(logged("セーブデータがありません"), "その旨がメッセージで出る")
	return true

# ---------------------------------------------------
# シナリオ54: ヘリポートと消防ヘリ（火災を空から消す）
#   屋上（2階=y=17）にヘリポートを建て、3階の建物を燃やしてヘリに消させる。
# ---------------------------------------------------
func run_helipad_scenario() -> bool:
	print("[シナリオ] ヘリポートと消防ヘリ")
	main.funds = 10000000
	var incidents = main.incident_system
	focus_camera(Vector2i(11, 15))
	await wait_frames(1)
	build_support([Vector2i(8, 18)] + cells_row(18, 9, 16), "lobby")
	
	# ヘリポートは屋上（上に建物がないところ）にだけ建てられる
	await choose_mode("helipad")
	check(main.mode_select.text.begins_with("ヘリポート") and main.mode_select.text.ends_with("800,000Cr"), "ヘリポートは80万Cr")
	# 上に建物があるところには建てられない（テストのために、上の階へ直接建物を置いて確かめる）
	main.place_unit(Vector2i(9, 16), "shop")
	check(main.get_build_problem(Vector2i(9, 17), "helipad").contains("屋上（上に建物がないところ）にしか建てられません"), "上に建物があるところには建てられない")
	var funds_before_cleanup: int = main.funds
	main.demolish_at(Vector2i(9, 16)) # 確かめ終わったので片づける（撤去費用は戻しておく）
	main.funds = funds_before_cleanup
	await click_cell(Vector2i(9, 19), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(9, 19)), "地下にも建てられない")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(12, 17)) == "helipad", "屋上（2階）にヘリポートを建てられる")
	await choose_mode("office")
	await click_cell(Vector2i(9, 16), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(9, 16)), "ヘリポートの上には建てられない")
	check(main.last_message == "ヘリポートの上には建てられません", "その理由がメッセージで出る")
	
	# 高い階が燃えると、消防ヘリが飛んできて消す（警備員はいない）
	main.select_mode("shop")
	main.build_at(Vector2i(13, 17))
	main.build_at(Vector2i(13, 16)) # 3階（ヘリポートの隣の上）
	check(incidents.guard_count() == 0, "警備員はいない")
	main.clock.set_time(1, 20, 0)
	main.clock.set_process(true)
	incidents.start_fire(Vector2i(14, 16))
	check(not incidents.has_heli(), "火が出た直後は、まだヘリは飛んでいない")
	set_speed(8.0)
	await wait_until(func(): return incidents.has_heli(), 20.0)
	check(incidents.has_heli(), "ヘリポートがあると消防ヘリが飛んでくる")
	check(incidents.heli.target.y <= 16, "ヘリは高い階の火から消しに行く")
	await wait_until(func(): return incidents.heli.pos.distance_to(main.tile_map.map_to_local(incidents.heli.target)) < 20.0, 20.0)
	await capture("helipad_01_heli")
	await wait_until(func(): return not incidents.has_fire(), 60.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(logged("消防ヘリが"), "消防ヘリが火を消したことがメッセージで出る")
	check(main.get_building_type(Vector2i(13, 16)) == "shop", "焼け落ちる前に消し止められる")
	await wait_frames(2)
	check(not incidents.has_heli(), "火が消えるとヘリは帰る")
	check(incidents.HELI_MINUTES < incidents.EXTINGUISH_MINUTES, "ヘリは警備員より早く1マスを消せる")
	return true

# ---------------------------------------------------
# シナリオ55: 遊びやすさ（ドラッグで連続建設・撤去モード・収支のグラフ）
# ---------------------------------------------------
func run_usability_scenario() -> bool:
	print("[シナリオ] 遊びやすさ")
	main.funds = 10000000
	focus_camera(Vector2i(10, 16))
	await wait_frames(1)
	
	# ドラッグ: 押したままなぞると、続けて建つ
	await choose_mode("lobby")
	await drag_cells(Vector2i(8, 18), Vector2i(13, 18), MOUSE_BUTTON_LEFT)
	var built := 0
	for x in range(8, 14):
		if main.get_building_type(Vector2i(x, 18)) == "lobby":
			built += 1
	check(built == 6, "ドラッグでなぞったマスに続けてロビーが建つ（%d マス）" % built)
	check(main.funds == 10000000 - 6 * 15000, "建てたぶんだけ建設費がかかる")
	
	# 右ドラッグ: 続けて撤去できる
	await drag_cells(Vector2i(12, 18), Vector2i(13, 18), MOUSE_BUTTON_RIGHT)
	check(main.is_cell_empty(Vector2i(12, 18)) and main.is_cell_empty(Vector2i(13, 18)), "右ドラッグで続けて撤去できる")
	
	# 撤去モード: 左クリックで撤去できる
	await choose_mode("demolish")
	check(main.mode_select.text.begins_with("撤去") and main.mode_select.text.ends_with("2,000Cr〜"), "建設メニューに「撤去」があり、撤去費用（最低2,000Cr〜）が出る")
	check(main.can_click_cell(Vector2i(11, 18)) and not main.can_click_cell(Vector2i(13, 18)), "建物のあるマスだけ操作できる（緑）")
	await click_cell(Vector2i(11, 18), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(11, 18)), "撤去モードでは左クリックで撤去できる")
	check(main.last_message.contains("撤去しました"), "撤去したことがメッセージで出る")
	await drag_cells(Vector2i(10, 18), Vector2i(9, 18), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(10, 18)) and main.is_cell_empty(Vector2i(9, 18)), "撤去モードでもドラッグで続けて撤去できる")
	
	# 収支のグラフ（⌘G）
	check(not main.chart_panel.visible, "グラフは最初は閉じている")
	await press_shortcut(KEY_G)
	check(main.chart_panel.visible, "⌘Gで収支のグラフが開く")
	check(main.economy_system.history.is_empty(), "まだ決算がないので記録も空")
	await capture("usability_01_chart_empty")
	await run_day(1)
	await run_day(2)
	await run_day(3)
	check(main.economy_system.history.size() == 3, "決算のたびに記録が増える")
	check(main.economy_system.history[2].day == 3, "新しい決算が後ろに入る")
	await wait_frames(2)
	await capture("usability_02_chart")
	await press_shortcut(KEY_G)
	check(not main.chart_panel.visible, "もう一度⌘Gを押すと閉じる")
	return true

# ---------------------------------------------------
# シナリオ56: 音（効果音とBGM）
#   音源ファイルは持たず、波形からゲームの中で作っている。
# ---------------------------------------------------
func run_audio_scenario() -> bool:
	print("[シナリオ] 音")
	var audio = main.audio_system
	check(audio.sounds.size() == audio.SOUNDS.size(), "効果音が%d種類そろっている" % audio.SOUNDS.size())
	for name in audio.SOUNDS:
		check(audio.sounds[name].data.size() > 0, "「%s」の音の波形ができている" % name)
	check(audio.bgm_player.stream != null and audio.bgm_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "BGMはくり返し鳴るようになっている")
	check(not audio.muted and audio.bgm_player.playing, "はじめは音が鳴っている")
	
	# 効果音は、続けて鳴らしすぎない
	audio.last_played.clear()
	audio.play("build")
	var playing := 0
	for player in audio.players:
		if player.playing:
			playing += 1
	check(playing >= 1, "建設の音が鳴る")
	var first_time: float = audio.last_played["build"]
	audio.play("build")
	check(is_equal_approx(audio.last_played["build"], first_time), "同じ音は少し間を空けてから鳴らす")
	
	# Mで音を消せる（macOSの⌘M（しまう）とぶつからないよう、⌘は使わない）
	await press_key(KEY_M)
	check(audio.muted and not audio.bgm_player.playing, "Mキーで音が止まる")
	check(main.last_message.contains("音をオフにしました"), "音を消したことがメッセージで出る")
	audio.last_played.clear()
	audio.play("chime")
	check(not audio.last_played.has("chime"), "音を消している間は効果音も鳴らない")
	await press_key(KEY_M)
	check(not audio.muted and audio.bgm_player.playing, "もう一度Mキーで音が戻る")
	
	# 時間帯（朝・昼・夕方・夜）でBGMが変わる
	check(audio.period_for(7 * 60) == "morning" and audio.period_for(12 * 60) == "day" and audio.period_for(18 * 60) == "evening"
		and audio.period_for(23 * 60) == "night" and audio.period_for(3 * 60) == "night", "時間帯は 朝5時・昼10時・夕方17時・夜20時 から")
	main.clock.set_time(1, 12, 0)
	await wait_until(func(): return audio.bgm_key == ["day", 1], 5.0) # まだ作っていない曲は、裏で作ってから切り替える
	check(audio.bgm_key == ["day", 1], "昼は昼のBGM")
	var day_stream = audio.bgm_player.stream
	main.clock.set_time(1, 23, 0)
	await wait_until(func(): return audio.bgm_key == ["night", 1], 5.0)
	check(audio.bgm_key == ["night", 1] and audio.bgm_player.stream != day_stream, "夜になると夜のBGMに変わる")
	main.clock.set_time(1, 18, 0)
	await wait_until(func(): return audio.bgm_key == ["evening", 1], 5.0)
	check(audio.bgm_key == ["evening", 1], "夕方は夕方のBGM")
	main.clock.set_time(1, 7, 30)
	await wait_until(func(): return audio.bgm_key == ["morning", 1], 5.0)
	check(audio.bgm_key == ["morning", 1], "朝は朝のBGM")

	# ★が上がると音が重なって豪華になる（同じ時間帯でも曲が変わる）
	var plain = audio.bgm_player.stream
	main.rating_system.stars = 3
	await wait_until(func(): return audio.bgm_key == ["morning", 3], 5.0)
	check(audio.bgm_key == ["morning", 3] and audio.bgm_player.stream != plain, "★が上がるとBGMが変わる")
	var started := Time.get_ticks_msec()
	main.rating_system.stars = 1
	await wait_frames(2)
	check(audio.bgm_player.stream == plain and Time.get_ticks_msec() - started < 500, "一度作った曲は覚えておいて、すぐに切り替える")
	var loudest := 0.0
	var rich: AudioStreamWAV = audio.make_bgm(audio.PERIODS.day, 5)
	for i in range(0, rich.data.size(), 2):
		loudest = maxf(loudest, absf(rich.data.decode_s16(i)))
	check(loudest < 32767.0, "音を重ねても、音が割れない")
	return true

# ---------------------------------------------------
# シナリオ57: タイトル画面（はじめから／続きから）
# ---------------------------------------------------
func run_title_scenario() -> bool:
	print("[シナリオ] タイトル画面")
	# このシナリオだけは、タイトル画面が出たままのゲームを作り直して確かめる
	main.queue_free()
	await wait_frames(1)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await wait_frames(3)
	use_test_save_dir()
	check(not main.started and main.title_panel.visible, "起動するとタイトル画面が出る")
	check(not main.clock.is_processing(), "タイトル画面の間は時間が止まっている")
	main.ui.do_menu_action("pause")
	check(not main.paused, "タイトル画面の間は、メニューからも一時停止できない")
	var title_labels: Array[String] = []
	for node in main.title_panel.find_children("*", "Label", true, false):
		title_labels.append(node.text)
	check(title_labels.has("ProjectTower"), "タイトルが出る")
	var buttons := {}
	for node in main.title_panel.find_children("*", "Button", true, false):
		buttons[node.text] = node
	check(buttons.has("はじめから") and buttons.keys().any(func(t: String): return t.begins_with("続きから")), "「はじめから」と「続きから」のボタンがある")
	await capture("title_01")
	
	# タイトル画面の間は、マップをクリックしても建たない
	await choose_mode("lobby")
	await click_cell(Vector2i(-9, 18), MOUSE_BUTTON_LEFT) # タイトル画面のボタンと重ならない、左のほうのマス
	check(main.building_grid.is_empty() and not main.started, "タイトル画面の間はマップを操作できない")
	
	# 「はじめから」を押すと、更地から始まる
	await click_button(buttons["はじめから"])
	check(main.started and not main.title_panel.visible, "「はじめから」でタイトル画面が閉じる")
	check(main.clock.is_processing(), "ゲームが始まると時間が動きだす")
	check(main.building_grid.is_empty() and main.funds == 3000000, "更地・資金300万Crから始まる")
	await click_cell(Vector2i(0, 18), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(0, 18)) == "lobby", "始まった後はマップを操作できる")
	return true

# ---------------------------------------------------
# シナリオ58: 目標（シナリオ）と達成の画面
# ---------------------------------------------------
func run_goal_scenario() -> bool:
	print("[シナリオ] 目標")
	var goals = main.goal_system
	focus_camera(Vector2i(0, 16))
	await wait_frames(2)
	check(goals.index == 0 and not goals.cleared, "はじめは1つ目の目標に挑戦している")
	check(goals.current().stars == 2, "1つ目の目標は★2")
	check(main.stats_label.text.contains("目標:"), "ビルの状況に今の目標が出る")
	check(not main.goal_panel.visible, "達成の画面は出ていない")
	
	# 達成すると、画面で知らせて次の目標に進む
	main.rating_system.stars = 2
	goals.check_day(1)
	check(goals.index == 1, "★2になると1つ目の目標を達成して、次の目標に進む")
	check(main.goal_panel.visible and main.goal_title.text == "目標を達成しました！", "達成の画面が出る")
	check(main.goal_text.text.contains("次の目標"), "次の目標が書いてある")
	check(logged("目標を達成しました"), "メッセージにも残る")
	await capture("goal_01_achieved")
	var close_button: Button = null
	for node in main.goal_panel.find_children("*", "Button", true, false):
		close_button = node
	await click_button(close_button)
	check(not main.goal_panel.visible, "「つづける」で画面を閉じられる")
	
	# 期限を過ぎても、続けて挑戦できる
	check(goals.current().day == 45, "2つ目の目標は45日目まで")
	main.clock.set_time(46, 12, 0)
	goals.check_day(46)
	check(goals.index == 1, "期限を過ぎても目標は変わらない")
	check(logged("目標の期限"), "期限を過ぎたことを知らせる")
	main.rating_system.stars = 3
	goals.check_day(47)
	check(goals.index == 2, "遅れて達成してもよい")
	
	# 全部達成するとクリアの画面が出る
	main.rating_system.stars = 4
	goals.check_day(48)
	main.funds = 50000000
	goals.check_day(49)
	check(goals.index == 4 and not goals.cleared, "資金の目標のあとに、最後の目標（★5）が残っている")
	main.rating_system.stars = 5
	goals.check_day(50)
	check(goals.cleared and goals.current() == null, "すべての目標を達成した")
	check(main.goal_title.text == "タワー完成！" and main.goal_text.text.contains("すべての目標を達成") and main.goal_panel.visible, "クリアの画面（タワー完成）が出る")
	await wait_frames(2) # 上部バーの表示は次のフレームで更新される
	check(main.stats_label.text.contains("すべて達成"), "ビルの状況もクリアの表示になる")
	await capture("goal_02_cleared")
	
	# 目標の進み具合はセーブに入る
	var save_path := "user://test_goal.json"
	check(main.save_system.save_game(save_path), "セーブできる")
	goals.index = 0
	goals.cleared = false
	check(main.save_system.load_game(save_path), "読み込める")
	check(goals.index == goals.GOALS.size() and goals.cleared, "目標の進み具合が戻る")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	return true

# ---------------------------------------------------
# シナリオ59: はじめての案内（チュートリアル）
#   更地から、案内のとおりに建てていくと、案内が順に進む。
# ---------------------------------------------------
func run_tutorial_scenario() -> bool:
	print("[シナリオ] はじめての案内")
	var tutorial = main.tutorial_system
	focus_camera(Vector2i(0, 17))
	await wait_frames(2)
	check(tutorial.step == 0 and not tutorial.finished, "はじめは1つ目の案内")
	check(main.tutorial_panel.visible and main.tutorial_label.text.contains("ロビーを建てよう"), "上部バーの下に案内が出る")
	await capture("tutorial_01")
	
	# 「案内を閉じる」でいつでもやめられる（確かめたら、案内を出し直して続ける）
	var skip_button: Button = null
	for node in main.tutorial_panel.find_children("*", "Button", true, false):
		skip_button = node
	await click_button(skip_button)
	await wait_frames(2)
	check(tutorial.finished and not main.tutorial_panel.visible, "「案内を閉じる」で消える")
	check(logged("案内を閉じました"), "閉じたことがメッセージで出る")
	tutorial.finished = false
	await wait_frames(2)
	check(main.tutorial_panel.visible, "案内を出し直して、続きを確かめる")
	
	# ① ロビーを建てると、次の案内へ
	await choose_mode("lobby")
	await drag_cells(Vector2i(-3, 18), Vector2i(2, 18), MOUSE_BUTTON_LEFT)
	await wait_frames(2)
	check(tutorial.step == 1 and main.tutorial_label.text.contains("エレベーター"), "ロビーを建てると2つ目の案内に進む")
	
	# ② 階段かエレベーターを建てると、次へ
	await choose_mode("stairs")
	await click_cell(Vector2i(2, 18), MOUSE_BUTTON_LEFT)
	await click_cell(Vector2i(3, 18), MOUSE_BUTTON_LEFT)
	await wait_frames(2)
	check(tutorial.step == 2 and main.tutorial_label.text.contains("オフィス"), "上下に移動できるようにすると3つ目の案内に進む")
	
	# ③ オフィスを建てると、次へ
	await choose_mode("office")
	await click_cell(Vector2i(-3, 17), MOUSE_BUTTON_LEFT) # ロビー(x=-3〜2)の上に、横4マスのオフィス
	await wait_frames(2)
	check(tutorial.step == 3 and main.tutorial_label.text.contains("時間を進め"), "オフィスを建てると4つ目の案内に進む")
	
	# ④ 時間を進めると、次へ
	main.clock.set_time(1, 9, 30)
	await wait_frames(2)
	check(tutorial.step == 4 and main.tutorial_label.text.contains("決算"), "時間を進めると5つ目の案内に進む")
	
	# ⑤ 決算があると案内は終わり
	await run_day(1)
	await wait_frames(2)
	check(tutorial.finished and not main.tutorial_panel.visible, "決算まで進むと案内は終わる")
	check(logged("案内はここまでです"), "終わりがメッセージで出る")
	
	return true

# ---------------------------------------------------
# シナリオ60: 見た目（歩くアニメーションと、建設・撤去・お金の演出）
# ---------------------------------------------------
func run_effects_scenario() -> bool:
	print("[シナリオ] 見た目の演出")
	main.funds = 10000000
	focus_camera(Vector2i(0, 16))
	await wait_frames(1)
	var effects = main.effects
	effects.effects.clear() # 共通のビルを建てたときの演出を片づけてから始める
	check(effects.effects.is_empty(), "はじめは演出が出ていない")
	
	# 建てると白い枠、撤去すると土ぼこりが出る
	await choose_mode("stairs")
	await click_cell(Vector2i(8, 18), MOUSE_BUTTON_LEFT)
	check(effects.effects.size() == 1 and effects.effects[0].type == "build", "建てると建設の演出が出る")
	await capture("effects_01_build")
	await click_cell(Vector2i(8, 18), MOUSE_BUTTON_RIGHT)
	check(effects.effects.any(func(e): return e.type == "demolish"), "撤去すると土ぼこりの演出が出る")
	
	# 演出はしばらくすると消える
	await wait_until(func(): return effects.effects.is_empty(), 5.0)
	check(effects.effects.is_empty(), "演出は時間がたつと消える")
	
	# 決算で黒字なら「+◯◯Cr」が浮かぶ
	await choose_mode("elevator")
	for y in range(18, 14, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT) # ブロックの隣にシャフトを建てて、社員が出勤できるようにする
	await run_day(1)
	var money: Array = effects.effects.filter(func(e): return e.type == "money")
	check(money.size() == 1 and money[0].text.begins_with("+"), "黒字の決算で「+◯◯Cr」が浮かぶ")
	await capture("effects_02_money")
	
	# 歩いている人は、足の形が変わる（歩いて見える）
	var resident = main.spawn_resident(Vector2i(-8, 18))
	check(resident.body_sprite() == resident.BODY_SPRITE, "立っている人はふつうの絵")
	resident.go_to(Vector2i(7, 18))
	var shapes := {}
	set_speed(2.0)
	var limit := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < limit and shapes.size() < 3 and resident.is_moving():
		shapes[resident.body_sprite()[resident.BODY_SPRITE.size() - 2]] = true
		await wait_frames(1)
	Engine.time_scale = 1.0
	print("    足の形の数: ", shapes.size())
	check(shapes.size() >= 2, "歩いている間に足の形が切り替わる")
	check(resident.walked > 0.0, "歩いた距離を数えている")
	return true

# ---------------------------------------------------
# シナリオ61: 屋上庭園（ストレスの回復が速くなり、騒音がやわらぐ）
# ---------------------------------------------------
func run_garden_scenario() -> bool:
	print("[シナリオ] 屋上庭園")
	main.funds = 10000000
	var noise = main.noise_system
	focus_camera(Vector2i(11, 16))
	await wait_frames(1)
	build_support(cells_row(18, 8, 16), "lobby")
	main.select_mode("cinema")
	main.build_at(Vector2i(8, 17)) # うるさい建物（x=8〜15、2階分）
	main.select_mode("housing")
	main.build_at(Vector2i(16, 17)) # その隣の住宅
	var home := Vector2i(16, 17)
	var noisy_before: float = noise.noise_stress(home)
	var recover_before: float = main.stress_recover_rate()
	check(noisy_before > 0.0 and is_equal_approx(recover_before, 1.0), "屋上庭園がないと、騒音はそのままで回復も標準")
	
	# 屋上庭園は屋上にだけ建てられる
	await choose_mode("garden")
	check(main.mode_select.text.begins_with("屋上庭園") and main.mode_select.text.ends_with("400,000Cr"), "屋上庭園は40万Cr")
	check(main.get_build_problem(Vector2i(20, 18), "garden").contains("屋上"), "1階（地上）には建てられない")
	await click_cell(Vector2i(8, 15), MOUSE_BUTTON_LEFT) # 映画館（y=17〜16）の上が屋上
	check(main.get_building_type(Vector2i(11, 15)) == "garden", "映画館の屋上に庭園を建てられる")
	await hover_cell(Vector2i(10, 15))
	check(main.hover_label.text.contains("屋上庭園（ストレスの回復"), "カーソルを合わせると効果が出る")
	await capture("garden_01")
	
	# 効果: 回復が速くなり、騒音がやわらぐ
	check(main.stress_recover_rate() > recover_before, "ストレスの回復が速くなる（%.1f倍）" % main.stress_recover_rate())
	check(noise.quiet_bonus() == noise.GARDEN_QUIET, "騒音を和らげる分が増える")
	check(noise.noise_stress(home) < noisy_before, "隣の住宅の騒音のつらさが減る")
	
	# メディカルセンターと合わせても、回復の速さには上限がある
	build_support(cells_row(18, 17, 22), "lobby")
	main.select_mode("medical")
	for x in [17, 20]:
		main.build_at(Vector2i(x, 17))
	main.select_mode("garden")
	main.build_at(Vector2i(17, 16)) # メディカルセンター（y=17）の上
	check(is_equal_approx(main.stress_recover_rate(), main.MEDICAL_RECOVER_MAX), "回復の速さは2.5倍で頭打ち")
	return true

# 指定した日の朝から全員を出勤させ、その日の決算まで時計を進める
# 目標の達成画面は、ほかのシナリオの操作の邪魔になるので閉じておく
func close_goal_panel() -> void:
	if main.goal_panel and main.goal_panel.visible:
		main.goal_panel.visible = false

func run_day(day: int) -> void:
	main.clock.set_time(day, 7, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60, 30.0)
	main.clock.set_time(day, 23, 58)
	await wait_until(func(): return main.economy_system.last_report.get("day") == day, 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	close_goal_panel()

func count_rides(path: Array[Vector2i]) -> int:
	var rides := 0
	for i in path.size() - 1:
		if main.is_elevator_ride(path[i], path[i + 1]):
			rides += 1
	return rides

# テストの足場: 支えのために、指定したマスに建物を建てる（2階から上は階段、1階はロビー）。
# 階段とロビーは社員も維持費も増やさず、足場の建設費は元に戻すので、
# 各シナリオの人数・金額の確認には影響しない
func build_support(cells: Array, type := "stairs") -> void:
	var funds_before: int = main.funds
	var mode: String = main.current_mode
	main.select_mode(type)
	for cell in cells:
		main.build_at(cell)
	main.select_mode(mode)
	main.funds = funds_before
	main.update_funds_display()

# y階の x0〜x1 のマスの一覧（build_support に渡す）
func cells_row(y: int, x0: int, x1: int) -> Array:
	var cells: Array = []
	for x in range(x0, x1 + 1):
		cells.append(Vector2i(x, y))
	return cells

# ゲーム開始からのメッセージの記録に、その文字が出てきたか
#（メッセージはほかの知らせで上書きされることがあるので、記録から探す）
func logged(text: String) -> bool:
	return main.message_log.any(func(line: String): return line.contains(text))

# マウスのボタンを押したまま、fromのマスからtoのマスまでなぞる（ドラッグでの連続建設・撤去）
func drag_cells(from: Vector2i, to: Vector2i, button: MouseButton) -> void:
	var tile_map: TileMapLayer = main.tile_map
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = tile_map.get_global_transform_with_canvas() * tile_map.map_to_local(from)
	press.global_position = press.position
	root.push_input(press)
	await wait_frames(1)
	var cell := from
	while cell != to:
		cell += step
		var motion := InputEventMouseMotion.new()
		motion.position = tile_map.get_global_transform_with_canvas() * tile_map.map_to_local(cell)
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		root.push_input(motion)
		await wait_frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = tile_map.get_global_transform_with_canvas() * tile_map.map_to_local(to)
	release.global_position = release.position
	root.push_input(release)
	await wait_frames(1)

# ⌘（Command）を押しながらキーを押す（⌘L・⌘Gなどのショートカット）
func press_shortcut(keycode: Key) -> void:
	await press_key(keycode, true)

# ⌘なしでキーを押す（F1・H・M・Esc）
func press_key(keycode: Key, meta := false) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	press.meta_pressed = meta
	root.push_input(press)
	await wait_frames(2)

# 建設メニューから選ぶ（プレイヤーがリストで項目を選んだときと同じく item_selected を送る）
func choose_mode(mode: String) -> void:
	var select: OptionButton = main.mode_select
	for i in select.item_count:
		if select.get_item_metadata(i) == mode:
			select.select(i)
			select.item_selected.emit(i)
	await wait_frames(1)

# 指定したマスが画面の中央に来るようにカメラを動かす
func focus_camera(cell: Vector2i) -> void:
	main.camera.focus_on(main.tile_map.to_global(main.tile_map.map_to_local(cell)))

func hover_cell(cell: Vector2i) -> void:
	var tile_map: TileMapLayer = main.tile_map
	var motion := InputEventMouseMotion.new()
	motion.position = tile_map.get_global_transform_with_canvas() * tile_map.map_to_local(cell)
	motion.global_position = motion.position
	root.push_input(motion)
	await wait_frames(2)
	# カーソルの位置が下部バーの表示に反映されるまで待つ（早送り中はフレームの間隔が変わるため）
	await wait_until(func(): return main.grid_overlay.hover_visible and main.grid_overlay.hover_cell == cell, 2.0)

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

	# 押す・離すは同じフレームで送る（間に別の入力が入ってクリックが取り消されないように）
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev)
	await wait_frames(1)

# ホイールを回す。zoom なら Ctrl を押しながら（ズーム）、shift なら Shift を押しながら（左右スクロール）
func scroll_wheel(pos: Vector2, button: MouseButton, times: int, zoom := true, shift := false) -> void:
	for i in times:
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			ev.pressed = pressed
			ev.ctrl_pressed = zoom
			ev.shift_pressed = shift
			ev.position = pos
			ev.global_position = pos
			root.push_input(ev)
	await wait_frames(1)

# トラックパッドの2本指スクロールを times 回送る
func pan_gesture(pos: Vector2, delta: Vector2, times: int) -> void:
	for i in times:
		var pan := InputEventPanGesture.new()
		pan.position = pos
		pan.delta = delta
		root.push_input(pan)
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

# キーを押したままにする（meta なら⌘も一緒に押す。⌘を先に押して、後で離す）
func hold_key(keycode: Key, seconds: float, meta := false) -> void:
	var keys: Array = [KEY_META, keycode] if meta else [keycode]
	for key in keys:
		send_key(key, true, meta)
	await create_timer(seconds, true, false, true).timeout # 一時停止中（時間の速さ0）でも進むタイマー
	keys.reverse()
	for key in keys:
		send_key(key, false, meta and key != KEY_META)
	await wait_frames(1)

func send_key(keycode: Key, pressed: bool, meta: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	ev.meta_pressed = meta
	Input.parse_input_event(ev)

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

# 早送りの倍率の上限。ゲーム内で進む時間は「倍率×2分/秒」なので、倍率を上げるほどテストは速く終わる。
# ただし倍率を fps に比べて上げすぎると1フレームが長くなりすぎて、エレベーターの扉が開いている
# 1秒ぶんを1フレームで飛び越えてしまい、乗れない人が出る（実際の遊びと違う動きになる）。
# そこで set_speed() では、今出ている fps の3分の1を超えない範囲で倍率を上げる
#（画面の更新の上限は外してあるので、速い機械ほど速く終わる）。
const SPEED_UP := 2.0

# シナリオの早送り。scale はふだんの倍率で、機械（そのときのfps）が速ければ最大 SPEED_UP 倍まで上げる。
# 待ち時間の上限（wait_until のタイムアウト）は実時間なので、倍率を下げすぎると逆に間に合わなくなる。
# そのため倍率は始めに1回だけ決め、待っている間は変えない
func set_speed(scale: float) -> void:
	Engine.time_scale = clampf(Engine.get_frames_per_second() / 3.0, scale, scale * SPEED_UP)

func wait_frames(n: int) -> void:
	for i in n:
		await process_frame

# シナリオ62: ファストフード（早くて安い店）
# 2階に「ファストフード｜オフィス｜オフィス｜飲食店」と並べて、
# 社員がそれぞれ近い方の店で食事をすることを確かめる。
# ---------------------------------------------------
func run_fastfood_scenario() -> bool:
	print("[シナリオ] ファストフード")
	main.clear_world()
	main.funds = 10000000
	var commerce = main.commerce_system
	# 足場: 1階のロビーと、2階へ上がるエレベーター
	build_support(cells_row(18, 9, 24), "lobby")
	build_support([Vector2i(8, 18), Vector2i(8, 17)], "elevator")
	var fastfood := Vector2i(9, 17)    # 2階の左（x=9〜10）
	var restaurant := Vector2i(19, 17) # 2階の右（x=19〜21）

	await choose_mode("fastfood")
	await click_cell(fastfood, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(fastfood) == "fastfood", "ファストフードを建てられる（12万Cr）")
	check(main.funds == 10000000 - 120000, "ファストフードの建設費12万Crがかかる")
	check(main.get_building_type(Vector2i(10, 17)) == "fastfood", "ファストフードは横2マス")
	check(main.get_building_type(Vector2i(11, 17)) == "", "ファストフードは3マス目までは使わない")
	check(commerce.RESTAURANTS["fastfood"].minutes < commerce.RESTAURANTS["restaurant"].minutes, "ファストフードの食事は飲食店より短い")
	check(commerce.RESTAURANTS["fastfood"].price < commerce.RESTAURANTS["restaurant"].price, "ファストフードの代金は飲食店より安い")

	await choose_mode("restaurant")
	await click_cell(restaurant, MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	await click_cell(Vector2i(11, 17), MOUSE_BUTTON_LEFT) # 左のオフィス（x=11〜14。ファストフードが近い）
	await click_cell(Vector2i(15, 17), MOUSE_BUTTON_LEFT) # 右のオフィス（x=15〜18。飲食店が近い）
	main.funds = 10000000

	# 出勤させてから昼休みへ
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return main.commute_system.count_at_office() == 8, 30.0)
	main.clock.set_time(1, 11, 59)
	var ate := {"fastfood": 0, "restaurant": 0}
	await wait_until(func():
		ate.fastfood = maxi(ate.fastfood, commerce.count_eating_at(fastfood))
		ate.restaurant = maxi(ate.restaurant, commerce.count_eating_at(restaurant))
		return main.clock.minute_of_day() >= 13 * 60, 30.0)
	focus_camera(Vector2i(15, 17))
	await wait_frames(2)
	await capture("fastfood_01_lunch")
	check(ate.fastfood > 0, "社員はファストフードで食事をする")
	check(ate.restaurant > 0, "飲食店が近い社員は飲食店へ行く")
	await hover_cell(fastfood)
	check(main.hover_label.text.contains("ファストフード（客 "), "カーソルを合わせると店にいる客の数が出る")
	await wait_until(func(): return main.clock.minute_of_day() >= 15 * 60, 30.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(commerce.revenue_by_day.get(1, 0) > 0, "ファストフードの売上が飲食の売上に入る")
	return true

# シナリオ63: オフィスの種類（小さいオフィス・大きいオフィス）
# 横2マス2人・横4マス4人・横6マス6人の3種類を建てて、
# 社員の数と1マスの賃料が種類ごとに違うことを確かめる。
# ---------------------------------------------------
func run_office_types_scenario() -> bool:
	print("[シナリオ] オフィスの種類")
	main.clear_world()
	main.funds = 10000000
	var economy = main.economy_system
	build_support(cells_row(18, 9, 22), "lobby")
	build_support([Vector2i(8, 18), Vector2i(8, 17)], "elevator")
	var small := Vector2i(9, 17)  # 小さいオフィス（x=9〜10）
	var large := Vector2i(11, 17) # 大きいオフィス（x=11〜16）
	var normal := Vector2i(17, 17) # ふつうのオフィス（x=17〜20）

	await choose_mode("small_office")
	await click_cell(small, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(small) == "small_office", "小さいオフィスを建てられる（24万Cr）")
	check(main.funds == 10000000 - 240000, "小さいオフィスの建設費24万Crがかかる")
	check(main.get_unit_cells(small).size() == 2, "小さいオフィスは横2マス")
	await choose_mode("large_office")
	await click_cell(large, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(large) == "large_office", "大きいオフィスを建てられる（48万Cr）")
	check(main.get_unit_cells(large).size() == 6, "大きいオフィスは横6マス")
	await choose_mode("office")
	await click_cell(normal, MOUSE_BUTTON_LEFT)
	main.funds = 10000000

	# 社員は1マスに1人
	check(main.commute_system.workers.size() == 12, "社員は1マスに1人（2+6+4=12人）")
	check(economy.office_rent(small) > economy.office_rent(normal), "小さいオフィスは1マスの賃料が高い")
	check(economy.office_rent(large) < economy.office_rent(normal), "大きいオフィスは1マスの賃料が安い")
	check(economy.office_rent(small) == 11000 and economy.office_rent(large) == 9000, "賃料は1マス1日 1.1万Cr・0.9万Cr")

	# 1日目の決算: 出勤した12人ぶんの賃料が種類ごとに計算される
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	set_speed(16.0)
	await wait_until(func(): return main.commute_system.count_at_office() == 12, 40.0)
	focus_camera(Vector2i(14, 17))
	await wait_frames(2)
	await capture("office_types_01")
	main.clock.set_time(1, 23, 59)
	await wait_until(func(): return economy.last_report.get("day") == 1, 20.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(economy.last_report.get("rent") == 2 * 11000 + 6 * 9000 + 4 * 10000, "決算の賃料は種類ごとの合計（2.2万＋5.4万＋4万＝11.6万Cr）")
	return true

# シナリオ64: 空きフロア（撤去の跡地）
# 上の階を支えているマスを撤去すると、建物の代わりに骨組み（空きフロア）が残り、
# 上の階を崩さずに建て替えられる。跡地は通り抜けられて、その上から建て直せる。
# ---------------------------------------------------
func run_frame_scenario() -> bool:
	print("[シナリオ] 空きフロア（撤去の跡地）")
	main.clear_world()
	main.funds = 10000000
	build_support(cells_row(18, 8, 16), "lobby")
	# 2階に飲食店（x=9〜11）、その上の3階にオフィス（x=9〜12）を建てる
	var shop := Vector2i(9, 17)
	await choose_mode("restaurant")
	await click_cell(shop, MOUSE_BUTTON_LEFT)
	build_support([Vector2i(12, 17)]) # 3階のオフィスを支える足場
	await choose_mode("office")
	await click_cell(Vector2i(9, 16), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 16)) == "office", "3階にオフィスが建つ")

	# 下の飲食店を撤去すると、上のオフィスを支えるために空きフロアが残る
	main.funds = 10000000
	await click_cell(shop, MOUSE_BUTTON_RIGHT)
	check(main.get_building_type(shop) == "frame", "支えているマスを撤去すると、空きフロアが残る")
	check(main.get_building_type(Vector2i(11, 17)) == "frame", "建物の幅のぶんだけ空きフロアになる")
	check(main.get_building_type(Vector2i(9, 16)) == "office", "上の階のオフィスはそのまま残る")
	check(main.funds == 10000000 - 20000, "撤去費用（建設費の1割＝2万Cr）がかかる")
	check(logged("空きフロアになります"), "空きフロアが残ることがメッセージで出る")
	await hover_cell(shop)
	check(main.hover_label.text.contains("空きフロア"), "カーソルを合わせると空きフロアと出る")
	await capture("frame_01_left")

	# 空きフロアは通り抜けられる
	check(main.is_walkable(shop), "空きフロアは通り抜けられる")
	check(not main.find_path(Vector2i(12, 17), Vector2i(9, 17)).is_empty(), "空きフロアを通り抜ける経路が見つかる")

	# 空きフロアの上には、そのまま別の建物を建て直せる
	await choose_mode("housing")
	await click_cell(shop, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(shop) == "housing", "空きフロアの上には別の建物を建て直せる")
	check(main.get_building_type(Vector2i(11, 17)) == "housing", "建物の幅のぶんの空きフロアが置き換わる")
	await capture("frame_02_rebuilt")

	# 建設メニューからも空きフロアを建てられる（すき間を埋めて、上の階を建てられるようにする）
	main.funds = 10000000
	await choose_mode("frame")
	check(main.mode_select.tooltip_text.contains("骨組みだけのフロア"), "カーソルを合わせると空きフロアの説明が出る")
	await click_cell(Vector2i(13, 17), MOUSE_BUTTON_LEFT) # 2階のすき間
	check(main.get_building_type(Vector2i(13, 17)) == "frame", "メニューから空きフロアを建てられる")
	check(main.funds == 10000000 - 10000, "空きフロアの建設費1万Crがかかる")
	await click_cell(Vector2i(13, 17), MOUSE_BUTTON_LEFT)
	check(main.last_message == "ここはもう空きフロアです", "空きフロアの上に空きフロアは建てない")
	await choose_mode("office")
	await click_cell(Vector2i(13, 16), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(13, 16)) == "", "1マスだけでは、その上に横4マスのオフィスは建てられない")
	await choose_mode("frame")
	focus_camera(Vector2i(13, 17)) # 右のほうのマスが画面の外に出ないようにする
	await wait_frames(1)
	for x in [14, 15, 16]:
		await click_cell(Vector2i(x, 17), MOUSE_BUTTON_LEFT)
	await choose_mode("office")
	await click_cell(Vector2i(13, 16), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(13, 16)) == "office", "空きフロアで支えれば、その上に建てられる")
	await capture("frame_03_filled")

	# 間が空いていても、上の階に建物が残っていれば空きフロアになる（上の部屋が浮かないように）
	await choose_mode("office")
	await click_cell(Vector2i(13, 15), MOUSE_BUTTON_LEFT) # 4階（3階のオフィスの上）
	await click_cell(Vector2i(13, 16), MOUSE_BUTTON_RIGHT) # 間の3階を撤去
	check(main.get_building_type(Vector2i(13, 16)) == "frame", "間の階を撤去しても、上に建物が残っていれば空きフロアになる")
	check(main.get_building_type(Vector2i(13, 15)) == "office", "上の階のオフィスは浮かずに残る")
	check(logged("空きフロアになります"), "空きフロアになることがメッセージで出る")
	await click_cell(Vector2i(13, 15), MOUSE_BUTTON_RIGHT) # 一番上を撤去（上には何もない）
	check(main.is_cell_empty(Vector2i(13, 15)), "一番上の階は、跡地を残さず更地に戻る")

	# 支えるものがなくなった空きフロアは、ふつうに撤去できる
	await click_cell(Vector2i(9, 16), MOUSE_BUTTON_RIGHT) # 上のオフィスを撤去
	await click_cell(shop, MOUSE_BUTTON_RIGHT)            # 住宅を撤去（もう支えていないので更地に戻る）
	check(main.is_cell_empty(shop), "上に何もなくなったら、撤去で更地に戻る（跡地は残らない）")
	return true

# シナリオ65: 大型エレベーター（横2マス・定員16人・速さ1.5倍）
# 横2マスで1本のシャフトになること、定員と速さ、経路探索で選ばれやすいことを確かめる。
# ---------------------------------------------------
func run_large_elevator_scenario() -> bool:
	print("[シナリオ] 大型エレベーター")
	main.clear_world()
	main.funds = 10000000
	var elevators = main.elevator_system
	build_support(cells_row(18, 4, 7) + cells_row(18, 11, 20), "lobby") # シャフトの場所（x=8〜10）は空けておく
	# x=8〜9 に大型エレベーター（1階〜5階）
	await choose_mode("large_elevator")
	check(main.mode_select.tooltip_text.contains("定員16人"), "カーソルを合わせると定員と速さが出る")
	for y in range(18, 13, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 18)) == "large_elevator", "大型エレベーターは横2マス")
	check(main.funds == 10000000 - 5 * 240000, "1階ぶん24万Cr（横2マス）かかる")

	var large = elevators.get_car_at(Vector2i(8, 18))
	check(large != null and large.capacity == 16, "大型のカゴは定員16人")
	check(is_equal_approx(large.speed, large.SPEED * 1.5), "大型のカゴは標準の1.5倍の速さ")
	check(elevators.cars.size() == 1, "横2マスでもシャフトは1本（カゴは1台）")
	check(elevators.get_car_at(Vector2i(9, 16)) == large, "右のマスからも同じカゴを使える")
	check(large.is_stop_floor(16), "大型は途中の階にも停まる（急行とちがう）")

	# 右隣に標準のエレベーターを建てて、経路探索がどちらを選ぶか確かめる
	await choose_mode("elevator")
	for y in range(18, 13, -1):
		await click_cell(Vector2i(10, y), MOUSE_BUTTON_LEFT)
	var standard = elevators.get_car_at(Vector2i(10, 18))
	check(standard != null and standard.capacity == 8, "標準のカゴは定員8人のまま")
	var moves: Array = main.pathfinding.get_moves(Vector2i(8, 18))
	var large_cost := 0.0
	for m in moves:
		if m.to == Vector2i(8, 14):
			large_cost = m.cost
	var standard_moves: Array = main.pathfinding.get_moves(Vector2i(10, 18))
	var standard_cost := 0.0
	for m in standard_moves:
		if m.to == Vector2i(10, 14):
			standard_cost = m.cost
	check(large_cost < standard_cost, "大型は待ち時間が短く速いので、経路の費用が標準より小さい")

	# 標準のシャフトの目の前にいる人でも、5階へ行くなら大型まで歩いて乗る
	var path: Array[Vector2i] = main.find_path(Vector2i(10, 18), Vector2i(8, 14))
	check(count_rides(path) == 1, "エレベーターに1回乗る経路になる")
	check(not path.has(Vector2i(10, 14)), "標準ではなく大型エレベーターを選ぶ")
	focus_camera(Vector2i(9, 16))
	await wait_frames(2)
	await capture("large_elevator_01")
	return true

# シナリオ66: 経路表示（人の通り道を線で出す）
# 上部バーのボタンとRキーで切り替えられ、既定はオフ。描くだけで移動には影響しない。
# ---------------------------------------------------
func run_routes_scenario() -> bool:
	print("[シナリオ] 経路表示")
	main.funds = 10000000
	check(not main.show_routes, "経路の表示は最初はオフ")
	check(main.route_button.text == "経路 オフ", "上部バーのボタンに今の状態が出る")

	# 住人を1人置いて、遠くへ歩かせる
	main.select_mode(main.MODE_RESIDENT)
	await click_cell(Vector2i(-8, 17), MOUSE_BUTTON_LEFT)
	var resident = main.selected_resident
	check(resident != null, "住人モードで住人を置ける")
	await click_cell(Vector2i(4, 17), MOUSE_BUTTON_LEFT)
	check(not resident.path.is_empty(), "行き先を指示すると通り道ができる")
	var steps: int = resident.path.size()

	# Rキーでオンにすると線が出る
	await press_key(KEY_R)
	check(main.show_routes, "Rキーで経路の表示がオンになる")
	check(main.route_button.text == "経路 オン", "ボタンの表示も切り替わる")
	check(logged("経路の表示をオンにしました"), "切り替えたことがメッセージで出る")
	check(resident.path.size() == steps, "経路を表示しても、通り道は変わらない（見た目だけ）")
	focus_camera(Vector2i(-2, 17))
	await wait_frames(2)
	await capture("routes_01_on")

	# ボタンでもオフに戻せる
	main.route_button.pressed.emit()
	check(not main.show_routes, "ボタンでオフに戻せる")
	check(main.route_button.text == "経路 オフ", "ボタンの表示ももとに戻る")
	await capture("routes_02_off")
	return true

# シナリオ67: メニューバー（マウスでも各機能に届くようにする）
# ショートカットと同じことが、画面上部のメニューからもできる。
# macOSでは画面最上部のシステムのメニューバーに出る。
# ---------------------------------------------------
func run_menu_scenario() -> bool:
	print("[シナリオ] メニューバー")
	var ui = main.ui
	var names: Array = []
	for popup in main.menu_bar.get_children():
		names.append(String(popup.name))
	check(names == ["ファイル", "表示", "ゲーム", "ヘルプ"], "メニューは ファイル・表示・ゲーム・ヘルプ の4つ")
	check(main.menu_bar.prefer_global_menu, "macOSでは画面最上部のメニューバーに出す設定になっている")
	# 建設メニューのどの項目にも、右側に金額（設定を変えるだけのものは「無料」）が出る
	var no_price: Array = []
	for i in main.mode_select.item_count:
		if main.mode_select.is_item_separator(i):
			continue
		var text: String = main.mode_select.get_item_text(i)
		if not (text.ends_with("Cr") or text.ends_with("Cr〜") or text.ends_with("無料")):
			no_price.append(text)
	check(no_price.is_empty(), "建設メニューのどの項目にも金額か「無料」が出る（出ていない項目: %s）" % ", ".join(no_price))
	# 「住人（テスト）」はテストのときだけメニューに出る
	var other_group: Dictionary = main.MODE_GROUPS[-1]
	check(ui.menu_modes(other_group).has(main.MODE_RESIDENT), "テストのときは、建設メニューに「住人（テスト）」がある")
	main.test_tools = false
	check(not ui.menu_modes(other_group).has(main.MODE_RESIDENT) and ui.menu_modes(other_group).has(main.MODE_RENT), "遊ぶときは、建設メニューに「住人（テスト）」が出ない")
	main.test_tools = true
	var widths := {}
	for i in main.mode_select.item_count:
		if not main.mode_select.is_item_separator(i):
			widths[ThemeDB.fallback_font.get_string_size(main.mode_select.get_item_text(i), HORIZONTAL_ALIGNMENT_LEFT, -1, ui.BASE_FONT_SIZE * ui.UI_SCALE).x] = true
	var sorted_widths: Array = widths.keys()
	sorted_widths.sort()
	check(sorted_widths[-1] - sorted_widths[0] < ThemeDB.fallback_font.get_string_size("  ", HORIZONTAL_ALIGNMENT_LEFT, -1, ui.BASE_FONT_SIZE * ui.UI_SCALE).x, "金額の右端がそろっている")

	# 「ヘルプ > 操作説明」で、F1と同じように開け閉めできる
	check(not main.help_panel.visible, "操作説明は最初は閉じている")
	ui.do_menu_action("help")
	check(main.help_panel.visible, "メニューから操作説明を開ける")
	await capture("menu_01_help")
	ui.do_menu_action("help")
	check(not main.help_panel.visible, "もう一度選ぶと閉じる")

	# 「表示 > 経路」はショートカットと同じ切り替え
	check(not main.show_routes, "経路の表示は最初はオフ")
	ui.do_menu_action("routes")
	check(main.show_routes and main.route_button.text == "経路 オン", "メニューから経路を出せる（ボタンの表示も合う）")
	ui.do_menu_action("routes")
	check(not main.show_routes, "もう一度選ぶとオフに戻る")

	# 「ゲーム > 速さ」「ゲーム > 音」
	check(is_equal_approx(Engine.time_scale, 1.0), "速さは最初は1x")
	ui.do_menu_action("speed")
	check(is_equal_approx(Engine.time_scale, 4.0) and main.speed_button.text == "4x", "メニューから速さを切り替えられる")
	ui.do_menu_action("speed")
	ui.do_menu_action("speed")
	check(is_equal_approx(Engine.time_scale, 1.0), "3回選ぶと1xに戻る")
	ui.do_menu_action("mute")
	check(main.audio_system.muted, "メニューから音を消せる")
	ui.do_menu_action("mute")
	check(not main.audio_system.muted, "もう一度選ぶと音が戻る")

	# 「表示 > 拡大・縮小・もとの大きさ」
	var zoom: float = main.camera.zoom.x
	ui.do_menu_action("zoom_in")
	check(main.camera.zoom.x > zoom, "メニューから拡大できる")
	ui.do_menu_action("zoom_reset")
	check(is_equal_approx(main.camera.zoom.x, zoom), "もとの大きさに戻せる")

	# 開いたときに、今の状態がチェックマークで出る
	var view_menu: PopupMenu = main.menu_bar.get_children()[1]
	var items: Array = ui.MENUS[1].items
	var routes_index := 0
	for i in items.size():
		if items[i].action == "routes":
			routes_index = i
	main.show_routes = true
	ui.update_menu_checks(view_menu, items)
	check(view_menu.is_item_checked(routes_index), "経路がオンのときはチェックが付く")
	main.show_routes = false
	ui.update_menu_checks(view_menu, items)
	check(not view_menu.is_item_checked(routes_index), "オフのときはチェックが外れる")
	return true

# シナリオ68: 撤去費用・焼け跡・建て替え
# 撤去にはお金がかかり（建設費は戻らない）、火災・爆破のあとは黒焦げの焼け跡が残る。
# 建物の上に直接ほかの建物は建てられず、先に撤去してから建てる。
# ---------------------------------------------------
func run_demolish_rules_scenario() -> bool:
	print("[シナリオ] 撤去費用・焼け跡・建て替え")
	main.clear_world()
	main.funds = 10000000
	build_support(cells_row(18, 8, 16), "lobby")
	focus_camera(Vector2i(11, 17))
	await wait_frames(1)
	await choose_mode("office")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT) # 2階のオフィス（x=9〜12）
	await click_cell(Vector2i(9, 16), MOUSE_BUTTON_LEFT) # 3階のオフィス（x=9〜12）
	check(main.demolish_fee("office") == 40000, "オフィスの撤去費用は建設費の1割（4万Cr）")
	check(main.demolish_fee("lobby") == main.MIN_DEMOLISH_FEE, "建設費が安いものも、最低%dCrかかる" % main.MIN_DEMOLISH_FEE)

	# 建物の上には、直接ほかの建物を建てられない（先に撤去する）
	await choose_mode("shop")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 17)) == "office", "オフィスの上に直接ショップは建てられない")

	# 火災・爆破のあとは黒焦げの焼け跡が残る（上の階は支えたまま）
	main.destroy_unit(Vector2i(9, 17))
	check(main.get_building_type(Vector2i(9, 17)) == "ruin" and main.get_building_type(Vector2i(12, 17)) == "ruin", "焼け落ちた部屋のマスは全部、焼け跡になる")
	check(main.get_building_type(Vector2i(9, 16)) == "office", "上の階のオフィスは浮かずに残る")
	await hover_cell(Vector2i(10, 17))
	check(main.hover_label.text.contains("焼け跡（撤去してから建て直せる"), "カーソルを合わせると、撤去が要ると出る")
	await capture("demolish_01_ruin")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 17)) == "ruin", "焼け跡の上には、そのままでは建てられない")

	# 撤去費用が足りないと撤去できない
	main.funds = 1000
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_RIGHT)
	check(main.get_building_type(Vector2i(9, 17)) == "ruin" and main.funds == 1000, "撤去費用が足りないと撤去できない")
	check(main.last_message.begins_with("撤去費用が足りません"), "足りないことがメッセージで出る")

	# 焼け跡を撤去すると（上に建物があるので）空きフロアになり、その上に建て直せる
	main.funds = 10000000
	main.select_mode(main.MODE_DEMOLISH)
	await drag_cells(Vector2i(9, 17), Vector2i(12, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 17)) == "frame" and main.get_building_type(Vector2i(12, 17)) == "frame", "焼け跡をなぞって撤去すると、空きフロアになる")
	check(main.funds == 10000000 - 4 * main.MIN_DEMOLISH_FEE, "焼け跡の撤去費用は1マス%dCr" % main.MIN_DEMOLISH_FEE)
	await choose_mode("shop")
	await click_cell(Vector2i(9, 17), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(9, 17)) == "shop", "撤去して空けた場所には、新しい施設を建てられる")
	await capture("demolish_02_rebuilt")
	return true

# シナリオ69: 事件の的はテナントだけ（火はエレベーターや階段に燃え移らない・
# 撤去して建て直したテナントにゴキブリは引き継がれない）
# ---------------------------------------------------
func run_incident_targets_scenario() -> bool:
	print("[シナリオ] 事件の的はテナントだけ")
	main.clear_world()
	main.funds = 10000000
	var incidents = main.incident_system
	build_support(cells_row(18, 8, 16), "lobby")
	main.select_mode("shop")
	main.build_at(Vector2i(9, 17)) # ショップ（x=9〜11）
	build_support([Vector2i(12, 17), Vector2i(8, 17)]) # 左右に階段
	main.select_mode("office")
	main.build_at(Vector2i(9, 16)) # 上にオフィス（x=9〜12）

	# 火はテナントにだけ燃え移る
	incidents.start_fire(Vector2i(11, 17))
	for i in 3:
		incidents.spread_fire(true) # 必ず燃え移らせて、燃え移る先の決まりを確かめる
	check(incidents.fire.has(Vector2i(10, 17)), "同じショップの隣のマスには燃え広がる")
	check(incidents.fire.has(Vector2i(11, 16)), "上の階のオフィスにも燃え広がる")
	check(not incidents.fire.has(Vector2i(12, 17)) and not incidents.fire.has(Vector2i(8, 17)), "階段には燃え移らない")
	check(not incidents.fire.has(Vector2i(11, 18)), "下の階のロビーには燃え移らない")
	incidents.reset_incidents()
	incidents.start_fire(Vector2i(10, 16)) # 上の階のオフィスから出火
	incidents.spread_fire(true)
	check(incidents.fire.has(Vector2i(10, 17)), "下の階のテナントにも燃え広がる（上下左右）")
	# ふつうは確率で燃え移る（左右は上下より燃え移りやすい）。同じ火事なら毎回同じ広がり方になる
	var spread_counts := {"side": 0, "vertical": 0}
	for i in 200:
		incidents.reset_incidents()
		main.clock.day = 1 + i
		incidents.start_fire(Vector2i(10, 16))
		incidents.spread_fire()
		spread_counts.side += int(incidents.fire.has(Vector2i(9, 16))) + int(incidents.fire.has(Vector2i(11, 16)))
		spread_counts.vertical += int(incidents.fire.has(Vector2i(10, 17)))
	check(spread_counts.side > 150 and spread_counts.side < 330, "左右へは、ときどき燃え移る（400回のうち%d回）" % spread_counts.side)
	check(spread_counts.vertical > 20 and spread_counts.vertical < 90, "上下の階へは、左右より燃え移りにくい（200回のうち%d回）" % spread_counts.vertical)
	main.clock.day = 1
	incidents.reset_incidents()
	incidents.start_fire(Vector2i(10, 16))
	incidents.spread_fire()
	var first: Array = incidents.fire.keys()
	incidents.reset_incidents()
	incidents.start_fire(Vector2i(10, 16))
	incidents.spread_fire()
	check(incidents.fire.keys() == first, "同じ日・同じ場所の火事なら、同じように燃え広がる")
	incidents.reset_incidents()

	# 撤去して建て直したテナントに、ゴキブリは引き継がれない
	incidents.roaches[Vector2i(9, 17)] = true
	main.demolish_at(Vector2i(9, 17)) # 上にオフィスがあるので、空きフロアになる
	check(main.get_building_type(Vector2i(9, 17)) == "frame", "ゴキブリのいたショップを撤去すると空きフロアになる")
	check(not incidents.roaches.has(Vector2i(9, 17)), "撤去すると、そのテナントのゴキブリはすぐ消える")
	main.select_mode("shop")
	main.build_at(Vector2i(9, 17))
	check(main.get_building_type(Vector2i(9, 17)) == "shop" and not incidents.has_roaches(), "同じ場所に建て直したテナントには、ゴキブリがいない")
	return true

# シナリオ70: 爆弾の捜索（場所が分からないので、警備員が近い棟から調べて回る）
# 2階に「警備室｜ショップ×4」と並べ、一番遠いショップに爆弾を仕掛ける。
# ---------------------------------------------------
func run_bomb_search_scenario() -> bool:
	print("[シナリオ] 爆弾の捜索")
	main.clear_world()
	main.funds = 10000000
	var incidents = main.incident_system
	build_support(cells_row(18, 8, 23), "lobby")
	main.select_mode("security")
	main.build_at(Vector2i(8, 17)) # 警備室A（x=8〜9）
	main.select_mode("shop")
	for x in [10, 13, 16, 19]:
		main.build_at(Vector2i(x, 17)) # ショップ4棟（x=10〜21）
	await wait_frames(2)
	focus_camera(Vector2i(15, 17))
	await wait_frames(1)

	# 一番遠いショップに爆弾。警備員は近い棟から順に調べる
	main.clock.set_time(1, 10, 0)
	main.clock.set_process(true)
	incidents.start_bomb(Vector2i(20, 17)) # ショップのどのマスでも、その棟に仕掛けられる
	check(incidents.bomb.cell == Vector2i(19, 17), "爆弾は棟（左端のマス）ごとに扱う")
	incidents.refuse_ransom()
	await wait_frames(2)
	check(incidents.bomb.search[Vector2i(8, 17)].target == Vector2i(10, 17), "警備員は一番近い棟から調べに行く")
	set_speed(8.0)
	await wait_until(func(): return incidents.bomb != null and incidents.bomb.searched.size() >= 1, 30.0)
	check(not incidents.bomb.found, "爆弾のない棟を調べても、見つからない")
	await wait_frames(2)
	check(main.stats_label.text.contains("捜索中") and main.stats_label.text.contains("/4棟を調べた"), "ビルの状況に捜索の進み具合が出る")
	await capture("bomb_search_01")
	await wait_until(func(): return incidents.bomb == null or incidents.bomb.found, 60.0)
	check(incidents.bomb != null and incidents.bomb.found, "調べて回るうちに、爆弾を見つける")
	check(incidents.bomb.searched.size() == 4, "近い順に4棟を調べて、4棟目で見つかる")
	await wait_until(func(): return not incidents.has_bomb(), 30.0)
	check(logged("爆弾を解体しました"), "見つけた警備員がそのまま解体する")

	# 警備室が2つあると手分けして探す（反対側から来た警備員がすぐ見つける）
	main.select_mode("security")
	main.build_at(Vector2i(22, 17)) # 警備室B（x=22〜23）
	await wait_frames(2)
	main.clock.set_time(2, 10, 0)
	incidents.start_bomb(Vector2i(19, 17))
	incidents.refuse_ransom()
	await wait_frames(2)
	var targets: Array = incidents.bomb.search.values().map(func(job): return job.target)
	check(targets.size() == 2 and targets[0] != targets[1], "警備員2人が別々の棟を調べに行く")
	check(targets.has(Vector2i(19, 17)), "反対側の警備員は、近い爆弾の棟へ向かう")
	await wait_until(func(): return incidents.bomb == null or incidents.bomb.found, 60.0)
	check(incidents.bomb != null and incidents.bomb.searched.size() <= 2, "手分けすると、少ない棟数で見つかる")
	await wait_until(func(): return not incidents.has_bomb(), 30.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	return true

# シナリオ71: 爆発の範囲（爆弾の棟のまわりのテナントも、上下の階ごと吹き飛ぶ）
#   y=16: オフィスD(9〜12)  オフィスE(13〜16)
#   y=17: ショップA(9〜11) 階段(12) ショップB(13〜15)★爆弾 ショップC(16〜18)
#   y=15: オフィスF(9〜12)（2つ上の階なので範囲の外）
# ---------------------------------------------------
func run_blast_scenario() -> bool:
	print("[シナリオ] 爆発の範囲")
	main.clear_world()
	main.funds = 10000000
	var incidents = main.incident_system
	build_support(cells_row(18, 8, 18), "lobby")
	main.select_mode("shop")
	for x in [9, 13, 16]:
		main.build_at(Vector2i(x, 17))
	build_support([Vector2i(12, 17)])
	main.select_mode("office")
	main.build_at(Vector2i(9, 16))
	main.build_at(Vector2i(13, 16))
	main.build_at(Vector2i(9, 15))
	check(main.get_building_type(Vector2i(9, 15)) == "office", "テストの建物がそろう")
	var victims: Array = incidents.blast_units(Vector2i(13, 17))
	victims.sort()
	check(victims == [Vector2i(9, 16), Vector2i(13, 16), Vector2i(13, 17), Vector2i(16, 17)], "吹き飛ぶのは、爆弾の棟と、1マス以内にかかるテナント（上の階・隣・ななめ）")

	focus_camera(Vector2i(13, 16))
	await wait_frames(1)
	incidents.start_bomb(Vector2i(13, 17))
	incidents.bomb.decided = true
	main.ui.hide_ransom_panel()
	incidents.explode()
	check(main.get_building_type(Vector2i(13, 17)) == "ruin", "爆弾のショップは焼け跡になる")
	check(main.get_building_type(Vector2i(16, 17)) == "ruin" and main.get_building_type(Vector2i(18, 17)) == "ruin", "隣のショップも吹き飛ぶ")
	check(main.get_building_type(Vector2i(13, 16)) == "ruin" and main.get_building_type(Vector2i(9, 16)) == "ruin", "上の階のオフィスも吹き飛ぶ（複数階）")
	check(main.get_building_type(Vector2i(9, 17)) == "shop", "離れたショップは無事")
	check(main.get_building_type(Vector2i(9, 15)) == "office", "2つ上の階は範囲の外で無事（焼け跡に支えられて浮かない）")
	check(main.get_building_type(Vector2i(12, 17)) == "stairs" and main.get_building_type(Vector2i(13, 18)) == "lobby", "階段やロビーは吹き飛ばない")
	check(logged("4棟のテナントが吹き飛びました"), "何棟吹き飛んだかがメッセージで出る")
	await capture("blast_01")
	return true

# シナリオ72: VIP専用エレベーター（VIPの来館中は、VIPだけが乗れる）
#   1階: ロビー(8) エレベーターA(9) ロビー(10) エレベーターB(11) ロビー(12〜16)
#   4階: 空きフロア(10) スイート(12〜15)。A・Bとも1階〜4階
# ---------------------------------------------------
func run_vip_elevator_scenario() -> bool:
	print("[シナリオ] VIP専用エレベーター")
	main.clear_world()
	main.funds = 10000000
	var vips = main.vip_system
	var elevators = main.elevator_system
	build_support([Vector2i(8, 18), Vector2i(10, 18)] + cells_row(18, 12, 16), "lobby")
	build_support([Vector2i(9, 18), Vector2i(9, 17), Vector2i(9, 16), Vector2i(9, 15)], "elevator")
	build_support([Vector2i(11, 18), Vector2i(11, 17), Vector2i(11, 16), Vector2i(11, 15)], "elevator")
	for y in [17, 16]:
		build_support([Vector2i(10, y)] + cells_row(y, 12, 15), "frame")
	build_support([Vector2i(10, 15)], "frame")
	main.select_mode("hotel_suite")
	main.build_at(Vector2i(12, 15))
	check(main.get_building_type(Vector2i(12, 15)) == "hotel_suite", "4階にスイートがある")
	focus_camera(Vector2i(11, 16))
	await wait_frames(1)

	# エレベーターAをVIP専用にする
	await choose_mode("vip_only")
	check(main.mode_select.text.begins_with("VIP専用") and main.mode_select.text.ends_with("無料") and main.mode_select.tooltip_text.contains("VIPだけが乗れる"), "建設メニューに「VIP専用」がある")
	await click_cell(Vector2i(9, 18), MOUSE_BUTTON_LEFT)
	check(elevators.is_vip_only(Vector2i(9, 16)), "シャフトをクリックするとVIP専用になる（どの階でも同じシャフト）")
	check(logged("VIP専用にしました"), "設定したことがメッセージで出る")
	check(elevators.get_vip_only_cells().size() == 4, "VIP専用のシャフトには目印が付く")
	await hover_cell(Vector2i(9, 17))
	check(main.hover_label.text.contains("（VIP専用）"), "カーソルを合わせるとVIP専用と出る")

	# VIPが来ていないときは、ふつうに誰でも乗れる
	var can_ride_a := func(vip: bool) -> bool:
		return main.get_moves(Vector2i(9, 18), false, vip).any(func(m): return m.to == Vector2i(9, 15))
	check(can_ride_a.call(false), "VIPが来ていないうちは、ほかの人もVIP専用のエレベーターに乗れる")

	# VIPがスイートへ向かっている間は、VIPだけが乗れる
	vips.invite()
	check(vips.is_arriving(), "VIPが来館してスイートへ向かう")
	check(elevators.is_reserved_for_vip(Vector2i(9, 18)), "VIPが向かっている間、VIP専用のシャフトは空けておく")
	check(not can_ride_a.call(false) and can_ride_a.call(true), "VIPが向かっている間は、VIPだけが乗れる")
	var others: Array[Vector2i] = main.find_path(Vector2i(8, 18), Vector2i(12, 15))
	check(not others.has(Vector2i(9, 15)) and others.has(Vector2i(11, 15)), "ほかの人は、もう1本のエレベーターを使う")
	check(vips.vip.path.has(Vector2i(9, 15)), "VIPはVIP専用のエレベーターに乗る")
	await capture("vip_elevator_01")

	# すでに乗り場で待っていた人も、別のエレベーターへ回る
	var waiter = main.spawn_resident(Vector2i(8, 18))
	vips.vip.go_to(vips.room_origin)
	main.clock.set_process(true)
	set_speed(4.0)
	await wait_until(func(): return vips.state == vips.State.STAYING or not vips.is_visiting(), 30.0)
	check(vips.state == vips.State.STAYING, "VIPはVIP専用のエレベーターでスイートに着く")
	check(not elevators.is_reserved_for_vip(Vector2i(9, 18)), "VIPが着いたら、VIP専用のシャフトはまた誰でも使える")
	check(can_ride_a.call(false), "VIPが着いた後は、ほかの人もまた乗れる")
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	if is_instance_valid(waiter):
		waiter.queue_free()

	# もう一度クリックで解除
	await choose_mode("vip_only")
	await click_cell(Vector2i(9, 15), MOUSE_BUTTON_LEFT)
	check(not elevators.is_vip_only(Vector2i(9, 18)), "もう一度クリックすると解除できる")
	return true

# シナリオ73: オフィスの家賃（安い・普通・高い）
# 家賃で賃料・社員の不満・空室への入居の決まりやすさが変わる。
# ---------------------------------------------------
func run_rent_scenario() -> bool:
	print("[シナリオ] オフィスの家賃")
	var tenants = main.tenant_system
	var economy = main.economy_system
	var office := Vector2i(0, 17) # はじめからある2階のオフィス（x=0〜3）
	focus_camera(Vector2i(2, 16))
	await wait_frames(1)
	check(economy.office_rent(office) == 10000 and tenants.rent_info(office).name == "普通", "家賃ははじめ「普通」（1マス10,000Cr）")

	# 「家賃」でオフィスをクリックするたびに 普通 → 高い → 安い → 普通 と切り替わる
	await choose_mode("rent")
	check(main.mode_select.text.begins_with("家賃") and main.mode_select.text.ends_with("無料") and main.mode_select.tooltip_text.contains("普通 → 高い → 安い"), "建設メニューに「家賃」がある")
	await click_cell(Vector2i(2, 17), MOUSE_BUTTON_LEFT)
	check(tenants.rent_info(office).name == "高い" and economy.office_rent(Vector2i(3, 17)) == 14000, "高い: 賃料が1.4倍（1マス14,000Cr）")
	check(logged("家賃を「高い」（1マス1日 14,000Cr）にしました"), "切り替えたことがメッセージで出る")
	await hover_cell(Vector2i(1, 17))
	check(main.hover_label.text.contains("家賃 高い・14,000Cr/マス"), "カーソルを合わせると家賃が出る")
	check(tenants.rent_info(office).stress == 15.0 and tenants.move_in_chance(office) < 0.5, "高いと、社員の不満が増え、空室に次のテナントが決まりにくい")
	await click_cell(Vector2i(2, 17), MOUSE_BUTTON_LEFT)
	check(tenants.rent_info(office).name == "安い" and economy.office_rent(office) == 7000, "安い: 賃料が0.7倍（1マス7,000Cr）")
	check(tenants.rent_info(office).stress < 0.0 and tenants.rent_info(office).wait_days == 1, "安いと、社員の不満が減り、空室はすぐ入居者を探し始める")
	await click_cell(Vector2i(2, 17), MOUSE_BUTTON_LEFT)
	check(tenants.rent_info(office).name == "普通", "もう一度で「普通」に戻る")
	await click_cell(Vector2i(2, 18), MOUSE_BUTTON_LEFT)
	check(main.last_message == "家賃はオフィスに設定します", "オフィス以外には家賃を設定できない")

	# 家賃が高いと、同じ働き方でも評価のストレスが15高くなる
	await click_cell(Vector2i(2, 17), MOUSE_BUTTON_LEFT) # 高い
	var normal_office := Vector2i(4, 17)
	for cell in main.get_unit_cells(office) + main.get_unit_cells(normal_office):
		main.commute_system.workers[cell].arrived_day = 1
		tenants.day_peak_stress[cell] = 10.0
	main.economy_system.pollution = 0
	tenants.evaluate_day(1)
	check(is_equal_approx(tenants.offices[office].average - tenants.offices[normal_office].average, 15.0), "家賃が高いオフィスは、評価のストレスが15高い")

	# 家賃はセーブに残り、撤去して建て直したオフィスには引き継がない
	var save_path := "user://test_rent.json"
	main.save_system.save_game(save_path)
	tenants.rent_levels.clear()
	main.save_system.load_game(save_path)
	check(tenants.rent_info(office).name == "高い", "家賃の設定はセーブに残る")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	main.funds = 10000000
	main.demolish_at(office)
	check(not tenants.rent_levels.has(office), "撤去すると、そのオフィスの家賃の設定は消える")
	return true

# シナリオ74: ゴキブリと掃除・店（掃除されない客室に出て、掃除すると消える。店では客が減る）
#   2階: シングル(9〜10) 飲食店A(11〜13) 飲食店B(14〜16) ショップ(17〜19)
# ---------------------------------------------------
func run_roach_rooms_scenario() -> bool:
	print("[シナリオ] ゴキブリと掃除・店")
	main.clear_world()
	main.funds = 10000000
	var incidents = main.incident_system
	var hotel = main.hotel_system
	var visitors = main.visitor_system
	build_support(cells_row(18, 8, 21), "lobby")
	build_support([Vector2i(22, 18)]) # 2階へ上がる階段（外から来るお客さん用）
	build_support([Vector2i(22, 17)], "frame")
	main.select_mode("hotel")
	main.build_at(Vector2i(9, 17))
	main.select_mode("restaurant")
	main.build_at(Vector2i(11, 17))
	main.build_at(Vector2i(14, 17))
	main.select_mode("shop")
	main.build_at(Vector2i(17, 17))
	var room := Vector2i(9, 17)
	focus_camera(Vector2i(13, 17))
	await wait_frames(1)

	# チェックアウトのあと掃除されないまま1日たつと、その客室にゴキブリが出る
	hotel.rooms[room].state = hotel.RoomState.DIRTY
	hotel.rooms[room].dirty_day = 1
	incidents.update_roaches(1)
	check(not incidents.roaches.has(room), "チェックアウトした日のうちは、まだ出ない")
	incidents.update_roaches(2)
	check(incidents.roaches.has(room), "掃除されないまま1日たった客室にゴキブリが出る")
	check(main.economy_system.pollution == 0, "（ビル全体の衛生が悪くなくても出る）")
	check(logged("掃除されないまま放っておかれた客室 1室に、ゴキブリが出ました"), "発生がメッセージで出る")
	await hover_cell(room)
	check(main.hover_label.text.contains("ゴキブリ発生中・掃除すると消える"), "カーソルを合わせると、掃除すれば消えると出る")
	incidents.update_roaches(3)
	check(incidents.roaches.has(room), "ビルがきれいでも、掃除されるまでは残る")
	await capture("roach_rooms_01")

	# ハウスキーパーが掃除すると消える
	main.select_mode("housekeeping")
	main.build_at(Vector2i(20, 17))
	main.clock.set_time(3, 9, 0)
	main.clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return hotel.rooms[room].state == hotel.RoomState.CLEAN, 40.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(hotel.rooms[room].state == hotel.RoomState.CLEAN, "ハウスキーパーが客室を掃除する")
	check(not incidents.roaches.has(room), "掃除すると、その客室のゴキブリは消える")

	# ゴキブリのいる店は、外から来る客が減る
	var shop := Vector2i(17, 17)
	var count_visits := func() -> int:
		visitors.visits.clear()
		visitors.plan_shop_visits(6, 10 * 60, 17 * 60) # 6日目は土曜（休日）
		return visitors.visits.filter(func(v): return main.get_unit_cells(shop).has(v.seat)).size()
	var clean_count: int = count_visits.call()
	incidents.roaches[shop] = true
	var dirty_count: int = count_visits.call()
	visitors.visits.clear()
	check(clean_count > 0 and dirty_count == int(clean_count * incidents.ROACH_CUSTOMER_RATE), "ゴキブリのいるショップは、外から来る客が半分になる（%d人 → %d人）" % [clean_count, dirty_count])
	await hover_cell(shop)
	check(main.hover_label.text.contains("ゴキブリ発生中・客が減っている"), "カーソルを合わせると、客が減っていると出る")

	# 社員は、ゴキブリのいる飲食店を避けて、ほかの店へ行く
	var near := Vector2i(11, 17)
	check(main.commerce_system.find_nearest_restaurant(Vector2i(9, 17)) == near, "ふだんは一番近い飲食店Aへ行く")
	incidents.roaches[near] = true
	check(main.commerce_system.find_nearest_restaurant(Vector2i(9, 17)) == Vector2i(14, 17), "ゴキブリのいる飲食店Aは避けて、飲食店Bへ行く")
	incidents.roaches[Vector2i(14, 17)] = true
	check(main.commerce_system.find_nearest_restaurant(Vector2i(9, 17)) == near, "どの店にもいるなら、しかたなく一番近い店へ行く")
	return true

# シナリオ75: コードレビューで直した不具合
#   2階: 警備室(10〜11) ハウスキーパー室(12〜13) スイート(14〜17) ショップ(18〜20、上に空きフロア)
# ---------------------------------------------------
func run_review_fixes_scenario() -> bool:
	print("[シナリオ] コードレビューで直した不具合")
	main.clear_world()
	main.funds = 10000000
	main.rating_system.stars = 1 # 火災・爆破予告が勝手に起きないように
	main.economy_system.pollution = 0
	main.clock.set_time(1, 12, 0)
	var incidents = main.incident_system
	var hotel = main.hotel_system
	var vips = main.vip_system
	var tenants = main.tenant_system
	build_support([Vector2i(8, 18)] + cells_row(18, 10, 20), "lobby")
	build_support([Vector2i(9, 18)]) # 2階へ上がる階段
	main.select_mode("security")
	main.build_at(Vector2i(10, 17))
	main.select_mode("housekeeping")
	main.build_at(Vector2i(12, 17))
	main.select_mode("hotel_suite")
	main.build_at(Vector2i(14, 17))
	main.select_mode("shop")
	main.build_at(Vector2i(18, 17))
	build_support([Vector2i(18, 16)], "frame") # ショップの上に空きフロア（撤去すると空きフロアが残る）
	focus_camera(Vector2i(14, 17))
	await wait_frames(2)

	# 常駐の警備員・清掃員がいなくなっても（乗っていたエレベーターの撤去など）、代わりが来る
	var home := Vector2i(10, 17)
	var guard = incidents.guards[home].resident
	var keeper = hotel.housekeepers[Vector2i(12, 17)].resident
	guard.queue_free()
	keeper.queue_free()
	await wait_frames(2)
	check(is_instance_valid(incidents.guards[home].resident) and incidents.guards[home].resident != guard, "いなくなった警備員の代わりが警備室に来る")
	check(is_instance_valid(hotel.housekeepers[Vector2i(12, 17)].resident) and hotel.housekeepers[Vector2i(12, 17)].resident != keeper, "いなくなった清掃員の代わりがハウスキーパー室に来る")

	# 燃えているテナントを撤去して空きフロアが残っても、空きフロアは燃えない
	incidents.start_fire(Vector2i(19, 17))
	main.demolish_at(Vector2i(18, 17))
	check(main.get_building_type(Vector2i(19, 17)) == "frame", "燃えているショップを撤去すると空きフロアが残る")
	await wait_frames(2)
	check(not incidents.has_fire() and logged("火は収まりました"), "空きフロアに火は残らず、鎮火する")
	check(main.get_building_type(Vector2i(19, 17)) == "frame", "空きフロアは焼け跡にならない")
	main.select_mode("shop")
	main.build_at(Vector2i(18, 17))

	# 火を消し止めた警備員は、警備室へ戻る
	main.clock.set_process(true)
	incidents.start_fire(Vector2i(18, 17))
	set_speed(16.0)
	await wait_until(func(): return not incidents.has_fire(), 60.0)
	check(logged("火を消し止めました"), "警備員が火を消し止める")
	guard = incidents.guards[home].resident
	await wait_until(func(): return guard.cell == home and not guard.is_moving(), 30.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(guard.cell == home, "鎮火すると、警備員は警備室へ戻る")

	# VIPの宿泊中にスイートがなくなっても、合格にはならない
	var suite := Vector2i(14, 17)
	vips.passed = false
	vips.vip = main.spawn_resident(suite)
	vips.room_origin = suite
	vips.state = vips.State.STAYING
	hotel.rooms[suite].state = hotel.RoomState.OCCUPIED
	hotel.rooms[suite].guests = [vips.vip]
	tenants.rooms[suite] = {"rating": tenants.Rating.BAD, "average": 80.0}
	main.demolish_at(suite)
	await wait_frames(2)
	check(vips.state == vips.State.NONE and not vips.passed, "宿泊中のスイートを撤去すると、VIPは合格にならずに帰る")
	check(logged("泊まっていたスイートがなくなり"), "スイートがなくなって帰ったことがメッセージで出る")
	check(not tenants.rooms.has(suite), "撤去した客室の評価は消える（跡地や建て直した部屋に残らない）")

	# 掃除されていない客室が、いつから汚れているかはセーブに残る（読み込んだ後もゴキブリが出る）
	main.select_mode("hotel")
	main.build_at(suite)
	main.clock.set_time(5, 12, 0)
	hotel.rooms[suite].state = hotel.RoomState.DIRTY
	hotel.rooms[suite].dirty_day = 3
	var save_path := "user://test_review_fixes.json"
	main.save_system.save_game(save_path)
	main.save_system.load_game(save_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	check(hotel.rooms[suite].get("dirty_day", -1) == 3, "客室が汚れた日はセーブに残る")
	incidents.infest_dirty_rooms(5)
	check(incidents.roaches.has(suite), "読み込んだ後も、掃除されないまま日がたった客室にはゴキブリが出る")
	return true

# シナリオ76: ビルの入口（1階の左右の出入り口・地下鉄駅・地下駐車場の4種類）
#   共通のビル（1階のロビー x=-8〜7）の右隣 x=8 にエレベーターを通し、
#   地下1階（y=19）にスロープ(0〜1)・駐車場(2〜5)・空きフロア(6〜7)を置く。
# ---------------------------------------------------
func run_entrances_scenario() -> bool:
	print("[シナリオ] ビルの入口")
	main.funds = 10000000
	check(main.get_ground_entrances() == [Vector2i(-8, 18), Vector2i(7, 18)], "1階のロビーの左端と右端が出入り口になる")
	check(main.get_entrance() == Vector2i(-8, 18) and main.get_right_entrance() == Vector2i(7, 18), "左の出入り口と右の出入り口")
	check(main.is_entrance(Vector2i(7, 18)), "右端から人が出入りできる")
	main.select_mode("elevator")
	for y in range(19, 14, -1):
		main.build_at(Vector2i(8, y))
	check(main.get_right_entrance() == Vector2i(8, 18), "ロビーの右端にエレベーターがあれば、右の出入り口はその隣（フロアの端）")
	check(main.nearest_entrance(Vector2i(5, 17)) == Vector2i(8, 18), "右寄りのオフィスの社員は、近い右の出入り口を使う")
	var lights: Array[Vector2] = main.lighting.get_entrance_lights()
	check(lights.size() == 2 and lights[1].x > lights[0].x, "夜は左右の出入り口に照明が灯る")
	focus_camera(Vector2i(4, 17))
	await wait_frames(2)
	await capture("entrances_01_right")

	# 地下駐車場も入口になる（車で下りてこられる駐車場だけ）
	main.select_mode("ramp")
	main.build_at(Vector2i(0, 19))
	main.select_mode("parking")
	main.build_at(Vector2i(2, 19))
	build_support(cells_row(19, 6, 7), "frame")
	check(main.parking_system.usable_units == [Vector2i(2, 19)], "スロープにつながった駐車場は使える")
	check(main.get_entrances() == [Vector2i(-8, 18), Vector2i(8, 18), Vector2i(2, 19)], "入口は1階の左右の出入り口と地下駐車場")
	check(main.nearest_entrance(Vector2i(4, 19)) == Vector2i(2, 19), "駐車場の近くからは、駐車場が一番近い入口")
	check(main.lighting.get_entrance_lights().size() == 2, "駐車場には扉がないので、入口の照明は付けない")
	main.select_mode("parking")
	main.build_at(Vector2i(-6, 19)) # 同じ地下1階の2つ目の駐車場（真上はロビー）
	build_support(cells_row(19, -2, -1), "frame")
	check(main.parking_system.usable_units.size() == 2 and main.get_entrances().filter(func(c): return c.y == 19).size() == 1, "同じ階の駐車場は、入口としては1つに数える（経路探索を増やさない）")
	main.demolish_at(Vector2i(-6, 19))
	main.demolish_at(Vector2i(0, 19))
	check(main.parking_system.usable_units.is_empty() and not main.get_entrances().has(Vector2i(2, 19)), "スロープがないと車が来られないので、駐車場は入口にならない")

	# ロビーが1マスだけなら、出入り口は1つ
	main.clear_world()
	main.select_mode("lobby")
	main.build_at(Vector2i(0, 18))
	check(main.get_ground_entrances() == [Vector2i(0, 18)], "ロビーが1マスだけなら、出入り口は1つ")
	check(main.lighting.get_entrance_lights().size() == 1, "照明も1つ")
	return true

# シナリオ77: 空のイベント（ゲームには関係しない、背景の飛行機・鳥・気球・虹・流れ星・ロケット・UFO・花火）
# ---------------------------------------------------
func run_sky_events_scenario() -> bool:
	print("[シナリオ] 空のイベント")
	var sky = main.sky_events
	var weather = main.weather_system
	var clock = main.clock
	var kinds := func(day: int) -> Array:
		return sky.events_for(day).map(func(e): return e.kind)
	# その日の条件に合う日を探す（1年のうちで最初の日。なければ -1）
	var find_day := func(condition: Callable) -> int:
		for d in range(2, 366):
			if condition.call(d):
				return d
		return -1
	var sunny: int = find_day.call(func(d): return weather.weather_for(d) == weather.Weather.SUNNY and weather.weather_for(d - 1) != weather.Weather.RAINY)
	var rainy: int = find_day.call(func(d): return weather.weather_for(d) == weather.Weather.RAINY)
	var after_rain: int = find_day.call(func(d): return weather.weather_for(d - 1) == weather.Weather.RAINY and weather.weather_for(d) != weather.Weather.RAINY)
	var summer_holiday: int = find_day.call(func(d): return clock.date(d)[0] == 7 and clock.is_holiday(d) and weather.weather_for(d) != weather.Weather.RAINY)
	var june_holiday: int = find_day.call(func(d): return clock.date(d)[0] == 6 and clock.is_holiday(d) and weather.weather_for(d) != weather.Weather.RAINY)
	var rocket_day: int = find_day.call(func(d): return kinds.call(d).has("rocket"))
	var ufo_day: int = find_day.call(func(d): return kinds.call(d).has("ufo"))
	var balloon_day: int = find_day.call(func(d): return kinds.call(d).has("balloon"))
	check(sunny > 0 and rainy > 0 and after_rain > 0 and summer_holiday > 0 and june_holiday > 0, "晴れ・雨・雨上がり・夏の休日・6月の休日の日がある")

	# 予定は日付から決まる（同じ日なら同じ）
	check(sky.events_for(sunny) == sky.events_for(sunny), "同じ日なら、同じ空のイベントが起きる")
	var planes: Array = sky.events_for(sunny).filter(func(e): return e.kind == "airplane")
	check(planes.size() >= sky.AIRPLANES[0] and planes.size() <= sky.AIRPLANES[1], "晴れた日には飛行機が%d機飛ぶ" % planes.size())
	check(planes.all(func(e): return e.start >= sky.DAY_FROM and e.start + e.length <= sky.DAY_TO), "飛行機が飛ぶのは昼だけ")
	check(kinds.call(sunny).has("birds") and kinds.call(sunny).has("shooting_star"), "晴れた日は、昼に鳥の群れ・夜に流れ星が見える")
	var stars: Array = sky.events_for(sunny).filter(func(e): return e.kind == "shooting_star")
	check(stars.all(func(e): return e.start >= sky.NIGHT_FROM), "流れ星は夜だけ")
	check(not kinds.call(rainy).has("airplane") and not kinds.call(rainy).has("birds") and not kinds.call(rainy).has("shooting_star"), "雨の日は飛行機も鳥も流れ星も見えない")
	check(kinds.call(after_rain).has("rainbow") and not kinds.call(sunny).has("rainbow"), "雨の次の日の朝だけ、虹がかかる")
	check(kinds.call(summer_holiday).has("firework") and not kinds.call(june_holiday).has("firework"), "花火は夏（7・8月）の休日の夜だけ")
	check(rocket_day > 0 and ufo_day > 0 and balloon_day > 0, "ときどきロケット・UFO・気球が見られる（ロケット%d日目・UFO%d日目・気球%d日目）" % [rocket_day, ufo_day, balloon_day])

	# 起きている間だけ描かれる（見た目を撮っておく）
	focus_camera(Vector2i(0, 6))
	var shots := [
		["airplane", sunny, planes[0].start + planes[0].length * 0.5],
		["birds", sunny, sky.events_for(sunny).filter(func(e): return e.kind == "birds")[0].start + sky.BIRD_MINUTES * 0.5],
		["rainbow", after_rain, 8 * 60 + 30],
		["shooting_star", sunny, stars[0].start + 0.8],
		["rocket", rocket_day, sky.events_for(rocket_day).filter(func(e): return e.kind == "rocket")[0].start + sky.ROCKET_MINUTES * 0.5],
		["ufo", ufo_day, sky.events_for(ufo_day).filter(func(e): return e.kind == "ufo")[0].start + sky.UFO_MINUTES * 0.4],
		["balloon", balloon_day, sky.events_for(balloon_day).filter(func(e): return e.kind == "balloon")[0].start + sky.BALLOON_MINUTES * 0.3],
		["firework", summer_holiday, sky.FIREWORKS_FROM + 10],
	]
	for shot in shots:
		var minute: float = shot[2]
		var day: int = shot[1]
		if minute >= 24 * 60: # 夜中の0時を過ぎたら、次の日の続き
			minute -= 24 * 60
			day += 1
		clock.day = day
		clock.minute = minute
		await wait_frames(2)
		check(sky.is_active(shot[0]), "%s が空に出ている（%d日目 %d:%02d）" % [shot[0], day, int(minute) / 60, int(minute) % 60])
		await capture("sky_%s" % shot[0])
	clock.day = sunny
	clock.minute = 3 * 60 # 夜中の3時: 昼のイベントは出ていない
	check(not sky.is_active("airplane") and not sky.is_active("birds") and not sky.is_active("rainbow"), "夜中には昼のイベントは出ない")
	return true

# シナリオ78: セーブの枠（3つ）とオートセーブ（毎日の決算のあと）
# ---------------------------------------------------
func run_save_slots_scenario() -> bool:
	print("[シナリオ] セーブの枠とオートセーブ")
	var saves = main.save_system
	var ui = main.ui
	check(saves.slot_path(1).begins_with(TEST_SAVE_DIR), "テストのセーブは、遊んでいるセーブデータとは別のフォルダに書く")
	if not saves.slot_path(1).begins_with(TEST_SAVE_DIR):
		return true # 遊んでいるセーブデータを上書きしないよう、ここでやめる
	for slot in range(0, saves.SLOT_COUNT + 1): # 前に流したテストの残りを消しておく
		remove_test_save(saves.slot_path(slot))
	check(not saves.has_save() and saves.slot_info(2).is_empty(), "はじめはどの枠も空き")

	# ⌘S で保存する枠を選ぶ画面が開く（枠1〜3）
	await press_shortcut(KEY_S)
	check(ui.save_panel.visible and ui.save_mode == "save", "⌘Sで、保存する枠を選ぶ画面が開く")
	await wait_frames(1)
	var rows: Array = ui.save_rows.get_children()
	check(rows.size() == 3 and rows[1].text.begins_with("枠2: （空き）"), "枠は3つで、空いている枠は「空き」と出る")
	await capture("save_01_slots")
	main.funds = 12340000
	rows[1].pressed.emit() # 枠2に保存する
	check(not ui.save_panel.visible and FileAccess.file_exists(saves.slot_path(2)), "枠を選ぶと、その枠に保存して画面が閉じる")
	check(logged("枠2にセーブしました"), "どの枠に保存したかがメッセージで出る")
	var info: Dictionary = saves.slot_info(2)
	check(info.funds == 12340000 and info.day == main.clock.day and info.saved_at != "", "枠の中身（日付・資金・保存した日時）を読める")

	# ⌘O で読み込む枠を選ぶ（オートセーブと枠1〜3。空の枠は押せない）
	main.funds = 1
	await press_shortcut(KEY_O)
	await wait_frames(1)
	rows = ui.save_rows.get_children()
	check(ui.save_mode == "load" and rows.size() == 4 and rows[0].text.begins_with("オートセーブ"), "⌘Oで、読み込む枠を選ぶ画面が開く（一番上はオートセーブ）")
	check(rows[0].disabled and not rows[2].disabled and rows[2].text.contains("資金 12,340,000Cr"), "空の枠は押せず、保存した枠には資金などが出る")
	await capture("save_02_load")
	rows[2].pressed.emit()
	check(main.funds == 12340000 and not ui.save_panel.visible, "枠2を読み込むと、保存したときの資金に戻る")
	await press_shortcut(KEY_O)
	await press_key(KEY_ESCAPE)
	check(not ui.save_panel.visible, "Escで枠を選ぶ画面を閉じる")

	# 毎日の決算のあとに、オートセーブの枠へ黙って保存する（決算のメッセージはそのまま）
	main.economy_system.settle(main.clock.day)
	check(FileAccess.file_exists(saves.slot_path(0)) and saves.slot_info(0).funds == main.funds, "決算のあとに、オートセーブの枠へ自動で保存する")
	check(main.last_message.contains("の決算"), "オートセーブしても、決算のメッセージは消えない")
	remove_test_save(saves.slot_path(0))
	saves.autosave_enabled = false
	main.economy_system.settle(main.clock.day)
	check(not FileAccess.file_exists(saves.slot_path(0)), "オートセーブを止めると保存しない（READMEの画像づくりで使う）")
	saves.autosave_enabled = true
	for slot in range(0, saves.SLOT_COUNT + 1):
		remove_test_save(saves.slot_path(slot))
	return true

# シナリオ80: 展望台（屋上のランドマーク。観光客が来て入場料が入る）と★5・最終目標（タワー完成）
#   共通のビル（2〜4階にオフィス。4階が一番上）の屋上 y=14 に展望台（x=2〜7）を建て、x=8 のエレベーターで上がる
# ---------------------------------------------------
func run_observatory_scenario() -> bool:
	print("[シナリオ] 展望台と★5")
	main.funds = 10000000
	var visitors = main.visitor_system
	main.select_mode("elevator")
	for y in range(18, 13, -1):
		main.build_at(Vector2i(8, y))
	await choose_mode("observatory")
	check(main.mode_select.text.begins_with("展望台") and main.mode_select.text.ends_with("3,000,000Cr"), "建設メニューに展望台（300万Cr）がある")
	main.funds = 10000000
	main.build_at(Vector2i(2, 16))
	check(main.get_building_type(Vector2i(2, 16)) == "office", "屋上でないところ（オフィスのある3階）には建てられない")
	var deck := Vector2i(2, 14)
	main.build_at(deck)
	check(main.get_building_type(deck) == "observatory" and main.get_unit_cells(deck).size() == 6, "屋上に横6マスの展望台を建てられる")
	check(main.funds == 10000000 - 3000000, "建設費300万Crがかかる")
	focus_camera(Vector2i(4, 14))
	await wait_frames(2)
	await capture("observatory_01_built")

	# 観光客が入口から屋上まで上がってきて、入場料を払う（入場料は決算の「展望台」に入る）
	main.clock.set_time(1, 10, 59)
	main.clock.set_process(true)
	set_speed(8.0)
	await wait_until(func(): return visitors.plan_day == 1, 10.0)
	var tourists: Array = visitors.visits.filter(func(v): return v.type == "observatory")
	check(tourists.size() > 0 and tourists[0].color == visitors.SHOP_TYPES.observatory.color, "展望台に観光客（水色）が来る予定が立つ（%d人）" % tourists.size())
	await wait_until(func(): return visitors.observatory_revenue_by_day.get(1, 0) > 0, 60.0)
	check(visitors.observatory_revenue_by_day.get(1, 0) % visitors.SHOP_TYPES.observatory.price == 0 and visitors.observatory_revenue_by_day.get(1, 0) > 0, "観光客が入場料（1人%s）を払う" % main.money_text(visitors.SHOP_TYPES.observatory.price))
	await hover_cell(deck + Vector2i(2, 0))
	check(main.hover_label.text.contains("展望台（観光客"), "カーソルを合わせると観光客の数と入場料が出る")
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	main.economy_system.settle(1)
	check(main.economy_system.last_report.observatory > 0 and logged("展望台 +"), "決算に展望台の入場料が入る")

	# ★5の条件: 人口500・展望台・結婚式場
	var rating = main.rating_system
	check(rating.MAX_STARS == 5, "★は5つまで")
	rating.stars = 4
	var missing: Array[String] = rating.missing_for_next()
	check(missing.has("人口500") and missing.has("結婚式場") and not missing.has("展望台"), "★5には人口500・展望台・結婚式場が必要（展望台はもうある）")
	# 不満なテナント（評価が「悪い」か、退去しそうなオフィス・住宅）が1割を超えていると、★5に上がれない
	var tenants = main.tenant_system
	var office_origins: Array[Vector2i] = main.find_office_units()
	for origin in office_origins:
		tenants.offices[origin] = tenants.new_tenant()
	check(rating.unhappy_rate() == 0.0 and not rating.missing_for_next().any(func(m): return m.begins_with("不満なテナント")), "不満なテナントがいなければ、満足度の条件は満たしている")
	tenants.offices[office_origins[0]].rating = tenants.Rating.BAD
	tenants.offices[office_origins[1]].bad_days = tenants.LEAVE_AFTER_BAD_DAYS - 1 # 退去しそう
	tenants.offices[office_origins[2]].vacant = true # 空室は数えない
	var expected := 2.0 / (office_origins.size() - 1)
	check(is_equal_approx(rating.unhappy_rate(), expected), "不満なテナントの割合は、入居しているオフィス・住宅のうち、悪い評価か退去しそうなもの（%d%%）" % int(round(expected * 100)))
	check(rating.missing_for_next().has("不満なテナント1割以下（今%d%%）" % int(round(expected * 100))), "不満なテナントが1割を超えていると、★5の条件に足りないものとして出る")
	for origin in office_origins:
		tenants.offices[origin] = tenants.new_tenant()
	await wait_frames(2)
	check(main.stats_button.text.begins_with("★★★★☆"), "★は5つの星で見せる（★4なら ★★★★☆）")

	# 最後の目標（180日目までに★5）を達成すると、タワー完成
	var goals = main.goal_system
	goals.index = goals.GOALS.size() - 1
	check(goals.current().stars == 5 and goals.current().day == 180, "最後の目標は180日目までに★5")
	rating.stars = 5
	goals.check_day(main.clock.day)
	check(goals.cleared and main.goal_panel.visible and main.goal_title.text == "タワー完成！", "★5になると「タワー完成！」の画面が出る")
	await capture("observatory_02_complete")
	main.goal_panel.visible = false
	return true

# シナリオ81: 色分け表示（Vキーで ストレス → 騒音 → エレベーター待ち → 消す）
#   共通のビルに、右端 x=8 のエレベーターと、2階の飲食店（うるさい）を足して試す
# ---------------------------------------------------
func run_overlay_scenario() -> bool:
	print("[シナリオ] 色分け表示")
	main.funds = 10000000
	var overlay = main.grid_overlay
	var tenants = main.tenant_system
	main.select_mode("elevator")
	for y in range(18, 14, -1):
		main.build_at(Vector2i(8, y))
	build_support(cells_row(18, 9, 12), "lobby")
	main.select_mode("restaurant")
	main.build_at(Vector2i(9, 17))
	focus_camera(Vector2i(2, 16))
	check(main.overlay == "" and not main.ui.overlay_panel.visible, "はじめは色分けを出していない")

	# ストレス: テナントの評価で塗る（良い=緑・普通=黄・悪い=赤・空室=灰色）
	await press_key(KEY_V)
	check(main.overlay == "stress" and main.ui.overlay_panel.visible and main.ui.overlay_label.text.contains("ストレス"), "Vでストレスの色分けになり、凡例が出る")
	var bad := Vector2i(-8, 17)
	var vacant := Vector2i(-4, 17)
	tenants.offices[bad] = tenants.new_tenant()
	tenants.offices[bad].rating = tenants.Rating.BAD
	tenants.offices[vacant] = tenants.new_tenant()
	tenants.offices[vacant].vacant = true
	tenants.offices[Vector2i(0, 17)] = tenants.new_tenant()
	var heat: Dictionary = overlay.heat_cells()
	check(heat.get(bad + Vector2i(3, 0)) == overlay.HEAT_BAD, "評価が悪いオフィスは、どのマスも赤")
	check(heat.get(vacant) == overlay.HEAT_VACANT and heat.get(Vector2i(0, 17)) == overlay.HEAT_GOOD, "空室は灰色、評価が良いオフィスは緑")
	await wait_frames(2)
	await capture("overlay_01_stress")

	# 騒音: うるさいマスほど濃い赤
	await press_key(KEY_V)
	check(main.overlay == "noise" and main.ui.overlay_label.text.contains("騒音"), "もう一度Vで騒音の色分けになる")
	heat = overlay.heat_cells()
	var noise = main.noise_system
	var loud := Vector2i(10, 17) # 飲食店の中
	check(heat.has(loud) and noise.get_noise(loud) > 0, "騒音のあるマスが塗られる（飲食店のまわり）")
	var quiet_cell: Vector2i = noise.noise_map.keys().reduce(func(a, b): return a if noise.noise_map[a] <= noise.noise_map[b] else b)
	check(heat[loud].a >= heat[quiet_cell].a, "うるさいマスほど濃く塗る")
	await wait_frames(2)
	await capture("overlay_02_noise")

	# エレベーター待ち: 待っている人が多い乗り場ほど赤く、人数も出す
	await press_key(KEY_V)
	check(main.overlay == "wait" and main.ui.overlay_label.text.contains("エレベーター待ち"), "もう一度Vでエレベーター待ちの色分けになる")
	var hall := Vector2i(8, 18)
	var waiting: Array = []
	for i in overlay.WAIT_BUSY: # 乗り場で待っている人を置く（すぐに数えて、次のフレームまでに戻す）
		var r = main.spawn_resident(hall)
		r.state = r.State.WAITING
		waiting.append(r)
	check(overlay.waiting_counts().get(hall) == overlay.WAIT_BUSY, "乗り場で待っている人の数を数える（%d人）" % overlay.WAIT_BUSY)
	check(overlay.heat_cells().get(hall).is_equal_approx(Color(1.0, 0.55, 0.15, 0.55)), "%d人以上待っている乗り場は橙" % overlay.WAIT_BUSY)
	for r in waiting:
		r.state = r.State.WALKING # 行き先のない「待っている人」のまま動かすとエラーになるので、戻してから消す
		r.queue_free()

	# もう一度Vで消える。メニューからも選べる（もう一度選ぶと消える）
	await press_key(KEY_V)
	check(main.overlay == "" and not main.ui.overlay_panel.visible and overlay.heat_cells().is_empty(), "もう一度Vで色分けが消える")
	main.ui.do_menu_action("overlay_noise")
	check(main.overlay == "noise" and main.ui.is_menu_on("overlay_noise"), "メニューからも騒音の色分けを出せる（チェックが付く）")
	main.ui.do_menu_action("overlay_noise")
	check(main.overlay == "", "出している色分けをもう一度選ぶと消える")
	return true

# シナリオ82: テナントからの頼みごと（3日以内にかなえるとお礼、かなえられないと評価の悪い日が増える）
#   共通のビル（2〜4階にオフィス）に x=8 のエレベーターを通して試す
# ---------------------------------------------------
func run_request_scenario() -> bool:
	print("[シナリオ] テナントからの頼みごと")
	main.funds = 10000000
	var requests = main.request_system
	var tenants = main.tenant_system
	main.select_mode("elevator")
	for y in range(18, 14, -1):
		main.build_at(Vector2i(8, y))
	var office := Vector2i(4, 16) # 3階のオフィス
	for origin in main.find_office_units():
		tenants.offices[origin] = tenants.new_tenant()
	tenants.offices[office].rating = tenants.Rating.NORMAL

	# 困りごとから頼みの候補を選ぶ（評価が良くないオフィス・近くに飲食店がないオフィス）
	var candidates: Array = requests.candidates()
	check(candidates.has(["rating", office, "offices"]), "評価が「良い」でないオフィスは、評価を良くしてほしいと頼める")
	check(candidates.any(func(c): return c[0] == "restaurant"), "近くに飲食店がないオフィスは、飲食店がほしいと頼める")
	check(not candidates.any(func(c): return c[0] == "garden"), "★1のうちは、屋上庭園の頼みは出ない")
	var days := 0
	for day in range(2, 102):
		if requests.roll(day):
			days += 1
	check(days > 15 and days < 55, "頼みごとはときどき届く（100日のうち%d日）" % days)

	# 飲食店の頼み: 近くに飲食店を建てれば、次の決算でお礼が入る
	main.clock.set_time(3, 9, 0)
	requests.start("restaurant", office, "offices", 3)
	check(logged("3階のオフィスから頼みごと") and requests.days_left() == 3, "頼みごとがメッセージで届く（3日以内）")
	await wait_frames(2)
	check(main.stats_label.text.contains("頼みごと: 3階のオフィス「近くに飲食店がほしい」（あと3日"), "ビルの状況に頼みごとが出る")
	check(main.stats_button.text.contains("⚠"), "頼みごとがあると★の横に⚠が付く")
	focus_camera(Vector2i(4, 16))
	await wait_frames(1)
	await hover_cell(office + Vector2i(1, 0))
	check(main.hover_label.text.contains("頼みごと:「近くに飲食店がほしい」あと3日"), "頼んでいるテナントにカーソルを合わせると頼みごとが出る")
	await capture("request_01_bubble")
	build_support(cells_row(18, 9, 12), "lobby")
	main.select_mode("restaurant")
	main.build_at(Vector2i(9, 17)) # 2階の飲食店（3階から1階下）
	var funds_before: int = main.funds
	requests.check_day(3)
	check(requests.request == null and main.funds == funds_before + requests.KINDS.restaurant.reward, "かなえると、お礼（%s）が入る" % main.money_text(requests.KINDS.restaurant.reward))
	check(logged("頼みごとをかなえました！"), "かなえたことがメッセージで出る")

	# 評価の頼み: 3日以内に「良い」にならなければ、評価の悪い日が1日増える
	requests.start("rating", office, "offices", 4)
	requests.check_day(4)
	requests.check_day(5)
	check(requests.request != null, "期限までは待ってくれる")
	requests.check_day(6)
	check(requests.request == null and tenants.offices[office].bad_days == 1, "3日以内にかなえられないと、評価の悪い日が1日増える")
	check(logged("がっかりしています"), "かなえられなかったことがメッセージで出る")

	# 頼んだテナントがいなくなったら、頼みは取り下げられる
	requests.start("rating", office, "offices", 7)
	main.demolish_at(office)
	main.select_mode("hotel_twin")
	main.build_at(office) # 同じ場所に別の建物を建てても、決算まで吹き出しや説明は出さない
	check(not requests.is_requester_here() and requests.get_cell_text(office) == "", "撤去して建て直した建物には、頼みごとの吹き出しや説明を出さない")
	requests.check_day(7)
	check(requests.request == null and logged("頼みごと「評価を良くしてほしい」は取り下げられました"), "頼んだテナントを撤去すると、頼みは取り下げられる")
	return true

# シナリオ83: 季節のにぎわい（お正月・ゴールデンウィーク・お盆休み・クリスマスは、外から来るお客さんが増える）
#   2階のショップ（x=9〜11）で、ふだんの平日とゴールデンウィークの平日の客の数を比べる
# ---------------------------------------------------
func run_season_scenario() -> bool:
	print("[シナリオ] 季節のにぎわい")
	main.funds = 10000000
	var visitors = main.visitor_system
	var clock = main.clock
	var weather = main.weather_system
	build_support([Vector2i(8, 18)] + cells_row(18, 10, 14), "lobby")
	build_support([Vector2i(9, 18)])
	main.select_mode("shop")
	main.build_at(Vector2i(9, 17))
	var find_day := func(condition: Callable) -> int:
		for d in range(1, 366):
			if condition.call(d):
				return d
		return -1
	var new_year: int = find_day.call(func(d): return clock.date(d) == [1, 1])
	var gw: int = find_day.call(func(d): return clock.date(d)[0] in [4, 5] and not visitors.season(d).is_empty() and not clock.is_holiday(d) and weather.weather_for(d) != weather.Weather.RAINY)
	var normal: int = find_day.call(func(d): return visitors.season(d).is_empty() and not clock.is_holiday(d) and weather.weather_for(d) != weather.Weather.RAINY)
	check(visitors.season(new_year).name == "お正月" and visitors.season_rate(new_year) == 2.0, "お正月（1月1日〜3日）はお客さんが2倍")
	check(visitors.season(gw).name == "ゴールデンウィーク" and visitors.season_rate(gw) == 1.5, "ゴールデンウィークは1.5倍（%s）" % clock.date_text(gw))
	check(visitors.season(find_day.call(func(d): return clock.date(d) == [12, 24])).name == "クリスマス", "12月24日はクリスマスのにぎわい")
	check(visitors.season(find_day.call(func(d): return clock.date(d) == [8, 12])).name == "お盆休み", "8月12日はお盆休みのにぎわい")
	check(visitors.season_rate(normal) == 1.0, "ふだんの日は1倍")

	# ゴールデンウィークの平日は、ふだんの平日よりショップのお客さんが多い
	var count_shop_visits := func(day: int) -> int:
		visitors.visits.clear()
		visitors.plan_shop_visits(day, visitors.WEEKDAY_START, visitors.WEEKDAY_END)
		return visitors.visits.filter(func(v): return v.type == "shop").size()
	clock.day = normal
	var usual: int = count_shop_visits.call(normal)
	clock.day = gw
	var busy: int = count_shop_visits.call(gw)
	visitors.visits.clear()
	check(usual == visitors.SHOP_TYPES.shop.weekday and busy == int(usual * 1.5), "ゴールデンウィークはショップの客が増える（ふだん%d人 → %d人）" % [usual, busy])

	# 始まった日の朝に知らせる（2日目からは知らせない）。ビルの状況にも出る
	var first_gw: int = find_day.call(func(d): return clock.date(d) == [4, 29])
	visitors.notice_season(first_gw)
	check(logged("ゴールデンウィーク（5月5日まで）"), "にぎわいが始まった日にメッセージで知らせる")
	var notices: int = main.message_log.filter(func(line): return line.contains("ゴールデンウィーク（5月5日まで）")).size()
	visitors.notice_season(first_gw + 1)
	check(main.message_log.filter(func(line): return line.contains("ゴールデンウィーク（5月5日まで）")).size() == notices, "2日目からは知らせない")
	clock.day = first_gw + 1
	await wait_frames(2)
	check(main.stats_label.text.contains("季節: ゴールデンウィーク（5月5日まで・お客さん1.5倍）"), "ビルの状況に季節のにぎわいが出る")
	return true

# シナリオ84: エレベーターの成績（今日の平均待ち時間・一番長い待ち時間・乗った人数・一番混む時間帯）
#   共通のビルの右端 x=8 に1号機（2〜4階と1階をつなぐ）、x=9 に2号機を建てて試す
# ---------------------------------------------------
func run_elevator_stats_scenario() -> bool:
	print("[シナリオ] エレベーターの成績")
	main.funds = 10000000
	var elevators = main.elevator_system
	main.select_mode("elevator")
	for x in [8, 9]:
		for y in range(18, 14, -1):
			main.build_at(Vector2i(x, y))
	main.clock.set_time(1, 8, 30)
	check(elevators.shaft_label(elevators.shaft_key(Vector2i(8, 16))) == "1号機（エレベーター）" and elevators.shaft_label(elevators.shaft_key(Vector2i(9, 16))) == "2号機（エレベーター）", "シャフトは左から1号機・2号機と呼ぶ")

	# 乗った人の待ち時間から、平均・最長・人数・混む時間帯を出す
	elevators.record_wait(Vector2i(8, 18), 2.0)
	elevators.record_wait(Vector2i(8, 17), 6.0)
	main.clock.set_time(1, 18, 10)
	elevators.record_wait(Vector2i(9, 18), 1.0)
	check(elevators.stats_text(elevators.shaft_key(Vector2i(8, 16))) == "平均待ち4.0分・最長6分・2人・8時台が一番混む", "1号機: 平均4分・最長6分・2人・8時台が一番混む")
	var lines: Array[String] = elevators.stats_lines()
	check(lines.size() == 2 and lines[0].begins_with("エレベーター 1号機（エレベーター）: 平均待ち4.0分"), "ビルの状況には、待ち時間の長いエレベーターから出す")
	await wait_frames(2)
	check(main.stats_label.text.contains("エレベーター 2号機（エレベーター）: 平均待ち1.0分"), "ビルの状況にエレベーターの成績が出る")
	focus_camera(Vector2i(8, 16))
	await wait_frames(1)
	await hover_cell(Vector2i(8, 16))
	check(main.hover_label.text.contains("1号機・今日: 平均待ち4.0分"), "シャフトにカーソルを合わせると、そのエレベーターの成績が出る")

	# 日付が変わると数え直す
	main.clock.set_time(2, 0, 10)
	check(elevators.stats_lines().is_empty(), "日付が変わると、今日の成績は数え直す")

	# 実際に人が乗ると記録される
	var r = main.spawn_resident(Vector2i(7, 18))
	r.go_to(Vector2i(7, 15))
	main.clock.set_process(true)
	await wait_until(func(): return is_instance_valid(r) and r.cell == Vector2i(7, 15), 20.0)
	main.clock.set_process(false)
	check(elevators.wait_stats.get(elevators.shaft_key(Vector2i(8, 18)), {}).get("riders", 0) == 1, "人がカゴに乗ると、乗り場で待った時間が記録される")
	check(r.wait_started < 0.0, "乗ったら、待ち始めた時刻は消す（次に待つときに、また数え始める）")
	return true

# シナリオ85: ビルの名前（タイトル画面・メニューで付けて、屋上の看板・ビルの状況・セーブの枠に出る）
# ---------------------------------------------------
func run_tower_name_scenario() -> bool:
	print("[シナリオ] ビルの名前")
	var ui = main.ui
	check(main.tower_name == main.DEFAULT_TOWER_NAME, "はじめの名前は「%s」" % main.DEFAULT_TOWER_NAME)
	check(ui.title_name_edit != null and ui.title_name_edit.text == main.DEFAULT_TOWER_NAME, "タイトル画面に、ビルの名前の入力欄がある")
	main.set_tower_name("  空の上ビル  ")
	check(main.tower_name == "空の上ビル" and main.get_window().title == "空の上ビル - ProjectTower", "前後の空白は除いて名前を付け、ウィンドウのタイトルにも出す")
	main.set_tower_name("あいうえおかきくけこさしすせそたちつてと")
	check(main.tower_name.length() == main.TOWER_NAME_MAX, "名前は%d文字まで" % main.TOWER_NAME_MAX)
	main.set_tower_name("")
	check(main.tower_name == main.DEFAULT_TOWER_NAME, "空にすると、はじめの名前に戻る")

	# メニューの「ビルの名前を変える」で変えられる（Enterで決める）
	ui.do_menu_action("rename")
	check(ui.name_panel.visible and ui.name_edit.has_focus(), "メニューから、名前を変える画面が開く")
	var cam_before: Vector2 = main.camera.position
	await hold_key(KEY_W, 0.2)
	check(main.camera.position == cam_before, "名前を打っている間は、WASDで画面が動かない")
	ui.name_edit.text = "ProjectTowerビル"
	ui.name_edit.text_submitted.emit(ui.name_edit.text)
	check(not ui.name_panel.visible and main.tower_name == "ProjectTowerビル" and logged("ビルの名前を「ProjectTowerビル」にしました"), "決めると名前が変わる")
	await wait_frames(1)
	cam_before = main.camera.position
	await hold_key(KEY_W, 0.2)
	check(main.camera.position != cam_before, "名前を決めたあとは、またWASDで画面を動かせる")
	ui.do_menu_action("rename")
	await press_key(KEY_ESCAPE)
	check(not ui.name_panel.visible and main.get_viewport().gui_get_focus_owner() != ui.name_edit, "Escで名前の画面を閉じると、入力欄からキーが離れる")
	await wait_frames(2)
	check(main.stats_label.text.begins_with("ビル:「ProjectTowerビル」"), "ビルの状況の一番上に名前が出る")

	# 屋上の看板: 一番上の階（共通のビルは4階）の屋根に立つ
	var sign_rect: Rect2 = main.tower_sign.sign_rect()
	var tile: float = main.tile_map.tile_set.tile_size.y
	check(sign_rect.has_area() and sign_rect.end.y <= 15 * tile, "看板は一番上の階の屋根の上に立つ")
	check(absf(sign_rect.get_center().x - 0.0) < tile, "看板は一番上の階の真ん中に立つ")
	focus_camera(Vector2i(0, 14))
	await wait_frames(2)
	await capture("tower_name_01_sign")

	# セーブの枠と読み込み
	check(main.save_system.slot_path(1).begins_with(TEST_SAVE_DIR), "テストのセーブはテスト用のフォルダに書く")
	main.save_system.save_slot(1)
	check(main.save_system.slot_info(1).name == "ProjectTowerビル", "セーブの枠に名前が残る")
	main.set_tower_name("べつの名前", false)
	main.save_system.load_slot(1)
	check(main.tower_name == "ProjectTowerビル", "読み込むと名前も戻る")
	remove_test_save(main.save_system.slot_path(1))
	return true

# シナリオ86: 人の気持ちの吹き出し（激怒は怒りのマーク・待ちでストレスが高いと汗・着いたときに音符）
# ---------------------------------------------------
func run_mood_scenario() -> bool:
	print("[シナリオ] 気持ちの吹き出し")
	var r = main.spawn_resident(Vector2i(0, 18))
	check(r.mood() == "", "ふだんは何も出さない")
	r.stress = 96.0
	check(r.mood() == "angry", "激怒している人には怒りのマーク")
	r.stress = 75.0
	r.state = r.State.WAITING
	check(r.mood() == "sweat", "エレベーターを待っていてストレスが高い人には汗")
	r.stress = 50.0
	check(r.mood() == "", "待っていても、ストレスがそれほど高くなければ出さない")
	r.state = r.State.WALKING
	r.stress = 10.0
	r.go_to(Vector2i(3, 18))
	await wait_until(func(): return not r.is_moving(), 10.0)
	check(r.mood() == "note", "ストレスの低い人が行き先に着くと、音符が出る")
	r.arrived_ticks -= int(r.NOTE_SECONDS * 1000.0) + 1
	check(r.mood() == "", "音符は少しのあいだだけ")
	r.arrived_ticks = Time.get_ticks_msec()
	r.stress = 45.0
	check(r.mood() == "", "ストレスが高めなら、着いても音符は出ない")
	# 見た目を撮っておく（怒り・汗・音符を並べる）
	var faces: Array = []
	for i in 3:
		faces.append(main.spawn_resident(Vector2i(-3 + i * 2, 18)))
	faces[0].stress = 99.0
	faces[1].stress = 80.0
	faces[1].state = faces[1].State.WAITING
	faces[1].path = [Vector2i(-1, 17)] as Array[Vector2i] # 待っている人には行き先がいる
	faces[2].stress = 5.0
	faces[2].arrived_ticks = Time.get_ticks_msec()
	check(faces.map(func(f): return f.mood()) == ["angry", "sweat", "note"], "3人に、それぞれの気持ちのアイコンが出る")
	focus_camera(Vector2i(-1, 17))
	main.camera.zoom = Vector2(6, 6)
	faces[1].set_process(false) # 撮るまで「待っている」ままにしておく（乗り場ではないので、動かすと待つのをやめてしまう）
	await capture("mood_01_icons")
	for f in faces:
		f.state = f.State.WALKING
		f.path.clear()
		f.queue_free()
	r.queue_free()
	return true

# シナリオ87: 覚えておく一覧（大きなビルで重くならないように、建物の種類ごとの一覧・シャフトごとのカゴを覚えておく）が、
#   建設・撤去・焼失のあとに正しく作り直される
# ---------------------------------------------------
func run_cache_scenario() -> bool:
	print("[シナリオ] 覚えておく一覧")
	main.funds = 10000000
	var offices: int = main.find_units_of_type("office").size()
	main.select_mode("office")
	main.build_at(Vector2i(-8, 14))
	check(main.find_units_of_type("office").size() == offices + 1, "建てると、種類ごとの一覧に増える")
	var list: Array[Vector2i] = main.find_units_of_type("office")
	list.clear()
	check(main.find_units_of_type("office").size() == offices + 1, "受け取った一覧を変えても、覚えている一覧は変わらない")
	main.demolish_at(Vector2i(-8, 14))
	check(main.find_units_of_type("office").size() == offices and main.find_cells_of_type("office").size() == offices * 4, "撤去すると、一覧から消える")
	main.destroy_unit(Vector2i(-8, 17))
	check(main.find_units_of_type("office").size() == offices - 1 and main.find_units_of_type("ruin").size() == 4, "焼け落ちると、焼け跡の一覧に入る")
	check(main.stress_recover_rate() == 1.0, "メディカルセンターがなければ、ストレスの回復は1倍")
	main.select_mode("medical")
	main.build_at(Vector2i(-8, 14))
	check(main.stress_recover_rate() > 1.0, "メディカルセンターを建てると、すぐに回復が速くなる")

	# シャフトごとのカゴ
	var elevators = main.elevator_system
	main.select_mode("elevator")
	for y in range(18, 14, -1):
		main.build_at(Vector2i(8, y))
	check(elevators.get_cars_at(Vector2i(8, 16)).size() == 1, "シャフトを建てると、そのシャフトのカゴが見つかる")
	elevators.add_car(Vector2i(8, 18))
	check(elevators.get_cars_at(Vector2i(8, 16)).size() == 2, "カゴを足すと、すぐに見つかる")
	main.demolish_at(Vector2i(8, 15))
	check(elevators.get_cars_at(Vector2i(8, 16)).size() == 2 and elevators.get_cars_at(Vector2i(8, 15)).is_empty(), "シャフトを縮めると、なくなった階ではカゴが見つからない")
	return true
