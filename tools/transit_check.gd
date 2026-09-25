extends SceneTree

# ---------------------------------------------------
# エレベーターの輸送の計測：オフィスだけのビルを、輸送の組み方ごとに組み立てて、16倍速で4日動かし、
# 毎日の決算のあとに 不満なテナントの割合（★4・★5の条件）・オフィスの評価・ストレスの平均 を出す。
# 10時（朝の通勤のあと）と19時（帰りのあと）には、シャフトごとの待ち時間と、ストレスの最大が60以上の人数も出す。
# ★4・★5の満足度の条件（不満なテナント ★4は1割以下・★5は2割以下）に、輸送を工夫すれば届くかを確かめるのに使う。
#
# 実行方法（ウィンドウ付きで起動する）:
#   godot --path . -s res://tools/transit_check.gd -- <構成> <下のゾーンのオフィス階数> [<上のゾーンのオフィス階数>] [frames]
# 構成: std3  … 標準エレベーター3本（各4台。全部の階に停まる）
#       large3・large4 … 大型エレベーター3本・4本（各4台）
#       sky・sky3 … 急行2本で1階とスカイロビー（15階）を結び、下のゾーン（2階〜）と上のゾーン（16階〜）を大型2本・3本ずつで
# 例: godot --path . -s res://tools/transit_check.gd -- large3 9（社員252人）/ -- sky3 9 9（社員504人）
# frames を付けると、2日目の朝の通勤の時間帯の1フレームの時間を10分ごとにまとめて出して終わる（重さの確認用）。
# 遊んでいるセーブデータには触らない（オートセーブを止めてから始める）。
# ---------------------------------------------------

const GROUND := 18
const DAYS := 4

var main: Node2D

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var config: String = args[0]
	var low_floors := int(args[1])
	var high_floors := int(args[2]) if args.size() > 2 and args[2].is_valid_int() else 0
	root.mouse_passthrough = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	main.save_system.autosave_enabled = false # 遊んでいるオートセーブを上書きしない
	main.start_game()
	main.tutorial_system.finished = true
	build(config, low_floors, high_floors)
	main.funds = 100000000
	print("構成 %s・オフィス %d階＋%d階・社員 %d人" % [config, low_floors, high_floors, main.find_office_units().size() * 4])
	Engine.time_scale = 16.0
	var last_day := 0
	var printed := {}
	while last_day < DAYS:
		var now: int = main.clock.minute_of_day()
		if args.has("frames") and main.clock.day == 2 and now >= 7 * 60 + 50:
			await frame_log()
			quit()
			return
		for hour in [10, 19]:
			var key := [main.clock.day, hour]
			if now >= hour * 60 and not printed.has(key):
				printed[key] = true
				print_waits(key)
		var report: Dictionary = main.economy_system.last_report
		if not report.is_empty() and report.day != last_day:
			last_day = report.day
			print_day(report)
		await process_frame
	quit()

# シャフトごとの今日の待ち時間と、今日のストレスの最大が60（評価が「悪い」の目安）以上の人数
func print_waits(key: Array) -> void:
	print("  %d日目 %d時: 待ち時間" % key)
	for k in main.elevator_system.wait_stats:
		print("    %s: %s" % [k, main.elevator_system.stats_text(k)])
	var peaks: Array = main.tenant_system.day_peak_stress.values()
	var over := peaks.filter(func(p): return p >= 60.0).size()
	print("    今日のストレスの最大が60以上の人: %d / %d" % [over, peaks.size()])

# 毎日の決算のあと: 不満なテナントの割合・オフィスの評価の内訳・ストレスの平均・衛生の悪化
func print_day(report: Dictionary) -> void:
	var tenants = main.tenant_system
	var counts := {tenants.Rating.GOOD: 0, tenants.Rating.NORMAL: 0, tenants.Rating.BAD: 0}
	var total := 0.0
	for origin in tenants.offices:
		counts[tenants.offices[origin].rating] += 1
		total += tenants.offices[origin].average
	print("%d日目: 不満 %d%%・良い%d 普通%d 悪い%d・ストレス平均 %.0f・衛生の悪化 %d" % [report.day,
		int(round(main.rating_system.unhappy_rate() * 100)), counts[tenants.Rating.GOOD], counts[tenants.Rating.NORMAL],
		counts[tenants.Rating.BAD], total / maxi(tenants.offices.size(), 1), report.pollution])

