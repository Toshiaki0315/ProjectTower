extends SceneTree

# ---------------------------------------------------
# ★5までの通しプレイの計測：ふつうのプレイヤーに近い手順で、更地から★5（タワー完成）をめざして自動で遊び、
# 毎日の決算のあとに 資金・人口・★・収支・退去しそうなテナント・空室・ゴミ・目標 を1行ずつ表示する。
# 最後に、★が上がった日と、180日目までに★5に届いたかをまとめて出す。難しさ（お金・人口・エレベーター）の見直しに使う。
#
# 実行方法（ウィンドウ付きで起動する。画面の更新が要るため --headless では不可）:
#   godot --path . -s res://tools/playthrough_check.gd -- [日数（省略すると180）] [最初の資金（省略するとゲームのまま）]
# 遊んでいるセーブデータには触らない（オートセーブを止めてから始める）。
#
# ビルの形（1階は y=18。左右とも同じ列に建て増す）:
#   地上: 1階はロビー（はじめは x=-8〜7、お金ができたら x=12〜22 まで広げる）。x=8〜10 にエレベーター
#         （はじめは1本。人口が増えたら SHAFT_POPULATION に合わせて足す）。x=11 は2階へ上がる階段。
#         2階: 左にオフィス4棟、右にスイート（VIP用。1階から階段で待たずに行ける）・ハウスキーパー室・結婚式場。
#         3階から上: OFFICE_FLOORS 階まではオフィス、その上は住宅（通勤のラッシュが分かれるように）。
#         一番上の階の屋根に展望台。
#   地下: 地下1〜4階に警備室・メディカルセンター・ゴミ処理場（ゴミの量に合わせて足す）、地下5階に地下鉄駅。
# ---------------------------------------------------

const GROUND := 18
const LOBBY_LEFT := -8
const LOBBY_RIGHT := 22
const SHAFT_XS := [8, 9, 10] # エレベーターの列（1本目・2本目・3本目）
const SHAFT_POPULATION := [0, 150, 300] # この人口になったら、その本数目のエレベーターを建てる
const STAIRS_X := 11       # 2階のスイートへ上がる階段（1階）
const OFFICE_FLOORS := 16  # この階までオフィス、その上は住宅
# 部屋は、エレベーターに近い側から外へ建てる（間が空くと、遠い部屋まで歩いて行けないため）
const LEFT_OFFICES := [4, 0, -4, -8]
const RIGHT_OFFICES := [11, 15, 19]
const LEFT_HOMES := [4, 1, -2, -5, -8] # 住宅は横3マス。x=7 は空きフロアで埋めて、エレベーターまで歩けるようにする
const RIGHT_HOMES := [11, 14, 17, 20]
const RESERVE := 300000    # 手元に残しておくお金（急な出費のため）
const CARS_PER_PERSON := 30 # 人口このくらいにつき、カゴを1台足す
const FLOORS_PER_GUARD := 5 # この階数ごとに警備室を1つ置く（火事を早く消せるように）
const UNHAPPY_LIMIT := 0.08 # 不満なテナントがこの割合を超えたら、建て増しを止める

var main: Node2D
var days := 180
var start_funds := -1 # 最初の資金（2つ目の引数。-1ならゲームのまま）
var star_days := {}        # ★ -> 上がった日
var basement_slots: Array = [] # 地下に設備を置ける場所 [y, 左端のx, 横幅] の残り

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		days = int(args[0])
	if args.size() > 1:
		start_funds = int(args[1])
	root.mouse_passthrough = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	main.save_system.autosave_enabled = false # 遊んでいるオートセーブを上書きしない
	main.start_game()
	main.tutorial_system.finished = true
	if start_funds >= 0:
		main.funds = start_funds
	build_start()

	print("日付\t資金\t人口\t★\t収支\t退去間近\t空室\t不満\tゴミ/処理能力\t目標")
	Engine.time_scale = 60.0
	var last_day := 0
	while main.clock.day <= days:
		if main.economy_system.last_report.get("day", 0) != last_day and not main.economy_system.last_report.is_empty():
			last_day = main.economy_system.last_report.day
			if not star_days.has(main.rating_system.stars):
				star_days[main.rating_system.stars] = last_day
			report_day()
			grow()
		await process_frame
	Engine.time_scale = 1.0
	print("---")
	for star in range(2, main.rating_system.MAX_STARS + 1):
		print("★%d: %s" % [star, ("%d日目" % star_days[star]) if star_days.has(star) else "届かず"])
	print("%d日目の時点: ★%d・人口%d・資金%s・目標%s" % [days, main.rating_system.stars, main.rating_system.population(),
		main.money_text(main.funds), "すべて達成" if main.goal_system.cleared else main.goal_system.current().name])
	quit()

