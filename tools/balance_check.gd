extends SceneTree

# ---------------------------------------------------
# バランスの計測：ふつうに遊んだときの伸び方を測る。
#
# 実行方法（ウィンドウ付きで起動する。画面の更新が要るため --headless では不可）:
#   godot --path . -s res://tools/balance_check.gd -- [日数]
#
# やること: 資金の範囲でオフィスを増やしていく素朴な遊び方を自動でくり返し、
#   毎日の決算のあとに 資金・人口・★・退去・目標 を1行ずつ表示する。
#   数字（建設費・賃料・維持費・目標の期限など）を見直すのに使う。
# ---------------------------------------------------

const GROUND := 18        # 1階のy
const LOBBY_LEFT := -8    # ロビーの左端
const LOBBY_RIGHT := 15   # ロビーの右端
const SHAFT_X := 8        # エレベーターのシャフトの列
# オフィスを建てる左端の位置（シャフトに近い側から埋めていく。途切れると通勤できないため）
const OFFICE_XS := [4, 0, -4, -8, 9]

var main: Node2D
var days := 60

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		days = int(args[0])
	root.mouse_passthrough = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0 # 上限を外して、できるだけ速く回す（1フレームで進む分数には上限があるため）

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	main.start_game()
	main.tutorial_system.finished = true
	build_start()

	print("日付\t資金\t人口\t★\t合計収支\t退去\t空室\t目標")
	Engine.time_scale = 60.0
	var last_day := 0
	while main.clock.day <= days:
		# 決算が終わったら、その日の結果を1行出して、資金の範囲で建て増す
		if main.economy_system.last_report.get("day", 0) != last_day and not main.economy_system.last_report.is_empty():
			last_day = main.economy_system.last_report.day
			report_day()
			grow()
		await process_frame
	Engine.time_scale = 1.0
	print("計測おわり（%d日）" % days)
	quit()

# 最初のビル: ロビー・シャフト・2階のオフィス
func build_start() -> void:
	# ロビーはシャフトの列を空けて敷き、そこに1階からエレベーターを積む
	build_row("lobby", LOBBY_LEFT, SHAFT_X - 1, GROUND)
	build_row("lobby", SHAFT_X + 1, LOBBY_RIGHT, GROUND)
	for y in range(GROUND, GROUND - 4, -1):
		build("elevator", Vector2i(SHAFT_X, y))
	build("office", Vector2i(4, GROUND - 1))
	build("office", Vector2i(0, GROUND - 1))

# その日にできる範囲で建て増す（ふつうの遊び方に近い手順）
func grow() -> void:
	# ★の条件になる設備を先にそろえる
	for type in ["security", "recycling", "medical"]:
		if main.find_units_of_type(type).is_empty() and main.funds > main.BUILDINGS[type].cost * 3:
			place_facility(type)
			return
	# 社員が増えてきたら、カゴを足す（待ち時間が延びてテナントが出ていかないように）
	var cars: int = main.elevator_system.get_cars_at(Vector2i(SHAFT_X, GROUND)).size()
	if cars < main.elevator_system.MAX_CARS and main.commute_system.workers.size() > cars * 12 \
			and main.funds > main.elevator_system.CAR_COST * 2:
		main.elevator_system.add_car(Vector2i(SHAFT_X, GROUND))
		return
	# オフィスを1棟増やす（必要ならシャフトを伸ばす）
	if main.funds < main.BUILDINGS.office.cost + 100000: # 少し手元を残して建てる
		return
	for y in range(GROUND - 1, GROUND - 20, -1):
		for x in OFFICE_XS:
			var cell := Vector2i(x, y)
			if main.get_build_problem(cell, "office") == "":
				extend_shaft(y)
				build("office", cell)
				return

# シャフトをその階まで伸ばす
func extend_shaft(y: int) -> void:
	for shaft_y in range(GROUND - 1, y - 1, -1):
		if main.is_cell_empty(Vector2i(SHAFT_X, shaft_y)):
			build("elevator", Vector2i(SHAFT_X, shaft_y))

# 設備は、建てられる一番下の階に置く
func place_facility(type: String) -> void:
	for y in range(GROUND - 1, GROUND - 20, -1):
		for x in OFFICE_XS:
			var cell := Vector2i(x, y)
			if main.get_build_problem(cell, type) == "":
				extend_shaft(y)
				build(type, cell)
				return

func build(type: String, cell: Vector2i) -> void:
	main.select_mode(type)
	main.build_at(cell)

func build_row(type: String, from_x: int, to_x: int, y: int) -> void:
	main.select_mode(type)
	for x in range(from_x, to_x + 1):
		main.build_at(Vector2i(x, y))

func report_day() -> void:
	var report: Dictionary = main.economy_system.last_report
	var tenants = main.tenant_system
	var goal = main.goal_system.current()
	print("%s\t%s\t%d\t%d\t%s\t%d\t%d\t%s" % [
		main.clock.date_text(report.day), main.format_money(main.funds), main.rating_system.population(),
		main.rating_system.stars, main.format_money(report.total, true),
		tenants.count_about_to_leave(), tenants.count_vacant(),
		"達成" if goal == null else goal.name.substr(0, 18)])
