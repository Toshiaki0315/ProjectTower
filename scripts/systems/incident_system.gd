extends Node

# ---------------------------------------------------
# 事件（トラブル）：爆破予告（テロ）・火災・ゴキブリの大繁殖・埋蔵金の発見を受け持つ。
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
# ■ 火災
#   ★MIN_STARS 以上のビルには、毎日 FIRE_MINUTE に FIRE_CHANCE の確率で出火する。
#   燃えているマスは SPREAD_MINUTES ごとに、隣（左右）と上のマスの建物へ燃え広がる。
#   1マスが BURN_MINUTES 燃え続けると、そのテナントは焼け落ちる（払い戻しなし）。
#   警備員が燃えているマスへ行き、EXTINGUISH_MINUTES 分かけて1マスずつ消し止める。
#   ヘリポートがあると消防ヘリが飛んできて、上の階の火から順に HELI_MINUTES 分で消していく
#   （警備員より速く、高い階に強い）。
#   燃えているマスがなくなれば鎮火。
# ■ ゴキブリの大繁殖
#   衛生の悪化（economy_system.pollution）が ROACH_POLLUTION 以上の日が ROACH_DAYS 日続くと発生し、
#   毎日 ROACH_SPAWN 棟ずつテナントに広がる。
#   ゴキブリがいるテナントは、評価にストレス ROACH_STRESS 相当が足される。
#   ゴミの処理が追いついて悪化が0に戻ると、いなくなる。
# ■ 埋蔵金の発見
#   地下に建物を建てる（＝掘る）と、マスごとに TREASURE_CHANCE の確率で埋蔵金が見つかる。
#   深いほど見つかりやすく、金額も大きい（TREASURE_PER_FLOOR × 深さ）。
#   同じマスで見つかるのは一度だけ（掘ったマスは覚えておく）。
# ---------------------------------------------------

const GUARD_COLOR := Color(0.45, 0.55, 0.95) # 警備員の服の色（青）
const MIN_STARS := 2        # この評価以上のビルが狙われる
const BOMB_CHANCE := 0.15   # 1日に爆破予告が届く確率
const BOMB_MINUTE := 10 * 60 # 予告が届く時刻
const BOMB_LIMIT := 120.0   # 予告から爆発までの時間（分）
const DEFUSE_MINUTES := 10.0 # 爆弾の解体にかかる時間（分）
const FIRE_CHANCE := 0.1       # 1日に出火する確率
const FIRE_MINUTE := 20 * 60   # 出火する時刻
const SPREAD_MINUTES := 20.0   # 隣のマスへ燃え広がるまでの時間（分）
const BURN_MINUTES := 60.0     # 1マスが燃え尽きる（建物が焼け落ちる）までの時間（分）
const EXTINGUISH_MINUTES := 10.0 # 警備員が1マスを消し止めるのにかかる時間（分）
const HELI_MINUTES := 5.0      # 消防ヘリが1マスを消すのにかかる時間（分）
const HELI_SPEED := 90.0       # 消防ヘリの飛ぶ速さ（px/秒）
const HELI_ARRIVE := 6.0       # このくらいまで近づいたら、消火を始める（px）

const ROACH_POLLUTION := 4   # 衛生の悪化がこのレベル以上の日が続くと、ゴキブリが出る
const ROACH_DAYS := 2        # 続く日数
const ROACH_SPAWN := 3       # 1日に広がるテナントの数
const ROACH_STRESS := 15.0   # ゴキブリがいるテナントの評価に足されるストレス
const ROACH_MINUTE := 6 * 60 # 1日の判定をする時刻

const TREASURE_CHANCE := 0.03      # 地下1階のマスを掘ったときに埋蔵金が見つかる確率
const TREASURE_CHANCE_PER_FLOOR := 0.002 # 1階深くなるごとに上がる確率
const TREASURE_CHANCE_MAX := 0.12  # 確率の上限
const TREASURE_PER_FLOOR := 10000  # 見つかる金額（深さ1階につき）
const TREASURE_MAX := 1000000      # 1回に見つかる金額の上限

# 爆弾が仕掛けられるテナント
const TARGET_TYPES := ["office", "hotel", "hotel_twin", "hotel_suite", "housing", "restaurant", "shop", "cinema", "wedding", "event_hall"]

var world: Node2D # main.gd

var guards := {}    # 警備室（左端のマス） -> {"home": マス, "resident": 警備員}
var bomb = null     # 今の爆破予告 {"cell": 仕掛けられたマス, "left": 残り時間（分）, "defuse_left": 解体の残り, "guard": 向かっている警備員}
var bomb_day := 0   # 最後に予告の判定をした日
var fire := {}      # 燃えているマス -> {"burn_left": 焼け落ちるまでの分, "work_left": 消火の残りの分}
var fire_spread_left := 0.0 # 次に燃え広がるまでの分
var heli = null     # 消防ヘリ {"pos": 今の位置, "target": 消しに行くマス, "work_left": 残りの分}
var fire_day := 0   # 最後に出火の判定をした日
var roaches := {}   # ゴキブリがいるテナント（左端のマス） -> true
var roach_days := 0 # 衛生の悪化が続いている日数
var roach_day := 0  # 最後にゴキブリの判定をした日
var dug := {}       # すでに掘った地下のマス -> true（同じマスで2度は見つからない）
var treasure_total := 0 # これまでに見つけた埋蔵金の合計

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

