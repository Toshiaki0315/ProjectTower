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
	# 本物のマウスの操作がテストの入力に割り込まないよう、ウィンドウはマウスを受け付けない
	# （テストの入力は push_input で直接送るので影響しない）
	root.mouse_passthrough = true

	# シナリオごとにゲームを起動し直して、前のシナリオの影響を受けないようにする
	for scenario in [run_build_scenario, run_stairs_scenario, run_camera_scenario, run_ui_scenario, run_elevator_scenario, run_ride_scenario, run_stress_scenario, run_collective_scenario, run_commute_scenario, run_economy_scenario, run_hotel_scenario, run_lunch_scenario, run_recycling_scenario, run_rating_scenario, run_housing_scenario, run_room_types_scenario, run_weekday_scenario, run_event_scenario, run_subway_scenario]:
		await start_main()
		# シナリオは最後まで進むとtrueを返す。途中でスクリプトエラーが起きるとnullになる
		var finished = await scenario.call()
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

func start_main() -> void:
	if main:
		main.queue_free()
		await wait_frames(1)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Engine.time_scale = 1.0
	await wait_frames(3) # _ready()が済むまで待つ
	main.clock.set_process(false) # 社員の出勤で他のシナリオが乱れないよう、時計は止めておく

# ---------------------------------------------------
# シナリオ1: 建設・撤去とモード表示
# ---------------------------------------------------
func run_build_scenario() -> bool:
	print("[シナリオ] 建設・撤去")
	var start_funds: int = main.funds
	await capture("build_01_start")

	# 1. 階段ボタンをクリック → 階段が[選択中]になる
	await click_button(main.mode_buttons["stairs"])
	check(main.current_mode == "stairs", "階段ボタンでモードがstairsになる")
	check(main.mode_buttons["stairs"].text.begins_with("▶"), "階段ボタンに▶が付く")
	check(main.mode_buttons["stairs"].button_pressed, "階段ボタンが押し込まれた表示になる")
	check(not main.mode_buttons["office"].text.begins_with("▶"), "オフィスボタンから▶が外れる")
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
	return true

# ---------------------------------------------------
# シナリオ2: 階段による移動
# 事前配置のブロック（y=15〜18）の右隣に階段を置き、その上の階にオフィスを並べる。
# 住人はブロック上段(0,15)から、階段(8,15)→(8,14)を通って上の階(4,14)へ向かう。
# ---------------------------------------------------
func run_stairs_scenario() -> bool:
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
	check(cam.zoom.x > cam.DEFAULT_ZOOM, "ホイール上でズームインする")
	check(cam.screen_to_world(screen_pos).is_equal_approx(world_before), "ズームしてもカーソル下の位置がずれない")
	check(main.funds == 1000000, "ホイール操作で建設されない")
	
	# ズーム後もクリックしたマスに正しく建設できる
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
	check(main.funds == 900000, "中ボタンドラッグで建設・撤去されない")
	
	# キー操作 → 押している間移動する
	pos_before = cam.position
	await hold_key(KEY_W, 0.2)
	check(cam.position.y < pos_before.y, "Wキーで上に移動する")
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
	var empty_cell := Vector2i(3, 13)
	await hover_cell(empty_cell)
	check(overlay.hover_visible and overlay.hover_cell == empty_cell, "カーソル下のマスを強調表示する")
	check(main.can_click_cell(empty_cell), "空きマスは建設可能（緑）と判定される")
	check(main.hover_label.text.contains(str(empty_cell)) and main.hover_label.text.contains("空き"), "下部バーにマスの座標と「空き」が出る")
	await capture("ui_01_hover_empty")
	
	var office_cell := Vector2i(0, 16)
	await hover_cell(office_cell)
	check(not main.can_click_cell(office_cell), "建物のあるマスは建設不可（赤）と判定される")
	check(main.hover_label.text.contains("オフィス"), "下部バーに建物の種類が出る")
	
	# 操作説明の開閉
	var help_button: Button = null
	for node in main.find_children("*", "Button", true, false):
		if node.text == "操作説明":
			help_button = node
	check(help_button != null and not main.help_panel.visible, "操作説明は最初は閉じている")
	await click_button(help_button)
	check(main.help_panel.visible, "操作説明ボタンで説明が開く")
	await capture("ui_02_help_open")
	await click_button(help_button)
	check(not main.help_panel.visible, "もう一度押すと説明が閉じる")
	return true

