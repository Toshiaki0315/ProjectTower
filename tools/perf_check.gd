extends SceneTree

# ---------------------------------------------------
# 重さの計測：人の多い大きなビル（35階・人口およそ550。★5までの通しプレイの終盤と同じくらい）を
# 直接組み立てて、朝の通勤の時間帯に、1フレームにかかる時間を測る。
# そのあと部品ごとに処理（_process）や描画を止めて、どこが重いかを調べる。
#
# 実行方法（ウィンドウ付きで起動する）:
#   godot --path . -s res://tools/perf_check.gd
# 遊んでいるセーブデータには触らない（オートセーブを止めてから始める）。
# ---------------------------------------------------

const GROUND := 18
const TOP_FLOOR := 35
const OFFICE_FLOORS := 16
const SHAFT_XS := [8, 9, 10]
const MEASURE_SECONDS := 3.0

var main: Node2D

func _init() -> void:
	root.mouse_passthrough = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	main.save_system.autosave_enabled = false
	main.start_game()
	main.tutorial_system.finished = true
	build_tower()
	main.rating_system.stars = 5
	# 朝の通勤の時間帯まで進めて、人をビルに入れる
	main.clock.set_time(1, 7, 50)
	Engine.time_scale = 4.0
	var until := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < until and main.clock.minute_of_day() < 9 * 60:
		await process_frame
	print("人口 %d・今ビルにいる人 %d・時刻 %02d:%02d" % [main.rating_system.population(), main.residents.filter(is_instance_valid).size(),
		main.clock.minute_of_day() / 60, main.clock.minute_of_day() % 60])
	await measure("すべて動かす（通勤の時間帯）")
	# ここからは時間を止めて（人が動かないので、同じ状態のまま比べられる）、部品ごとに止めたときの軽さを見る
	Engine.time_scale = 0.0
	var base := await measure("時間を止めて、すべて動かす")
	# 部品ごとに処理を止めて、どれだけ軽くなるかを見る
	for part in ["commute_system", "hotel_system", "housing_system", "visitor_system", "elevator_system", "tenant_system",
			"incident_system", "request_system", "grid_overlay", "lighting", "sky_events", "cinema_screen", "tower_sign", "ui"]:
		var node: Node = main.get(part)
		node.set_process(false)
		var ms := await measure("%s の処理を止める" % part)
		node.set_process(true)
		print("    → %.2fms 軽くなる" % (base - ms))
	# 人の処理と描画
	for r in main.residents:
		if is_instance_valid(r):
			r.set_process(false)
	var no_people := await measure("人の処理（歩く・待つ・乗る）を止める")
	print("    → %.2fms 軽くなる" % (base - no_people))
	for r in main.residents:
		if is_instance_valid(r):
			r.set_process(true)
			r.visible = false
	var hidden := await measure("人を描かない")
	print("    → %.2fms 軽くなる" % (base - hidden))
	for r in main.residents:
		if is_instance_valid(r):
			r.visible = true
	for car in main.elevator_system.cars:
		car.set_process(false)
	var no_cars := await measure("カゴの処理を止める")
	print("    → %.2fms 軽くなる" % (base - no_cars))
	quit()

# MEASURE_SECONDS 秒のあいだの、1フレームの平均の時間（ミリ秒）と、そのうちの処理（_process）の時間
func measure(label: String) -> float:
	await process_frame
	var frames := 0
	var process_total := 0.0
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < MEASURE_SECONDS * 1000000.0:
		await process_frame
		frames += 1
		process_total += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var ms := (Time.get_ticks_usec() - started) / 1000.0 / frames
	print("%s: 1フレーム %.2fms（%.0ffps）・そのうち処理 %.2fms" % [label, ms, 1000.0 / ms, process_total / frames])
	return ms

# 通しプレイの終盤と同じくらいのビルを、お金をかけずに組み立てる
func build_tower() -> void:
	for x in range(-8, 23):
		place("lobby" if not SHAFT_XS.has(x) else "elevator", Vector2i(x, GROUND))
	for y in range(GROUND - 1, GROUND - TOP_FLOOR, -1):
		for x in SHAFT_XS:
			place("elevator", Vector2i(x, y))
		var floor_number: int = GROUND - y + 1
		if floor_number <= OFFICE_FLOORS:
			for x in [-8, -4, 0, 4, 11, 15, 19]:
				place("office", Vector2i(x, y))
		else:
			for x in [-8, -5, -2, 1, 4, 11, 14, 17, 20]:
				place("housing", Vector2i(x, y))
			place("frame", Vector2i(7, y))
			place("frame", Vector2i(23, y))
	for y in range(GROUND + 1, GROUND + 3): # 地下: ゴミ処理場・警備室・メディカルセンター
		for x in SHAFT_XS:
			place("elevator", Vector2i(x, y))
		for x in [-8, -5, -2, 1, 4, 11, 14, 17, 20]:
			place("recycling", Vector2i(x, y))
	main.rebuild_systems()
	for x in SHAFT_XS:
		for i in 3:
			main.elevator_system.add_car(Vector2i(x, GROUND))
	main.funds = 100000000

func place(type: String, cell: Vector2i) -> void:
	main.place_unit(cell, type)
