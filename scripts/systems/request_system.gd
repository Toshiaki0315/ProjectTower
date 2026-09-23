extends Node2D

# ---------------------------------------------------
# テナントからの頼みごと：ときどきテナントが、ビルの困りごとをかなえてほしいと頼んでくる。
#   毎朝 REQUEST_MINUTE に、頼みごとが出ていなければ REQUEST_CHANCE の確率で1件届く
#   （日ごとに決まった乱数。2日目から）。頼みの中身は、そのビルの今の困りごとから選ぶ（KINDS）:
#     rating     … 評価が「良い」でないオフィスが、評価を良くしてほしいと頼む
#     restaurant … 上下 RESTAURANT_FLOORS 階以内に行ける飲食店がないオフィスが、近くに店がほしいと頼む
#     quiet      … 騒音で評価が下がっている住宅が、静かにしてほしいと頼む
#     clean      … 衛生が悪化しているときに、テナントがきれいにしてほしいと頼む
#     garden     … ★2以上で屋上庭園がないときに、テナントが屋上庭園がほしいと頼む
#   REQUEST_DAYS 日以内（その日を含めて3回の決算まで）にかなえると、お礼（reward）が入る。
#   かなえられなかったら、頼んだテナントの評価の「悪い日」が1日増える（退去に近づく）。
#   頼んだテナントがいなくなったら（撤去・退去）、頼みは取り下げられる。
# 頼んでいる部屋の上には「!」の吹き出しを出す（TileMapLayerの子。座標はタイルマップ座標系）。
# セーブには残さない（読み込むと取り下げ）。
# ---------------------------------------------------

const REQUEST_CHANCE := 0.35
const REQUEST_MINUTE := 9 * 60
const REQUEST_DAYS := 3
const RESTAURANT_FLOORS := 2
const RESTAURANT_TYPES := ["restaurant", "fastfood"]
# short: 吹き出し・カーソルの説明に出す短い文 / text: 頼みが届いたときのメッセージ / reward: お礼
const KINDS := {
	"rating": {"short": "評価を良くしてほしい", "text": "社員の不満を減らして、評価を「良い」にしてほしい", "reward": 200000},
	"restaurant": {"short": "近くに飲食店がほしい", "text": "上下%d階以内に、歩いて行ける飲食店かファストフードがほしい" % RESTAURANT_FLOORS, "reward": 150000},
	"quiet": {"short": "静かにしてほしい", "text": "うるさくて落ち着かない。まわりを静かにしてほしい", "reward": 150000},
	"clean": {"short": "ビルをきれいにしてほしい", "text": "ビルが汚れている。ゴミ処理場を増やして、きれいにしてほしい", "reward": 200000},
	"garden": {"short": "屋上庭園がほしい", "text": "屋上庭園で休みたい。屋上に庭園を作ってほしい", "reward": 250000},
}
const BUBBLE_COLOR := Color(1.0, 1.0, 1.0)
const MARK_COLOR := Color(0.9, 0.2, 0.2)

var world: Node2D # main.gd
# 今の頼みごと（なければnull）: {"kind": 種類, "origin": 頼んだテナント（左端のマス）, "type": その建物の種類,
#   "records": "offices" か "homes"（tenant_system のどの評価か）, "deadline": この日の決算までにかなえる}
var request = null
var request_day := 0 # 最後に頼みごとの判定をした日

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 9 # テナントの評価のマーク（9）と同じ高さ。住人より奥

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	if request_day != day and world.clock.minute_of_day() >= REQUEST_MINUTE:
		request_day = day
		if request == null and day >= 2 and roll(day):
			var choice = pick(day)
			if choice != null:
				start(choice[0], choice[1], choice[2], day)
	queue_redraw()

# その日に頼みごとが届くか（日ごとに決まった乱数）
func roll(day: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "request"])
	return rng.randf() < REQUEST_CHANCE

# 今のビルで出せる頼みごとの一覧 [[種類, 頼むテナント, "offices"/"homes"], ...]
func candidates() -> Array:
	var tenants = world.tenant_system
	var list: Array = []
	var requesters: Array = [] # 建物全体の頼み（衛生・屋上庭園）を出せるテナント
	var offices: Array = tenants.offices.keys().filter(func(o): return is_present(o, "offices"))
	offices.sort()
	for origin in offices:
		requesters.append([origin, "offices"])
		if tenants.offices[origin].rating != tenants.Rating.GOOD:
			list.append(["rating", origin, "offices"])
		if not has_restaurant_near(origin):
			list.append(["restaurant", origin, "offices"])
	var homes: Array = tenants.homes.keys().filter(func(o): return is_present(o, "homes"))
	homes.sort()
	for origin in homes:
		requesters.append([origin, "homes"])
		if world.noise_system.noise_stress(origin) > 0.0:
			list.append(["quiet", origin, "homes"])
	if not requesters.is_empty():
		if world.economy_system.pollution > 0:
			list.append(["clean", requesters[0][0], requesters[0][1]])
		if world.rating_system.stars >= 2 and world.find_units_of_type("garden").is_empty():
			list.append(["garden", requesters[-1][0], requesters[-1][1]])
	return list

# 出す頼みごとを1つ選ぶ（日ごとに決まった乱数。なければnull）
func pick(day: int):
	var list := candidates()
	if list.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "request_pick"])
	return list[rng.randi_range(0, list.size() - 1)]