# ---------------------------------------------------
# シナリオ5: エレベーター（1本のシャフトで1台のカゴが指定階に停まる）
# 事前配置のブロック（x=-8〜7, y=15〜18）の右隣 x=8 に、y=14〜18 のシャフトを建てる。
# ---------------------------------------------------
func run_elevator_scenario() -> bool:
	print("[シナリオ] エレベーター")
	var elevators = main.elevator_system
	var x := 8
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 13, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	check(main.funds == 500000, "シャフト5マスで50万円かかる")
	check(elevators.cars.size() == 1, "縦につながったシャフトにカゴが1台できる")
	var car = elevators.cars[0]
	check(car.top_y == 14 and car.bottom_y == 18, "シャフトの範囲がy=14〜18になる")
	check(car.current_floor() == 18, "カゴは最下階からスタートする")
	
	# 階を指定して呼ぶ → その階に停まる
	var arrivals: Array[int] = []
	car.arrived.connect(func(y): arrivals.append(y))
	Engine.time_scale = 4.0
	await click_cell(Vector2i(x, 15), MOUSE_BUTTON_LEFT)
	check(main.funds == 500000, "シャフトのクリックでは建設されない（お金も減らない）")
	await wait_until(func(): return car.state == car.State.MOVING, 5.0)
	await capture("elevator_01_moving")
	await wait_until(func(): return arrivals.size() >= 1, 10.0)
	check(arrivals == [15], "呼んだ階(y=15)に停まる")
	check(car.position == main.tile_map.map_to_local(Vector2i(x, 15)), "カゴが階の位置にぴったり停まる")
	check(car.state == car.State.DOORS_OPEN, "停まったら扉が開く")
	check(main.message_label.text.contains("到着"), "到着メッセージが出る")
	await capture("elevator_02_arrived")
	
	# 集合制御: 下(18)へ向かう途中で17を呼ぶ → 先に17に寄ってから18へ
	Engine.time_scale = 1.0
	await wait_until(func(): return car.state == car.State.IDLE, 5.0)
	await click_cell(Vector2i(x, 18), MOUSE_BUTTON_LEFT)
	await wait_until(func(): return car.state == car.State.MOVING, 5.0)
	check(car.direction == car.Direction.DOWN, "下の階を呼ぶと進行方向が「下」になる")
	await capture("elevator_02b_direction")
	await click_cell(Vector2i(x, 17), MOUSE_BUTTON_LEFT)
	Engine.time_scale = 4.0
	await wait_until(func(): return arrivals.size() >= 3, 15.0)
	check(arrivals == [15, 17, 18], "下へ向かう途中で呼ばれた階(17)に寄ってから18に停まる")
	
	# 進行方向を保つ: 上(14)へ向かう途中、通り過ぎた後ろの階(17)を呼んでも引き返さない
	Engine.time_scale = 1.0
	await wait_until(func(): return car.state == car.State.IDLE, 5.0)
	await click_cell(Vector2i(x, 14), MOUSE_BUTTON_LEFT)
	await wait_until(func(): return car.current_floor() <= 16, 5.0)
	await click_cell(Vector2i(x, 17), MOUSE_BUTTON_LEFT)
	Engine.time_scale = 4.0
	await wait_until(func(): return arrivals.size() >= 5, 15.0)
	check(arrivals.slice(3) == [14, 17], "上へ進んでいる間は後ろの階に引き返さず、14の後に17へ向かう")
	await wait_until(func(): return car.state == car.State.IDLE, 5.0)
	check(car.direction == car.Direction.NONE, "呼び出しがなくなると進行方向が消える")
	Engine.time_scale = 1.0
	
	# シャフトの最下段を撤去 → 同じカゴのまま範囲が縮む
	await click_cell(Vector2i(x, 18), MOUSE_BUTTON_RIGHT)
	check(elevators.cars.size() == 1 and elevators.cars[0] == car, "シャフトを縮めても同じカゴが残る")
	check(car.bottom_y == 17, "シャフトの範囲がy=14〜17になる")
	var other_cell := Vector2i(x, 14)
	
	# 途中を撤去 → シャフトが2本に分かれ、カゴも2台になる
	await click_cell(Vector2i(x, 16), MOUSE_BUTTON_RIGHT)
	check(elevators.cars.size() == 2, "途中を撤去するとシャフトが2本になりカゴも2台になる")
	check(elevators.cars.has(car), "元のカゴは今いる階のシャフトに残る")
	
	# 範囲外の階は呼べない
	check(not car.request_floor(other_cell.y), "別のシャフトになった階には呼べない")
	await capture("elevator_03_split")
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
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	var car = main.elevator_system.cars[0]
	var arrivals: Array[int] = []
	car.arrived.connect(func(y): arrivals.append(y))
	
	await click_button(main.mode_buttons["resident"])
	await click_cell(Vector2i(0, 15), MOUSE_BUTTON_LEFT)
	var resident = main.residents.back()
	var goal := Vector2i(5, 13)
	await click_cell(goal, MOUSE_BUTTON_LEFT)
	check(resident.is_moving(), "エレベーターのある上の階を指定すると移動を始める")
	var path: Array[Vector2i] = [resident.cell]
	path.append_array(resident.path)
	check(count_rides(path) == 1, "経路にエレベーターの乗車が1回含まれる")
	
	Engine.time_scale = 4.0
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
	# x=9 に y=14〜18 の階段を積み、y=13 にオフィスを置く（x=8のシャフトと並ぶ）
	await click_button(main.mode_buttons["stairs"])
	for y in range(18, 13, -1):
		await click_cell(Vector2i(9, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	await click_cell(Vector2i(9, 13), MOUSE_BUTTON_LEFT)
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
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	var car = main.elevator_system.cars[0]
	
	await click_button(main.mode_buttons["resident"])
	await click_cell(Vector2i(0, 15), MOUSE_BUTTON_LEFT)
	var resident = main.residents.back()
	var goal := Vector2i(5, 13)
	await click_cell(goal, MOUSE_BUTTON_LEFT)
	check(resident.stress == 0.0 and resident.get_body_color() == Color.WHITE, "最初はストレス0で白")
	
	car.set_process(false) # カゴを止めて、住人を待たせ続ける
	Engine.time_scale = 4.0
	await wait_until(func(): return resident.state == resident.State.WAITING, 10.0)
	var walking_stress: float = resident.stress
	check(walking_stress == 0.0, "歩いている間はストレスがたまらない")
	
	await wait_until(func(): return resident.stress >= resident.STRESS_PINK, 10.0)
	check(resident.get_body_color() == resident.PINK_COLOR, "ストレス40以上でピンクになる")
	await hover_cell(resident.cell)
	check(main.hover_label.text.contains("住人のストレス"), "カーソルを合わせると下部バーにストレスが出る")
	await capture("stress_01_pink")
	
	await wait_until(func(): return resident.stress >= resident.STRESS_RED, 10.0)
	check(resident.get_body_color() == resident.RED_COLOR, "ストレス70以上で赤になる")
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
	check(resident.stress < arrived_stress and resident.get_body_color() == resident.PINK_COLOR, "目的地に着くとストレスが回復して赤からピンクに戻る")
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
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	var car = main.elevator_system.cars[0]
	
	# カゴを最上階(13)に上げてから、最下階(18)へ向かわせる
	await click_button(main.mode_buttons["elevator"])
	await click_cell(Vector2i(x, 13), MOUSE_BUTTON_LEFT)
	await wait_until(func(): return car.floor_y == 13 and car.state == car.State.IDLE, 10.0)
	var arrivals: Array[int] = []
	car.arrived.connect(func(y): arrivals.append(y))
	await click_cell(Vector2i(x, 18), MOUSE_BUTTON_LEFT)
	
	# 上へ行きたい住人を、シャフトの隣(7,15)に置いて(5,13)へ向かわせる
	await click_button(main.mode_buttons["resident"])
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
# ＋ どこにもつながらない孤立したオフィス1つ。入口はブロック最下段の左端(-8,18)。
# ---------------------------------------------------
func run_commute_scenario() -> bool:
	print("[シナリオ] 出退社ラッシュ")
	main.funds = 10000000
	var commute = main.commute_system
	var x := 8
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(x, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	await click_cell(Vector2i(-10, 20), MOUSE_BUTTON_LEFT) # 孤立したオフィス
	check(main.get_entrance() == Vector2i(-8, 18), "地下にオフィスを建てても、入口は1階の左端のまま")
	await click_cell(Vector2i(-10, 20), MOUSE_BUTTON_RIGHT)
	await click_cell(Vector2i(-10, 14), MOUSE_BUTTON_LEFT) # 上の方に置き直す
	check(main.get_entrance() == Vector2i(-8, 18), "入口はブロック最下段の左端(-8,18)")
	check(commute.workers.size() == 68, "オフィス68マスに社員68人が登録される")
	
	# 7:59 → 時計を進めて朝のラッシュを見る
	var car = main.elevator_system.cars[0]
	var elevator_stops := [0]
	car.arrived.connect(func(_y): elevator_stops[0] += 1)
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	check(main.clock_label.text != "", "上部バーに時刻が出る")
	Engine.time_scale = 8.0
	await wait_until(func(): return main.clock.minute_of_day() >= 8 * 60 + 30, 20.0)
	check(main.clock_label.text.begins_with("1日目（月） 08:"), "時刻の表示が進む（1日目（月） 08:xx）")
	check(commute.count_in_building() > 0, "8時台に社員が入口から出勤してくる")
	await capture("commute_01_rush")
	var max_stress := 0.0
	while main.clock.minute_of_day() < 10 * 60:
		for r in main.residents:
			if is_instance_valid(r):
				max_stress = maxf(max_stress, r.stress)
		await process_frame
	print("    at_office=", commute.count_at_office(), " in_building=", commute.count_in_building(), " unreachable=", commute.count_unreachable())
	check(commute.count_at_office() == 67, "10時には通勤できる67人全員が自分のオフィスに着いている")
	check(commute.count_unreachable() == 1, "孤立したオフィスの1人は通勤できない")
	check(main.stats_label.text.contains("通勤できない 1人"), "下部バーに通勤できない人数が出る")
	check(elevator_stops[0] > 0, "上の階の社員はエレベーターで出勤する")
	check(max_stress > 0.0, "エレベーター待ちで社員にストレスがたまる")
	await capture("commute_02_at_office")
	
	# 夕方 → 全員帰る
	Engine.time_scale = 16.0
	await wait_until(func(): return main.clock.minute_of_day() >= 19 * 60, 60.0)
	Engine.time_scale = 1.0
	await wait_frames(2)
	print("    evening in_building=", commute.count_in_building())
	check(commute.count_in_building() == 0, "19時には全員が入口から帰っている")
	await capture("commute_03_evening")
	main.clock.set_process(false)
	return true

# ---------------------------------------------------
# シナリオ10: 毎日の決算（賃料収入と維持費）
# シナリオ9と同じ建物で1日目を過ごし、0:00の決算を確かめる。
# 出勤できるオフィス67マス × 1万円 − エレベーター6マス × 2千円
#   − ゴミ67の外部委託（ゴミ処理場なし）× 1千円 = +591,000円
# ---------------------------------------------------
func run_economy_scenario() -> bool:
	print("[シナリオ] 決算")
	check(main.format_money(1000000) == "1,000,000", "金額は3桁ごとにカンマで区切る")
	check(main.format_money(-1234) == "-1,234" and main.format_money(999) == "999", "マイナスや3桁以下も正しく表示する")
	check(main.format_money(658000, true) == "+658,000", "収支にはプラス記号を付ける")
	
	main.funds = 10000000
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	await click_cell(Vector2i(-10, 14), MOUSE_BUTTON_LEFT) # 孤立したオフィス（賃料は入らない）
	check(main.funds_label.text.contains("現在の資金: 9,000,000円"), "資金の表示もカンマ区切りになる")
	
	# 1日目の朝に全員出勤させてから、夜中まで時計を進める
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	Engine.time_scale = 8.0
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60, 30.0)
	main.clock.set_time(1, 23, 58)
	var funds_before: int = main.funds
	await wait_until(func(): return not main.economy_system.last_report.is_empty(), 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	var report = main.economy_system.last_report
	check(report.get("day") == 1, "日付が変わると1日目の決算をする")
	check(report.get("rent") == 670000, "出勤したオフィス67マス分の賃料67万円が入る（孤立したオフィスは0）")
	check(report.get("maintenance") == 12000, "エレベーター6マス分の維持費1.2万円がかかる")
	check(report.get("garbage") == 67 and report.get("garbage_cost") == 67000, "ゴミ処理場がないとゴミ67を外部委託して6.7万円かかる")
	check(main.funds == funds_before + 591000, "資金が差し引き59.1万円増える")
	check(main.funds_label.text.contains("（前日 +591,000円）"), "資金の横に前日の収支が出る")
	check(main.message_label.text.contains("1日目の決算"), "決算の内容がメッセージに出る")
	await capture("economy_01_settled")
	return true

# ---------------------------------------------------
# シナリオ11: ホテルとハウスキーパー
# ブロック最下段(y=18)の右隣に、客室3室(x=8〜10)とハウスキーパー室(x=11)を並べる。
# 入口(-8,18)から同じ階を歩いて行き来できる。
# ---------------------------------------------------
func run_hotel_scenario() -> bool:
	print("[シナリオ] ホテルとハウスキーパー")
	main.funds = 10000000
	var hotel = main.hotel_system
	var room_cells: Array[Vector2i] = [Vector2i(8, 18), Vector2i(9, 18), Vector2i(10, 18)]
	await click_button(main.mode_buttons["hotel"])
	for cell in room_cells:
		await click_cell(cell, MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["housekeeping"])
	await click_cell(Vector2i(11, 18), MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 3 * 150000 - 100000, "客室15万円×3とハウスキーパー室10万円がかかる")
	check(hotel.rooms.size() == 3 and hotel.count_rooms(hotel.RoomState.CLEAN) == 3, "客室が3室でき、最初はきれいな空室")
	check(hotel.housekeepers.size() == 1, "ハウスキーパー室に清掃員が1人いる")
	var keeper = hotel.housekeepers.values()[0].resident
	check(keeper.base_color == hotel.HOUSEKEEPER_COLOR, "清掃員は水色")
	
	# 夕方 → 客が来て泊まる
	main.clock.set_time(1, 16, 59)
	main.clock.set_process(true)
	Engine.time_scale = 16.0
	await wait_until(func(): return main.clock.minute_of_day() >= 21 * 60 + 30, 30.0)
	check(hotel.count_rooms(hotel.RoomState.OCCUPIED) == 3, "21時半には3室とも宿泊中になる")
	var guests_in_room := 0
	for cell in room_cells:
		var guest = hotel.rooms[cell].guests[0]
		if is_instance_valid(guest) and guest.cell == cell and guest.base_color == hotel.GUEST_COLOR:
			guests_in_room += 1
	check(guests_in_room == 3, "薄紫の宿泊客がそれぞれの部屋に着いている")
	await hover_cell(room_cells[0])
	check(main.hover_label.text.contains("シングル（宿泊中）"), "カーソルを合わせると部屋の状態が出る")
	check(main.stats_label.text.contains("客室: 宿泊 3"), "下部バーに客室の状況が出る")
	var viewport_width: float = main.get_viewport_rect().size.x
	var help_button_right := 0.0
	for node in main.find_children("*", "Button", true, false):
		help_button_right = maxf(help_button_right, node.get_global_rect().end.x)
	check(help_button_right <= viewport_width, "文字が増えてもUIのボタンが画面からはみ出さない")
	await capture("hotel_01_night")
	
	# 翌朝 → チェックアウトして帰り、部屋は清掃待ち → 清掃員が掃除する
	main.clock.set_time(2, 6, 59)
	await wait_until(func(): return hotel.count_rooms(hotel.RoomState.OCCUPIED) == 0, 30.0)
	check(hotel.revenue_by_day.get(2, 0) == 60000, "チェックアウトで宿泊料2万円×3室が入る")
	var saw_dirty := [false]
	var saw_cleaning := [false]
	await wait_until(func():
		if hotel.count_rooms(hotel.RoomState.DIRTY) > 0:
			saw_dirty[0] = true
		for cell in room_cells:
			if hotel.get_room_state_text(cell) == "清掃中":
				saw_cleaning[0] = true
		return hotel.count_rooms(hotel.RoomState.CLEAN) == 3, 30.0)
	check(saw_dirty[0], "チェックアウトした部屋は清掃待ちになる")
	check(saw_cleaning[0], "清掃員が部屋に来て清掃する")
	check(hotel.count_rooms(hotel.RoomState.CLEAN) == 3, "清掃が済むと3室ともきれいな空室に戻る")
	await wait_until(func(): return keeper.cell == Vector2i(11, 18) and not keeper.is_moving(), 20.0)
	check(keeper.cell == Vector2i(11, 18), "仕事が終わると清掃員はハウスキーパー室に戻る")
	
	# 2日目の決算に宿泊料と維持費が入る
	main.clock.set_time(2, 23, 59)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 2, 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(main.economy_system.last_report.get("hotel") == 60000, "2日目の決算に宿泊料6万円が入る")
	check(main.economy_system.last_report.get("maintenance") == 5000, "ハウスキーパー室の維持費5千円がかかる")
	check(main.message_label.text.contains("宿泊料 +60,000円"), "決算のメッセージに宿泊料が出る")
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
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	var restaurant := Vector2i(9, 18)
	await click_button(main.mode_buttons["restaurant"])
	await click_cell(restaurant, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(restaurant) == "restaurant", "飲食店を建てられる（20万円）")
	check(main.funds == 10000000 - 6 * 100000 - 3 * 100000 - 200000, "飲食店の建設費20万円がかかる")
	
	# 朝のうちに全員出勤させる
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	Engine.time_scale = 8.0
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60, 30.0)
	check(commute.count_at_office() == 67, "10時には67人全員がオフィスにいる")
	
	# 昼休み
	var car = main.elevator_system.cars[0]
	var lunch_stops := [0]
	car.arrived.connect(func(_y): lunch_stops[0] += 1)
	main.clock.set_time(1, 11, 59)
	Engine.time_scale = 16.0
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
		return main.clock.minute_of_day() >= 14 * 60 + 30, 30.0)
	check(max_eating[0] > 0, "昼に社員が飲食店で食事をする")
	check(lunch_stops[0] > 0, "上の階の社員はエレベーターで飲食店へ行き来する")
	check(commerce.revenue_by_day.get(1, 0) == 67000, "67人が食事をして売上6.7万円になる")
	check(commute.count_at_office() == 67, "14時半には全員がオフィスに戻っている")
	
	# 1日目の決算に飲食店の売上が入る
	main.clock.set_time(1, 23, 59)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 1, 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(main.economy_system.last_report.get("food") == 67000, "決算に飲食店の売上6.7万円が入る")
	check(main.message_label.text.contains("飲食 +67,000円"), "決算のメッセージに飲食の売上が出る")
	return true

# ---------------------------------------------------
# シナリオ13: ゴミ処理場
# シナリオ10と同じ建物＋1階のシャフトの右隣にゴミ処理場2マス（処理能力40）。
# ゴミ67のうち40を処理し、残り27を外部委託（2.7万円）。維持費はエレベーター1.2万＋ゴミ処理場1万。
# ---------------------------------------------------
func run_recycling_scenario() -> bool:
	print("[シナリオ] ゴミ処理場")
	main.funds = 10000000
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["recycling"])
	for rx in [9, 10]:
		await click_cell(Vector2i(rx, 18), MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 6 * 100000 - 3 * 100000 - 2 * 150000, "ゴミ処理場の建設費15万円×2がかかる")
	check(main.economy_system.recycling_capacity() == 40, "ゴミ処理場2マスで処理能力40/日になる")
	await hover_cell(Vector2i(9, 18))
	check(main.hover_label.text.contains("処理能力 40/日"), "カーソルを合わせると処理能力が出る")
	await capture("recycling_01_built")
	
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	Engine.time_scale = 8.0
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60, 30.0)
	main.clock.set_time(1, 23, 58)
	await wait_until(func(): return not main.economy_system.last_report.is_empty(), 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	var report = main.economy_system.last_report
	check(report.get("garbage") == 67, "出勤したオフィス67マスからゴミ67が出る")
	check(report.get("garbage_cost") == 27000, "処理しきれない27を外部委託して2.7万円かかる")
	check(report.get("maintenance") == 22000, "維持費はエレベーター1.2万円＋ゴミ処理場1万円")
	check(report.get("total") == 670000 - 22000 - 27000, "合計は+62.1万円（ゴミ処理場なしより4.2万円得）")
	check(main.message_label.text.contains("ゴミ処理 -27,000円（ゴミ67・処理能力40）"), "決算のメッセージにゴミの量と処理能力が出る")
	return true

# ---------------------------------------------------
# シナリオ14: ビルの評価（★）
# シナリオ10と同じ建物（人口67）に警備室を置くと、1日目の決算で★2に上がり、
# 2日目の決算から賃料に25%の評価ボーナスが付く。
# ---------------------------------------------------
func run_rating_scenario() -> bool:
	print("[シナリオ] ビルの評価")
	main.funds = 10000000
	var rating = main.rating_system
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	check(rating.stars == 1 and rating.population() == 67, "最初は★1、人口67（社員67人）")
	check(rating.missing_for_next() == ["警備室"], "★2に足りないのは警備室だけ")
	await wait_frames(2)
	check(main.stats_label.text.begins_with("★1 人口67（★2まで: 警備室）"), "下部バーに評価と次の★に足りないものが出る")
	
	await click_button(main.mode_buttons["security"])
	await click_cell(Vector2i(9, 18), MOUSE_BUTTON_LEFT)
	check(rating.missing_for_next().is_empty(), "警備室を置くと★2の条件を満たす")
	check(rating.stars == 1, "★が上がるのは決算のとき")
	
	# 1日目: 決算で★2に上がる（ボーナスはまだ付かない）
	await run_day(1)
	var report = main.economy_system.last_report
	check(rating.stars == 2, "1日目の決算で★2に上がる")
	check(main.message_label.text.begins_with("ビルの評価が★2に上がりました！"), "昇格がメッセージで知らされる")
	check(report.get("bonus") == 0, "昇格した日の決算にはまだボーナスが付かない")
	check(report.get("maintenance") == 12000 + 5000, "警備室の維持費5千円がかかる")
	await capture("rating_01_star2")
	
	# 2日目: 賃料67万円の25% = 16.75万円のボーナス
	await run_day(2)
	report = main.economy_system.last_report
	check(report.get("bonus") == 167500, "★2では賃料に25%（16.75万円）の評価ボーナスが付く")
	check(main.message_label.text.contains("評価ボーナス +167,500円"), "決算のメッセージに評価ボーナスが出る")
	
	# ★3の条件
	check(rating.missing_for_next() == ["人口120", "メディカルセンター", "ゴミ処理場"], "★3には人口120・メディカルセンター・ゴミ処理場が必要")
	await click_button(main.mode_buttons["medical"])
	await click_cell(Vector2i(10, 18), MOUSE_BUTTON_LEFT)
	check(main.get_building_type(Vector2i(10, 18)) == "medical", "メディカルセンターを建てられる")
	check(rating.missing_for_next() == ["人口120", "ゴミ処理場"], "メディカルセンターを置くと★3の条件から外れる")
	return true

# ---------------------------------------------------
# シナリオ15: 住宅
# ブロック最下段(y=18)の右隣に住宅2戸(x=8,9)。入口(-8,18)から同じ階を歩いて行き来できる。
# ---------------------------------------------------
func run_housing_scenario() -> bool:
	print("[シナリオ] 住宅")
	main.funds = 10000000
	var housing = main.housing_system
	var homes: Array[Vector2i] = [Vector2i(8, 18), Vector2i(9, 18)]
	await click_button(main.mode_buttons["housing"])
	for cell in homes:
		await click_cell(cell, MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 2 * 150000, "住宅の建設費15万円×2がかかる")
	check(housing.homes.size() == 2 and housing.count_moved_in() == 0, "建てた直後はまだ入居者がいない")
	await hover_cell(homes[0])
	check(main.hover_label.text.contains("住宅（入居者募集中）"), "カーソルを合わせると「入居者募集中」と出る")
	
	# 1日目の夕方: 入居者が来て入居し、販売収入が入る
	main.clock.set_time(1, 16, 59)
	main.clock.set_process(true)
	Engine.time_scale = 16.0
	await wait_until(func(): return main.clock.minute_of_day() >= 20 * 60 + 30, 30.0)
	check(housing.count_moved_in() == 2 and housing.count_at_home() == 2, "夕方に2戸とも入居者が来て家にいる")
	check(housing.revenue_by_day.get(1, 0) == 500000, "入居で販売収入25万円×2が入る")
	check(housing.homes[homes[0]].resident.base_color == housing.RESIDENT_COLOR, "入居者は緑の服")
	var others: int = main.commute_system.workers.size() - main.commute_system.count_unreachable() + main.hotel_system.total_capacity()
	check(main.rating_system.population() == others + 2, "入居者の分だけ人口が増える")
	await hover_cell(homes[0])
	check(main.hover_label.text.contains("住宅（在宅）"), "入居後は「在宅」と出る")
	await capture("housing_01_moved_in")
	
	# 2日目の朝: 1日目の決算に販売収入が入り、入居者は出かける
	main.clock.set_time(2, 6, 59)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 1, 10.0)
	check(main.economy_system.last_report.get("housing") == 500000, "1日目の決算に住宅販売50万円が入る")
	check(main.message_label.text.contains("住宅販売 +500,000円"), "決算のメッセージに住宅販売が出る")
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60, 30.0)
	check(housing.count_at_home() == 0, "朝のうちに入居者は出かけている")
	check(housing.homes[homes[0]].resident == null, "出かけた入居者はビルの外にいる")
	await hover_cell(homes[0])
	check(main.hover_label.text.contains("住宅（外出中）"), "外出中は「外出中」と出る")
	
	# 2日目の夕方: 帰ってくる（販売収入は2回目は入らない）
	main.clock.set_time(2, 16, 59)
	await wait_until(func(): return main.clock.minute_of_day() >= 20 * 60 + 30, 30.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)
	check(housing.count_at_home() == 2, "夕方には2人とも帰ってくる")
	check(housing.revenue_by_day.get(2, 0) == 0, "販売収入は入居したときの1回だけ")
	return true