# 最初のビル: ロビーの左半分・エレベーター1本・2階のオフィス2棟
func build_start() -> void:
	for x in range(LOBBY_LEFT, SHAFT_XS[0]):
		build("lobby", Vector2i(x, GROUND))
	build("elevator", Vector2i(SHAFT_XS[0], GROUND))
	extend_shafts(GROUND - 1)
	build("office", Vector2i(4, GROUND - 1))
	build("office", Vector2i(0, GROUND - 1))
	# 地下に設備を置ける場所（上から順に使う。エレベーターの列は飛ばす。右側はロビーを広げてから）
	for y in range(GROUND + 1, GROUND + 5):
		basement_slots.append([y, LOBBY_LEFT, SHAFT_XS[0] - LOBBY_LEFT])          # 左側（x=-8〜7）
		basement_slots.append([y, STAIRS_X, LOBBY_RIGHT - STAIRS_X + 1])           # 右側（x=11〜22）

# ロビーを右半分に広げる（エレベーター3本ぶんの列と、2階へ上がる階段も）
func widen_lobby() -> bool:
	if not main.is_cell_empty(Vector2i(LOBBY_RIGHT, GROUND)):
		return false
	var cost: int = main.BUILDINGS.lobby.cost * (LOBBY_RIGHT - STAIRS_X) + main.BUILDINGS.stairs.cost
	if main.funds < cost + RESERVE:
		return false
	build("stairs", Vector2i(STAIRS_X, GROUND))
	for x in range(STAIRS_X + 1, LOBBY_RIGHT + 1):
		build("lobby", Vector2i(x, GROUND))
	return true

# 人口に合わせて、エレベーターを1本足す（全部の階に通す）
func add_shaft_if_needed() -> bool:
	for i in SHAFT_XS.size():
		var x: int = SHAFT_XS[i]
		if not main.is_cell_empty(Vector2i(x, GROUND)):
			continue
		# 人口が増えたとき、または不満なテナントが多い（エレベーターが混んでいる）ときに足す
		if main.rating_system.population() < SHAFT_POPULATION[i] and main.rating_system.unhappy_rate() <= UNHAPPY_LIMIT:
			return false
		var floors := 0
		for cell: Vector2i in main.building_grid:
			if cell.x == SHAFT_XS[0] and main.get_building_type(cell) == "elevator":
				floors += 1
		if main.funds < main.BUILDINGS.elevator.cost * floors + RESERVE:
			return false
		build("elevator", Vector2i(x, GROUND))
		var top := GROUND
		var bottom := GROUND
		for cell: Vector2i in main.building_grid:
			if cell.x == SHAFT_XS[0] and main.get_building_type(cell) == "elevator":
				top = mini(top, cell.y)
				bottom = maxi(bottom, cell.y)
		extend_shafts(top)
		extend_shafts(bottom)
		return not main.is_cell_empty(Vector2i(x, GROUND)) # 建てられなかったら、ほかの建て増しに進む
	return false

# 毎日の決算のあとに、お金の範囲で建て増す（1日に何回でも）
func grow() -> void:
	for i in 30:
		if not grow_once():
			return