# 頼みごとを出す（テストからも呼ぶ）
func start(kind: String, origin: Vector2i, records: String, day: int) -> void:
	request = {"kind": kind, "origin": origin, "type": world.get_building_type(origin), "records": records,
		"deadline": day + REQUEST_DAYS - 1}
	world.audio_system.play("chime")
	world.show_message("%sから頼みごと:「%s」（%d日以内・お礼 %s）" % [tenant_name(), KINDS[kind].text, REQUEST_DAYS,
		world.money_text(KINDS[kind].reward)])

# 頼んだテナントが、まだその場所にいるか（撤去・退去していないか）
func is_present(origin: Vector2i, records: String) -> bool:
	var record = world.tenant_system.get(records).get(origin)
	if record == null or record.get("vacant", false):
		return false
	if not world.building_grid.has(origin) or world.building_grid[origin].origin != origin:
		return false
	if records == "homes":
		return world.housing_system.homes.has(origin) and world.housing_system.homes[origin].moved_in
	return true

# 上下 RESTAURANT_FLOORS 階以内に、歩いて行ける飲食店・ファストフードがあるか
func has_restaurant_near(origin: Vector2i) -> bool:
	for type in RESTAURANT_TYPES:
		for unit in world.find_units_of_type(type):
			if absi(unit.y - origin.y) <= RESTAURANT_FLOORS and not world.find_path(origin, unit).is_empty():
				return true
	return false

# 頼みごとがかなっているか
func is_met() -> bool:
	var origin: Vector2i = request.origin
	match request.kind:
		"rating":
			return world.tenant_system.offices[origin].rating == world.tenant_system.Rating.GOOD
		"restaurant":
			return has_restaurant_near(origin)
		"quiet":
			return world.noise_system.noise_stress(origin) <= 0.0
		"clean":
			return world.economy_system.pollution == 0
		"garden":
			return not world.find_units_of_type("garden").is_empty()
	return false

# 毎日の決算のあと（テナントの評価を決めた後）に呼ばれる: かなったか・期限が切れたかを確かめる
func check_day(day: int) -> void:
	if request == null:
		return
	var name := tenant_name()
	if request.type != world.get_building_type(request.origin) or not is_present(request.origin, request.records):
		world.show_message("%sがいなくなったので、頼みごと「%s」は取り下げられました" % [name, KINDS[request.kind].short])
		request = null
		return
	if is_met():
		var reward: int = KINDS[request.kind].reward
		world.funds += reward
		world.update_funds_display()
		world.audio_system.play("money")
		world.show_message("頼みごとをかなえました！ %sからお礼 %s が届きました" % [name, world.money_text(reward)])
		request = null
		return
	if day >= request.deadline:
		var record: Dictionary = world.tenant_system.get(request.records)[request.origin]
		record.bad_days += 1 # 退去に1日近づく
		world.show_message("頼みごと「%s」を%d日以内にかなえられず、%sはがっかりしています（評価の悪い日が1日増えました）"
			% [KINDS[request.kind].short, REQUEST_DAYS, name])
		request = null

# 頼んだテナントが、今もその場所にいるか（撤去して別の建物を建て直していたら、決算で取り下げるまで吹き出しを出さない）
func is_requester_here() -> bool:
	return request != null and world.building_grid.has(request.origin) \
		and world.building_grid[request.origin].origin == request.origin and world.get_building_type(request.origin) == request.type

# 頼んだテナントの呼び名（例: 3階のオフィス）
func tenant_name() -> String:
	return "%sの%s" % [world.get_floor_name(request.origin.y), world.BUILDINGS[request.type].name]

# 読み込んだときなどに、頼みごとを取り下げる
func reset() -> void:
	request = null
	request_day = 0

# あと何日（今日を含めて何回の決算まで）
func days_left() -> int:
	return maxi(request.deadline - world.clock.day + 1, 0)

# ビルの状況に出す文（頼みごとがなければ ""）
func get_status_text() -> String:
	if request == null:
		return ""
	return "頼みごと: %s「%s」（あと%d日・お礼 %s）" % [tenant_name(), KINDS[request.kind].short, days_left(),
		world.money_text(KINDS[request.kind].reward)]

# カーソルの説明に出す文（そのマスのテナントが頼んでいなければ ""）
func get_cell_text(cell: Vector2i) -> String:
	if not is_requester_here() or not world.building_grid.has(cell) or world.building_grid[cell].origin != request.origin:
		return ""
	return "頼みごと:「%s」あと%d日" % [KINDS[request.kind].short, days_left()]

# 頼んでいる部屋の右上に、「!」の吹き出しを描く（7×7ドットに、しっぽ）
func _draw() -> void:
	if not is_requester_here():
		return
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	var cells: Array[Vector2i] = world.get_unit_cells(request.origin)
	var right := cells[0]
	for c in cells:
		if c.y == request.origin.y and c.x > right.x:
			right = c
	var p := Vector2(right) * tile_size + Vector2(tile_size.x - 9, 1)
	draw_rect(Rect2(p - Vector2.ONE, Vector2(9, 9)), Color(0, 0, 0, 0.6)) # 縁
	draw_rect(Rect2(p, Vector2(7, 7)), BUBBLE_COLOR)
	draw_rect(Rect2(p + Vector2(1, 7), Vector2(2, 1)), BUBBLE_COLOR) # 吹き出しのしっぽ
	draw_rect(Rect2(p + Vector2(3, 1), Vector2(1, 3)), MARK_COLOR) # 「!」
	draw_rect(Rect2(p + Vector2(3, 5), Vector2(1, 1)), MARK_COLOR)