# ---------------------------------------------------
# シナリオ16: ホテルのツイン・スイート
# ブロック最下段(y=18)の右隣に、ツイン(8)・スイート(9)・ハウスキーパー室(10)を並べる。
# ---------------------------------------------------
func run_room_types_scenario() -> bool:
	print("[シナリオ] ツイン・スイート")
	main.funds = 10000000
	var hotel = main.hotel_system
	var twin := Vector2i(8, 18)
	var suite := Vector2i(9, 18)
	await click_button(main.mode_buttons["hotel_twin"])
	await click_cell(twin, MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["hotel_suite"])
	await click_cell(suite, MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["housekeeping"])
	await click_cell(Vector2i(10, 18), MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 200000 - 500000 - 100000, "ツイン20万円・スイート50万円がかかる")
	check(hotel.total_capacity() == 4, "ツインとスイートは2人ずつ、定員の合計は4人")
	var others: int = main.commute_system.workers.size() - main.commute_system.count_unreachable()
	check(main.rating_system.population() == others + 4, "人口には客室の定員が入る")
	
	# 夕方: それぞれ2人ずつ泊まりに来る
	main.clock.set_time(1, 16, 59)
	main.clock.set_process(true)
	Engine.time_scale = 16.0
	await wait_until(func(): return main.clock.minute_of_day() >= 21 * 60 + 30, 30.0)
	check(hotel.rooms[twin].guests.size() == 2 and hotel.rooms[suite].guests.size() == 2, "ツインとスイートにそれぞれ2人ずつ泊まる")
	var arrived := 0
	for cell in [twin, suite]:
		for guest in hotel.rooms[cell].guests:
			if guest.cell == cell and not guest.is_moving():
				arrived += 1
	check(arrived == 4, "4人とも部屋に着いている")
	await hover_cell(suite)
	check(main.hover_label.text.contains("スイート（宿泊中）"), "カーソルを合わせると客室の種類と状態が出る")
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
		return clean_end.size() == 2, 40.0)
	check(hotel.revenue_by_day.get(2, 0) == 35000 + 80000, "チェックアウトでツイン3.5万円＋スイート8万円が入る")
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
# シナリオ10と同じ建物（社員67人）＋ 1階の右隣に住宅1戸(9,18)。
# 5日目（金）→ 6日目（土・休日）→ 8日目（月）と進めて違いを確かめる。
# ---------------------------------------------------
func run_weekday_scenario() -> bool:
	print("[シナリオ] 平日・休日")
	main.funds = 10000000
	var clock = main.clock
	check(clock.weekday(1) == 0 and not clock.is_holiday(1), "1日目は月曜日で平日")
	check(clock.is_holiday(6) and clock.is_holiday(7) and not clock.is_holiday(8), "6日目（土）・7日目（日）は休日、8日目（月）は平日")
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	var home := Vector2i(9, 18)
	await click_button(main.mode_buttons["housing"])
	await click_cell(home, MOUSE_BUTTON_LEFT)
	
	# 5日目（金）: 社員は出勤し、夕方に入居者が入居する
	clock.set_time(5, 7, 59)
	clock.set_process(true)
	Engine.time_scale = 8.0
	await wait_until(func(): return clock.minute_of_day() >= 10 * 60, 30.0)
	check(main.commute_system.count_at_office() == 67, "金曜日は67人が出勤する")
	clock.set_time(5, 16, 59)
	Engine.time_scale = 16.0
	await wait_until(func(): return main.housing_system.count_at_home() == 1 and clock.minute_of_day() >= 20 * 60, 30.0)
	
	# 6日目（土）: 休日。社員は来ない。入居者は遅めに出かける
	clock.set_time(6, 7, 59)
	await wait_until(func(): return clock.minute_of_day() >= 9 * 60 + 45, 30.0)
	check(main.clock_label.text.begins_with("6日目（土）休日"), "上部バーに曜日と休日が出る")
	check(main.commute_system.count_in_building() == 0, "休日は社員が出勤しない")
	check(main.housing_system.count_at_home() == 1, "休日の入居者は9時45分にはまだ家にいる（平日なら9時までに出かける）")
	await capture("weekday_01_holiday")
	await wait_until(func(): return clock.minute_of_day() >= 12 * 60 + 10, 30.0)
	check(main.housing_system.count_at_home() == 0, "休日の入居者は12時までに出かける")
	clock.set_time(6, 23, 58)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 6, 10.0)
	var report = main.economy_system.last_report
	check(report.get("rent") == 670000, "休日もたどり着けるオフィス67マスの賃料は入る")
	check(report.get("garbage") == 1, "休日はオフィスからゴミが出ない（住宅の1だけ）")
	
	# 8日目（月）: また出勤する
	clock.set_time(8, 7, 59)
	Engine.time_scale = 8.0
	await wait_until(func(): return clock.minute_of_day() >= 10 * 60, 30.0)
	Engine.time_scale = 1.0
	clock.set_process(false)
	check(main.commute_system.count_at_office() == 67, "月曜日はまた67人が出勤する")
	return true