# 1つ建てる。建てられたら true
func grow_once() -> bool:
	var stars: int = main.rating_system.stars
	var missing: Array[String] = main.rating_system.missing_for_next()
	# 火事や爆発の焼け跡は、撤去して建て直せるようにする
	if clear_ruin():
		return true
	# 次の★の条件になる設備を先にそろえる。警備室はビルの高さに合わせて足す
	if (missing.has("警備室") or needs_guard()) and try_basement("security"):
		return true
	if missing.has("メディカルセンター") and try_basement("medical"):
		return true
	if (missing.has("ゴミ処理場") or needs_recycling()) and try_basement("recycling"):
		return true
	if stars >= 3 and missing.has("地下鉄駅") and try_subway():
		return true
	if stars >= 3 and main.find_units_of_type("hotel_suite").is_empty():
		return try_second_floor("hotel_suite", STAIRS_X)
	if stars >= 3 and main.find_units_of_type("housekeeping").is_empty():
		return try_second_floor("housekeeping", STAIRS_X + 4)
	if stars >= 4 and missing.has("結婚式場") and try_second_floor("wedding", STAIRS_X + 6):
		return true
	if stars >= 4 and missing.has("展望台") and main.rating_system.population() >= 450 and try_observatory():
		return true
	if add_shaft_if_needed() or add_car_if_needed():
		return true
	if main.rating_system.population() >= 40 and widen_lobby():
		return true
	# 次の★に満足度が要るとき（★4・★5）は、不満なテナントが増えてきたら、建て増しを止めて落ち着くのを待つ
	if main.rating_system.REQUIREMENTS.get(stars + 1, {}).has("unhappy") and main.rating_system.unhappy_rate() > UNHAPPY_LIMIT:
		return add_any_car()
	return build_next_unit()

# どのシャフトでもよいので、カゴを1台足す（不満なテナントが多いとき）
func add_any_car() -> bool:
	for x in SHAFT_XS:
		var cell := Vector2i(x, GROUND)
		if not main.is_cell_empty(cell) and main.elevator_system.get_add_car_problem(cell) == "" \
				and main.funds > main.elevator_system.CAR_COST + RESERVE:
			main.elevator_system.add_car(cell)
			return true
	return false

# 焼け跡を1つ撤去する（撤去したら true）
func clear_ruin() -> bool:
	for cell: Vector2i in main.building_grid:
		if main.get_building_type(cell) == "ruin" and main.funds > main.demolish_fee("ruin") + RESERVE:
			main.demolish_at(cell)
			return true
	return false

# 警備室が足りないか（FLOORS_PER_GUARD 階ごとに1つ）
func needs_guard() -> bool:
	var top := GROUND
	for cell: Vector2i in main.building_grid:
		top = mini(top, cell.y)
	var floors: int = GROUND - top + 1
	return main.find_units_of_type("security").size() < ceili(float(floors) / FLOORS_PER_GUARD)

# ゴミが処理能力を超えそうか（前日の決算のゴミから）
func needs_recycling() -> bool:
	var garbage: int = main.economy_system.last_report.get("garbage", 0)
	return garbage + 10 > main.economy_system.recycling_capacity()

# 人口に合わせてカゴを足す（2本のシャフトに交互に）
func add_car_if_needed() -> bool:
	var cars := 0
	for x in SHAFT_XS:
		if not main.is_cell_empty(Vector2i(x, GROUND)):
			cars += main.elevator_system.get_cars_at(Vector2i(x, GROUND)).size()
	if main.rating_system.population() < cars * CARS_PER_PERSON:
		return false
	for x in SHAFT_XS:
		var cell := Vector2i(x, GROUND)
		if main.is_cell_empty(cell):
			continue
		if main.elevator_system.get_add_car_problem(cell) == "" and main.funds > main.elevator_system.CAR_COST + RESERVE:
			main.elevator_system.add_car(cell)
			return true
	return false

# 次の階の部屋を1つ建てる（下の階から。オフィスの階、その上は住宅の階）
func build_next_unit() -> bool:
	for y in range(GROUND - 1, GROUND - 60, -1):
		var floor_number: int = GROUND - y + 1
		var plan: Array = [] # [種類, 左端のx]
		if floor_number == 2:
			for x in LEFT_OFFICES:
				plan.append(["office", x])
		elif floor_number <= OFFICE_FLOORS:
			for x in LEFT_OFFICES:
				plan.append(["office", x])
			if not main.is_cell_empty(Vector2i(LOBBY_RIGHT, GROUND)): # 右半分はロビーを広げてから
				for x in RIGHT_OFFICES:
					plan.append(["office", x])
		else:
			plan.append(["frame", 7])
			for x in LEFT_HOMES:
				plan.append(["housing", x])
			if not main.is_cell_empty(Vector2i(LOBBY_RIGHT, GROUND)):
				for x in RIGHT_HOMES:
					plan.append(["housing", x])
		for item in plan:
			var cell := Vector2i(item[1], y)
			if not main.is_cell_empty(cell) and main.get_building_type(cell) != "frame":
				continue # もう建っている
			if main.funds < main.BUILDINGS[item[0]].cost + RESERVE:
				return false
			extend_shafts(y)
			if main.get_build_problem(cell, item[0]) == "":
				build(item[0], cell)
				return true
		if floor_number == 2 and not main.is_cell_empty(Vector2i(LOBBY_RIGHT, GROUND)):
			fill_second_floor_right() # 2階の右側は空きフロアで埋めておく（3階から上を支えるため）
	return false

