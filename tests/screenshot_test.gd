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
	for scenario in [run_build_scenario, run_stairs_scenario, run_camera_scenario, run_ui_scenario, run_elevator_scenario, run_ride_scenario, run_stress_scenario, run_collective_scenario]:
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
	await wait_frames(3)

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
	return true

# ---------------------------------------------------
# シナリオ4: UIバーとマス目の表示
# ---------------------------------------------------
func run_ui_scenario() -> bool:
	print("[シナリオ] UIバーとマス目")
	var overlay = main.grid_overlay
	
	# 上部バーの上をクリックしても、その下のマスには建設されない
	# 最後のモードボタンの右隣（ボタンのない位置）
	var last_button: Button = main.mode_buttons.values().back()
	var bar_pos := Vector2(last_button.get_global_rect().end.x + 40, 15)
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