# ---------------------------------------------------
# シナリオ18: 結婚式場・イベントホール（休日の大勢の来客）
# x=8 に y=13〜18 のシャフト、1階の右隣(9,18)に結婚式場、上の階(7,13)にイベントホール。
# イベントホールの来客はエレベーターで上がる。
# ---------------------------------------------------
func run_event_scenario() -> bool:
	print("[シナリオ] 結婚式場・イベントホール")
	main.funds = 10000000
	var events = main.event_system
	var clock = main.clock
	await click_button(main.mode_buttons["elevator"])
	for y in range(18, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	var wedding := Vector2i(9, 18)
	var hall := Vector2i(7, 13)
	await click_button(main.mode_buttons["wedding"])
	await click_cell(wedding, MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["event_hall"])
	await click_cell(hall, MOUSE_BUTTON_LEFT)
	check(main.funds == 10000000 - 6 * 100000 - 1000000 - 800000, "結婚式場100万円・イベントホール80万円がかかる")
	
	# 平日（月曜日）は催しがない
	clock.set_time(1, 9, 59)
	clock.set_process(true)
	Engine.time_scale = 16.0
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
	check(events.revenue_by_day.get(6, 0) == 12 * 10000 + 15 * 3000, "来客の料金は12万円＋4.5万円")
	
	clock.set_time(6, 23, 58)
	await wait_until(func(): return main.economy_system.last_report.get("day") == 6, 10.0)
	Engine.time_scale = 1.0
	clock.set_process(false)
	check(main.economy_system.last_report.get("event") == 165000, "決算にイベントの売上16.5万円が入る")
	check(main.message_label.text.contains("イベント +165,000円"), "決算のメッセージにイベントの売上が出る")
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
	check(main.ground_y == 18, "起動時の一番下の階(y=18)が1階になる")
	await click_button(main.mode_buttons["elevator"])
	for y in range(19, 12, -1):
		await click_cell(Vector2i(8, y), MOUSE_BUTTON_LEFT)
	await click_button(main.mode_buttons["office"])
	for ox in range(5, 8):
		await click_cell(Vector2i(ox, 13), MOUSE_BUTTON_LEFT)
	
	# 地下鉄駅は地下にしか建てられない
	await click_button(main.mode_buttons["subway"])
	await click_cell(Vector2i(9, 18), MOUSE_BUTTON_LEFT)
	check(main.is_cell_empty(Vector2i(9, 18)), "1階には地下鉄駅を建てられない")
	check(main.message_label.text.contains("地下鉄駅は地下（1階より下）にしか建てられません"), "建てられない理由がメッセージで出る")
	var station := Vector2i(9, 19)
	await click_cell(station, MOUSE_BUTTON_LEFT)
	check(main.get_building_type(station) == "subway", "地下(y=19)には地下鉄駅を建てられる")
	check(main.get_entrance() == Vector2i(-8, 18), "地下に建物ができても、1階の入口は変わらない")
	check(main.get_entrances() == [Vector2i(-8, 18), station], "入口は1階の入口と地下鉄駅の2つ")
	check(main.nearest_entrance(Vector2i(6, 13)) == station, "上の階のオフィスからは地下鉄駅の方が近い")
	check(main.nearest_entrance(Vector2i(-6, 18)) == Vector2i(-8, 18), "1階の左寄りのオフィスからは1階の入口の方が近い")
	await capture("subway_01_built")
	
	# 平日の朝: それぞれ近い入口から出勤してくる
	var first_cells := {}
	main.clock.set_time(1, 7, 59)
	main.clock.set_process(true)
	Engine.time_scale = 8.0
	while main.clock.minute_of_day() < 10 * 60:
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
		elif first_cells[r] == Vector2i(-8, 18):
			from_main += 1
	check(from_station > 0 and from_main > 0, "地下鉄駅と1階の入口の両方から社員が来る（駅 %d人・1階 %d人）" % [from_station, from_main])
	check(from_station + from_main == 67, "67人全員がどちらかの入口から来る")
	check(main.commute_system.count_at_office() == 67, "10時には67人全員がオフィスに着いている")
	
	# ★4の条件に地下鉄駅がある
	main.rating_system.stars = 3
	check(main.rating_system.missing_for_next() == ["人口250"], "★4の条件（人口250・地下鉄駅）のうち、地下鉄駅は満たしている")
	main.rating_system.stars = 1
	return true

# 指定した日の朝から全員を出勤させ、その日の決算まで時計を進める
func run_day(day: int) -> void:
	main.clock.set_time(day, 7, 59)
	main.clock.set_process(true)
	Engine.time_scale = 8.0
	await wait_until(func(): return main.clock.minute_of_day() >= 10 * 60, 30.0)
	main.clock.set_time(day, 23, 58)
	await wait_until(func(): return main.economy_system.last_report.get("day") == day, 10.0)
	Engine.time_scale = 1.0
	main.clock.set_process(false)

func count_rides(path: Array[Vector2i]) -> int:
	var rides := 0
	for i in path.size() - 1:
		if main.is_elevator_ride(path[i], path[i + 1]):
			rides += 1
	return rides

func hover_cell(cell: Vector2i) -> void:
	var tile_map: TileMapLayer = main.tile_map
	var motion := InputEventMouseMotion.new()
	motion.position = tile_map.get_global_transform_with_canvas() * tile_map.map_to_local(cell)
	motion.global_position = motion.position
	root.push_input(motion)
	await wait_frames(2)

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