# 2階の右側（スイート・ハウスキーパー室・結婚式場の場所）を空きフロアで埋める
func fill_second_floor_right() -> void:
	for x in range(STAIRS_X, LOBBY_RIGHT + 1):
		if main.is_cell_empty(Vector2i(x, GROUND - 1)):
			build("frame", Vector2i(x, GROUND - 1))

# 2階の右側に建てる（空きフロアの上に建て直す）
func try_second_floor(type: String, x: int) -> bool:
	if main.is_cell_empty(Vector2i(LOBBY_RIGHT, GROUND)):
		return widen_lobby()
	fill_second_floor_right()
	var cell := Vector2i(x, GROUND - 1)
	if main.funds < main.BUILDINGS[type].cost + RESERVE or main.get_build_problem(cell, type) != "":
		return false
	build(type, cell)
	return true

# 地下の空いている場所に設備を建てる
func try_basement(type: String) -> bool:
	var width: int = main.get_width(type)
	if main.funds < main.BUILDINGS[type].cost + RESERVE:
		return false
	for slot in basement_slots:
		if slot[2] < width:
			continue
		var cell := Vector2i(slot[1], slot[0])
		extend_shafts(slot[0])
		if main.get_build_problem(cell, type) == "":
			build(type, cell)
			slot[1] += width
			slot[2] -= width
			return true
	return false

# 地下鉄駅（地下5階。x=4〜7 の真上の地下1〜4階を埋めてから建てる）
func try_subway() -> bool:
	if main.funds < main.BUILDINGS.subway.cost + RESERVE:
		return false
	for y in range(GROUND + 1, GROUND + 5):
		for x in range(4, 8):
			if main.is_cell_empty(Vector2i(x, y)):
				build("frame", Vector2i(x, y))
	extend_shafts(GROUND + 5)
	build("subway", Vector2i(4, GROUND + 5))
	return main.get_building_type(Vector2i(4, GROUND + 5)) == "subway"

# 展望台（一番上の階の屋根に）
func try_observatory() -> bool:
	if main.funds < main.BUILDINGS.observatory.cost + RESERVE:
		return false
	var top := GROUND
	for cell: Vector2i in main.building_grid:
		top = mini(top, cell.y)
	for x in LEFT_OFFICES:
		var cell := Vector2i(x, top - 1)
		if main.get_build_problem(cell, "observatory") == "":
			build("observatory", cell)
			return true
	return false

# 建てたエレベーターのシャフトを、その階まで伸ばす（上にも下にも）
func extend_shafts(y: int) -> void:
	for x in SHAFT_XS:
		if main.is_cell_empty(Vector2i(x, GROUND)):
			continue # まだ建てていないエレベーター
		var step := -1 if y < GROUND else 1
		for shaft_y in range(GROUND, y + step, step):
			if main.is_cell_empty(Vector2i(x, shaft_y)):
				build("elevator", Vector2i(x, shaft_y))

func build(type: String, cell: Vector2i) -> void:
	main.select_mode(type)
	main.build_at(cell)

func report_day() -> void:
	var report: Dictionary = main.economy_system.last_report
	var tenants = main.tenant_system
	var goal = main.goal_system.current()
	print("%s\t%s\t%d\t%d\t%s\t%d\t%d\t%d%%\t%d/%d\t%s" % [
		main.clock.date_text(report.day), main.format_money(main.funds), main.rating_system.population(),
		main.rating_system.stars, main.format_money(report.total, true),
		tenants.count_about_to_leave(), tenants.count_vacant(), int(main.rating_system.unhappy_rate() * 100),
		report.garbage, main.economy_system.recycling_capacity(),
		"達成" if goal == null else goal.name.substr(0, 16)])