# y: 階の番号（1階=1）からマスのy
func fy(floor_number: int) -> int:
	return GROUND - floor_number + 1

func build(config: String, low_floors: int, high_floors: int) -> void:
	# シャフト: [種類, 列, 下の階, 上の階]
	var shafts: Array = []
	var top_floor := 1 + low_floors
	var sky := config.begins_with("sky")
	match config:
		"std3":
			for x in [8, 9, 10]:
				shafts.append(["elevator", x, 1, top_floor])
		"large3", "large4":
			for i in (3 if config == "large3" else 4):
				shafts.append(["large_elevator", 8 + i * 2, 1, top_floor])
		"sky", "sky3":
			top_floor = 15 + high_floors
			var locals := 2 if config == "sky" else 3 # ゾーンごとの大型エレベーターの本数
			for x in [8, 9]:
				shafts.append(["express_elevator", x, 1, 15])
			for i in locals:
				shafts.append(["large_elevator", 10 + i * 2, 1, 1 + low_floors])
			for i in locals:
				shafts.append(["large_elevator", 10 + (locals + i) * 2, 15, top_floor])
	var shaft_cells := {}
	var right := 8
	for s in shafts:
		var width := 2 if s[0] == "large_elevator" else 1
		right = maxi(right, s[1] + width)
		for f in range(s[2], s[3] + 1):
			for dx in width:
				shaft_cells[Vector2i(s[1] + dx, fy(f))] = true
	var offices_x := [-8, -4, 0, 4, right, right + 4, right + 8]
	var last_x := right + 11
	for f in range(1, top_floor + 1):
		var y := fy(f)
		var office_floor := f >= 2 and f <= 1 + low_floors or sky and f >= 16 and f <= top_floor
		if f == 1 or (sky and f == 15):
			for x in range(-8, last_x + 1):
				if not shaft_cells.has(Vector2i(x, y)):
					main.place_unit(Vector2i(x, y), "lobby" if f == 1 else "sky_lobby")
		elif office_floor:
			for x in offices_x:
				main.place_unit(Vector2i(x, y), "office")
	for s in shafts:
		var width := 2 if s[0] == "large_elevator" else 1
		for f in range(s[2], s[3] + 1):
			main.place_unit(Vector2i(s[1], fy(f)), s[0])
	# すき間（別のゾーンのシャフトの列など）は空きフロアで埋める
	for f in range(2, top_floor + 1):
		for x in range(-8, last_x + 1):
			if main.is_cell_empty(Vector2i(x, fy(f))):
				main.place_unit(Vector2i(x, fy(f)), "frame")
	# 地下1〜4階: ゴミ処理場（汚れで評価が下がらないように、十分に）
	for y in range(GROUND + 1, GROUND + 5):
		for x in range(-8, last_x - 1, 3):
			main.place_unit(Vector2i(x, y), "recycling")
	main.rebuild_systems()
	for s in shafts:
		for i in 3:
			main.elevator_system.add_car(Vector2i(s[1], fy(s[2])))

# 朝の通勤の時間帯（2日目の7:50〜9:30）の、1フレームごとの時間を10分ごとにまとめて出す
func frame_log() -> void:
	var bucket := -1
	var times: Array = []
	var capped := 0
	var last := Time.get_ticks_usec()
	while main.clock.minute_of_day() < 9 * 60 + 30:
		await process_frame
		var t := Time.get_ticks_usec()
		times.append((t - last) / 1000.0)
		last = t
		if main.clock.last_advance >= main.clock.MAX_MINUTES_PER_FRAME:
			capped += 1
		var b: int = main.clock.minute_of_day() / 10
		if b != bucket:
			if bucket >= 0 and not times.is_empty():
				times.sort()
				var total := 0.0
				for x in times:
					total += x
				print("  %02d:%02d台 フレーム%d 平均%.1fms 中央%.1fms 最大%.1fms 時計の上限に当たった%d・人%d 待っている人%d" % [bucket / 6, bucket % 6 * 10,
					times.size(), total / times.size(), times[times.size() / 2], times[-1], capped,
					main.residents.filter(is_instance_valid).size(),
					main.residents.filter(func(r): return is_instance_valid(r) and r.state == r.State.WAITING).size()])
			bucket = b
			times.clear()
			capped = 0
