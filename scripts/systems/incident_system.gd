extends Node

# ---------------------------------------------------
# 事件（トラブル）：今は爆破予告（テロ）を受け持つ。
#
# ■ 警備員
#   警備室1つにつき1人が常駐する（裏方なので、サービスエレベーターにも乗れる）。
#   事件がないときは警備室で待ち、爆破予告が来ると現場へ向かう。
# ■ 爆破予告（テロ）
#   ★MIN_STARS 以上のビルには、毎日 BOMB_MINUTE に BOMB_CHANCE の確率で予告が届く
#   （日ごとに決まった乱数なので、同じ日なら毎回同じ結果になる）。
#   爆弾はテナント（TARGET_TYPES）1棟にランダムで仕掛けられ、BOMB_LIMIT 分で爆発する。
#   一番近い警備員が現場へ行き、DEFUSE_MINUTES 分かけて解体できれば成功。
#   時間切れだと爆発して、そのテナントが吹き飛ぶ（払い戻しなし。上の階の建物はそのまま残る）。
# ---------------------------------------------------

const GUARD_COLOR := Color(0.45, 0.55, 0.95) # 警備員の服の色（青）
const MIN_STARS := 2        # この評価以上のビルが狙われる
const BOMB_CHANCE := 0.15   # 1日に爆破予告が届く確率
const BOMB_MINUTE := 10 * 60 # 予告が届く時刻
const BOMB_LIMIT := 120.0   # 予告から爆発までの時間（分）
const DEFUSE_MINUTES := 10.0 # 爆弾の解体にかかる時間（分）
# 爆弾が仕掛けられるテナント
const TARGET_TYPES := ["office", "hotel", "hotel_twin", "hotel_suite", "housing", "restaurant", "shop", "cinema", "wedding", "event_hall"]

var world: Node2D # main.gd

var guards := {}    # 警備室（左端のマス） -> {"home": マス, "resident": 警備員}
var bomb = null     # 今の爆破予告 {"cell": 仕掛けられたマス, "left": 残り時間（分）, "defuse_left": 解体の残り, "guard": 向かっている警備員}
var bomb_day := 0   # 最後に予告の判定をした日

func setup(p_world: Node2D) -> void:
	world = p_world

# 警備室の数に合わせて、警備員を増やしたり減らしたりする
func rebuild() -> void:
	var rooms: Array[Vector2i] = world.find_units_of_type("security")
	for origin in rooms:
		if not guards.has(origin) or not is_instance_valid(guards[origin].resident):
			var guard = world.spawn_resident(origin)
			guard.base_color = GUARD_COLOR
			guard.staff = true # 裏方（サービスエレベーターに乗れる）
			guards[origin] = {"home": origin, "resident": guard}
	for origin in guards.keys():
		if not rooms.has(origin):
			if is_instance_valid(guards[origin].resident):
				guards[origin].resident.queue_free()
			guards.erase(origin)

func guard_count() -> int:
	return guards.size()

# 爆破予告が出ているか
func has_bomb() -> bool:
	return bomb != null

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	var minutes: float = world.clock.last_advance # このフレームで進んだゲーム内の分数
	if bomb_day != day and now >= BOMB_MINUTE:
		bomb_day = day
		if not has_bomb() and roll_bomb(day):
			start_bomb(pick_target(day))
	if has_bomb():
		process_bomb(minutes)

# その日に爆破予告が届くか（日ごとに決まった乱数）
func roll_bomb(day: int) -> bool:
	if world.rating_system.stars < MIN_STARS:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "bomb"])
	return rng.randf() < BOMB_CHANCE

# 爆弾を仕掛けるテナントを選ぶ（なければnull）
func pick_target(day: int):
	var targets: Array[Vector2i] = []
	for type in TARGET_TYPES:
		targets.append_array(world.find_units_of_type(type))
	if targets.is_empty():
		return null
	targets.sort() # 並び順を決めてから選ぶ（同じ日なら同じ結果になる）
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "target"])
	return targets[rng.randi_range(0, targets.size() - 1)]

# 爆破予告を始める（テストからも呼ぶ）
func start_bomb(cell) -> void:
	if cell == null or world.is_cell_empty(cell):
		return
	bomb = {"cell": cell, "left": BOMB_LIMIT, "defuse_left": DEFUSE_MINUTES, "guard": null}
	world.show_message("爆破予告！ %s の%sに爆弾が仕掛けられました（残り%d分）。警備員が向かいます"
		% [world.get_floor_name(cell.y), world.BUILDINGS[world.get_building_type(cell)].name, int(BOMB_LIMIT)])
	send_guard()

# 一番近い警備員を現場へ向かわせる
func send_guard() -> void:
	var best = null
	var best_length := 0
	for origin in guards:
		var guard = guards[origin].resident
		if not is_instance_valid(guard):
			continue
		var path: Array[Vector2i] = world.find_path(guard.cell, bomb.cell, true)
		if not path.is_empty() and (best == null or path.size() < best_length):
			best = guard
			best_length = path.size()
	if best == null:
		world.show_message("爆弾のところへ行ける警備員がいません！ 警備室を建てておきましょう")
		return
	bomb.guard = best
	best.go_to(bomb.cell)

func process_bomb(minutes: float) -> void:
	# 爆弾が仕掛けられた建物がなくなった（撤去された）ら、予告は終わり
	if world.is_cell_empty(bomb.cell):
		bomb = null
		return
	bomb.left -= minutes
	var guard = bomb.guard
	if is_instance_valid(guard) and guard.cell == bomb.cell and not guard.is_moving():
		# 現場に着いた警備員が解体する
		bomb.defuse_left -= minutes
		if bomb.defuse_left <= 0.0:
			defused()
			return
	elif not is_instance_valid(guard):
		send_guard() # 警備員がいなくなったら、ほかの警備員を呼ぶ
	if bomb.left <= 0.0:
		explode()

# 解体成功: 警備員は警備室に戻る
func defused() -> void:
	var guard = bomb.guard
	bomb = null
	world.show_message("警備員が爆弾を解体しました！ ビルは無事です")
	send_guards_home(guard)

# 時間切れ: テナントが吹き飛ぶ
func explode() -> void:
	var cell: Vector2i = bomb.cell
	var name: String = world.BUILDINGS[world.get_building_type(cell)].name
	var guard = bomb.guard
	bomb = null
	world.destroy_unit(cell)
	world.show_message("爆発！ %s の%sが吹き飛びました" % [world.get_floor_name(cell.y), name])
	send_guards_home(guard)

# 警備員を警備室へ帰す
func send_guards_home(guard) -> void:
	if not is_instance_valid(guard):
		return
	for origin in guards:
		if guards[origin].resident == guard:
			guard.go_to(guards[origin].home)
			return

# カーソルや上部バーの表示用
func get_bomb_text() -> String:
	if not has_bomb():
		return ""
	return "爆破予告！ %s に爆弾（残り%d分）" % [world.get_floor_name(bomb.cell.y), int(bomb.left)]