# 火災が起きているか
func has_fire() -> bool:
	return not fire.is_empty()

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
	if fire_day != day and now >= FIRE_MINUTE:
		fire_day = day
		if not has_fire() and roll_fire(day):
			start_fire(pick_target(day))
	if has_fire():
		process_fire(minutes)
	process_heli(minutes) # 火が消えたらヘリは帰る
	if roach_day != day and now >= ROACH_MINUTE:
		roach_day = day
		update_roaches(day)

# その日に爆破予告が届くか（日ごとに決まった乱数）
func roll_bomb(day: int) -> bool:
	if world.rating_system.stars < MIN_STARS:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "bomb"])
	return rng.randf() < BOMB_CHANCE

# その日に出火するか（日ごとに決まった乱数）
func roll_fire(day: int) -> bool:
	if world.rating_system.stars < MIN_STARS:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "fire"])
	return rng.randf() < FIRE_CHANCE

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
	world.audio_system.play("alert")
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

# ---------------------------------------------------
# 火災
# ---------------------------------------------------

# 出火させる（テストからも呼ぶ）
func start_fire(cell) -> void:
	if cell == null or world.is_cell_empty(cell):
		return
	fire.clear()
	burn(cell)
	world.audio_system.play("alert")
	fire_spread_left = SPREAD_MINUTES
	world.show_message("火事だ！ %s の%sから火が出ました。警備員が消火に向かいます"
		% [world.get_floor_name(cell.y), world.BUILDINGS[world.get_building_type(cell)].name])

func burn(cell: Vector2i) -> void:
	fire[cell] = {"burn_left": BURN_MINUTES, "work_left": EXTINGUISH_MINUTES}

func process_fire(minutes: float) -> void:
	# 燃えているマスの建物がなくなったら、その火は消える
	for cell in fire.keys():
		if world.is_cell_empty(cell):
			fire.erase(cell)
	# 警備員を、担当がいない燃えているマスへ向かわせる
	dispatch_guards()
	for cell in fire.keys():
		if not fire.has(cell):
			continue # 建物ごと焼け落ちて、このマスの火はもうない
		var flame: Dictionary = fire[cell]
		# 消火: 警備員がそのマスにいる間だけ進む
		if guard_at(cell) != null:
			flame.work_left -= minutes
			if flame.work_left <= 0.0:
				fire.erase(cell)
				world.show_message("警備員が %s の火を消し止めました" % world.get_floor_name(cell.y))
				continue
		flame.burn_left -= minutes
		if flame.burn_left <= 0.0:
			burn_down(cell)
	# 延焼: 決まった時間ごとに、隣（左右）と上のマスへ広がる
	fire_spread_left -= minutes
	if fire_spread_left <= 0.0:
		fire_spread_left = SPREAD_MINUTES
		spread_fire()
	if not has_fire():
		world.show_message("火は収まりました")

# 燃え尽きたマスのテナントが焼け落ちる
func burn_down(cell: Vector2i) -> void:
	var name: String = world.BUILDINGS[world.get_building_type(cell)].name
	for c in world.get_unit_cells(cell):
		fire.erase(c)
	world.destroy_unit(cell)
	world.show_message("%s の%sが焼け落ちました" % [world.get_floor_name(cell.y), name])

# 燃えているマスから、隣（左右）と上のマスへ燃え広がる
func spread_fire() -> void:
	for cell in fire.keys():
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var next: Vector2i = cell + dir
			if not world.is_cell_empty(next) and not fire.has(next):
				burn(next)

# ---------------------------------------------------
# 消防ヘリ（ヘリポートがあるときだけ飛んでくる）
# ---------------------------------------------------

func has_heli() -> bool:
	return heli != null

# ヘリが消しに行くマス（燃えているマスのうち、一番上の階のもの）
func heli_target():
	var best = null
	for cell in fire:
		if best == null or cell.y < best.y:
			best = cell
	return best

func process_heli(minutes: float) -> void:
	var pads: Array[Vector2i] = world.find_units_of_type("helipad")
	if pads.is_empty():
		heli = null
		return
	var target = heli_target()
	if target == null:
		heli = null
		return
	if not has_heli():
		# ヘリポートの少し上から飛び立つ
		heli = {"pos": world.tile_map.map_to_local(pads[0]) + Vector2(0, -24), "target": target, "work_left": HELI_MINUTES}
	if not fire.has(heli.target):
		heli.target = target
		heli.work_left = HELI_MINUTES
	var goal: Vector2 = world.tile_map.map_to_local(heli.target) + Vector2(0, -12) # マスの少し上でホバリングする
	heli.pos = heli.pos.move_toward(goal, HELI_SPEED * world.get_process_delta_time() * Engine.time_scale)
	if heli.pos.distance_to(goal) > HELI_ARRIVE:
		return
	# 真上から放水して火を消す
	heli.work_left -= minutes
	if heli.work_left <= 0.0:
		var cell: Vector2i = heli.target
		fire.erase(cell)
		heli.work_left = HELI_MINUTES
		world.show_message("消防ヘリが %s の火を消しました" % world.get_floor_name(cell.y))

# 燃えているマスにいる警備員（いなければnull）
func guard_at(cell: Vector2i):
	for origin in guards:
		var guard = guards[origin].resident
		if is_instance_valid(guard) and guard.cell == cell and not guard.is_moving():
			return guard
	return null

# 手が空いている警備員を、まだ誰も向かっていない燃えているマスへ向かわせる
func dispatch_guards() -> void:
	for origin in guards:
		var guard = guards[origin].resident
		if not is_instance_valid(guard) or guard.is_moving() or fire.has(guard.cell):
			continue
		if has_bomb() and bomb.guard == guard:
			continue # 爆弾の解体が先
		var best = null
		var best_length := 0
		for cell in fire:
			var path: Array[Vector2i] = world.find_path(guard.cell, cell, true)
			if not path.is_empty() and (best == null or path.size() < best_length):
				best = cell
				best_length = path.size()
		if best != null:
			guard.go_to(best)
		else:
			send_guards_home(guard)

# ---------------------------------------------------
# 埋蔵金の発見
# ---------------------------------------------------

# 建物を建てたときに呼ばれる（地下のマスを掘ると、埋蔵金が見つかることがある）
func on_built(cells: Array) -> void:
	for cell in cells:
		if cell.y > world.ground_y:
			dig(cell)

# 地下のマスを1つ掘る（見つかったら資金に足して、メッセージで知らせる）
func dig(cell: Vector2i) -> void:
	if dug.has(cell):
		return # このマスはもう掘った
	dug[cell] = true
	var depth: int = cell.y - world.ground_y
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cell, "treasure"])
	if rng.randf() >= treasure_chance(depth):
		return
	var amount := mini(int(TREASURE_PER_FLOOR * depth * rng.randf_range(1.0, 2.0)), TREASURE_MAX)
	treasure_total += amount
	world.funds += amount
	world.update_funds_display()
	world.show_message("埋蔵金を発見！ %s で %s円 を掘り当てました" % [world.get_floor_name(cell.y), world.format_money(amount)])

# その深さで埋蔵金が見つかる確率
func treasure_chance(depth: int) -> float:
	return minf(TREASURE_CHANCE + TREASURE_CHANCE_PER_FLOOR * (depth - 1), TREASURE_CHANCE_MAX)

# ---------------------------------------------------
# ゴキブリの大繁殖
# ---------------------------------------------------

func has_roaches() -> bool:
	return not roaches.is_empty()

# ゴキブリがいるテナントか（そのテナントのどのマスでもよい）
func has_roach_at(cell: Vector2i) -> bool:
	return world.building_grid.has(cell) and roaches.has(world.building_grid[cell].origin)

# ゴキブリのぶん、評価に足されるストレス
func roach_stress(origin: Vector2i) -> float:
	return ROACH_STRESS if roaches.has(origin) else 0.0

# 1日1回の判定（衛生が悪い日が続くと増え、きれいになるといなくなる）
func update_roaches(day: int) -> void:
	# なくなったテナントのゴキブリは消す
	for origin in roaches.keys():
		if world.is_cell_empty(origin):
			roaches.erase(origin)
	if world.economy_system.pollution >= ROACH_POLLUTION:
		roach_days += 1
	else:
		roach_days = 0
		if world.economy_system.pollution == 0 and has_roaches():
			roaches.clear()
			world.show_message("ビルがきれいになり、ゴキブリはいなくなりました")
			return
	if roach_days < ROACH_DAYS:
		return
	var before := roaches.size()
	spread_roaches(day)
	if before == 0 and has_roaches():
		world.show_message("ゴキブリが大繁殖しました！ テナントの評価が下がります。ゴミの処理を急ぎましょう")
	elif roaches.size() > before:
		world.show_message("ゴキブリが %d 棟のテナントに広がっています" % roaches.size())

# ゴキブリをテナントに広げる（日ごとに決まった乱数で選ぶ）
func spread_roaches(day: int) -> void:
	var targets: Array[Vector2i] = []
	for type in TARGET_TYPES:
		for origin in world.find_units_of_type(type):
			if not roaches.has(origin):
				targets.append(origin)
	if targets.is_empty():
		return
	targets.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([day, "roach"])
	for i in mini(ROACH_SPAWN, targets.size()):
		roaches[targets[rng.randi_range(0, targets.size() - 1)]] = true

func get_roach_text() -> String:
	if not has_roaches():
		return ""
	return "ゴキブリ %d棟" % roaches.size()

# カーソルや上部バーの表示用
func get_fire_text() -> String:
	if not has_fire():
		return ""
	return "火災！ 燃えているマス %d" % fire.size()

func get_bomb_text() -> String:
	if not has_bomb():
		return ""
	return "爆破予告！ %s に爆弾（残り%d分）" % [world.get_floor_name(bomb.cell.y), int(bomb.left)]
