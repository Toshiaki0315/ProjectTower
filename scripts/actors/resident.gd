extends Node2D

const ElevatorCar := preload("res://scripts/actors/elevator_car.gd")

# ---------------------------------------------------
# 住人：グリッド上を1マスずつ歩き、階段やエレベーターで上下の階へ移動する。
# 移動できるかどうかの判断と経路探索は world（main.gd）に任せる。
# TileMapLayerの子として追加するので、positionはタイルマップ座標系。
#
# 状態:
#   WALKING  … 経路に沿って歩く（階段の上り下りを含む）
#   WAITING  … シャフトの前で行きたい方向（上/下）のボタンを押してカゴを待つ。
#              同じ方向へ進むカゴの扉が開いたら乗る（逆方向のカゴ・満員のカゴは見送る）
#   RIDING   … カゴに乗っている（目的の階で扉が開いたら降りる）
#
# ストレス（0〜100）:
#   カゴを待っている間たまり、目的地に着いて立ち止まっている間は回復する。
#   メディカルセンターがビルにあると、回復が速くなる（main.stress_recover_rate）。
#   顔（肌）の色で表す: ふつうの肌色（平常）→ ピンク（40以上）→ 赤（70以上）→ 赤く点滅（95以上＝激怒）。
#   歩いている間は、足の形を切り替えて歩いて見せる（WALK_LEGS）。
#   服の色はその人の種類（社員は白・宿泊客は薄紫など）を表すので、ストレスでは変えない
# ---------------------------------------------------

enum State { WALKING, WAITING, RIDING }

const WALK_SPEED := 48.0   # 横移動の速さ（px/秒）
const STAIRS_SPEED := 24.0 # 階段での上下移動の速さ（px/秒）
const ESCALATOR_SPEED := 40.0 # エスカレーターでの移動の速さ（px/秒。斜めに進む）

const MAX_STRESS := 100.0
const STRESS_WAIT_RATE := 10.0    # 待っている間に1秒でたまるストレス
const STRESS_RECOVER_RATE := 5.0  # 目的地で1秒に回復するストレス
const STRESS_PINK := 40.0         # これ以上でピンク
const STRESS_RED := 70.0          # これ以上で赤
const STRESS_ANGRY := 95.0        # これ以上は「激怒」。顔が赤く点滅する
const BLINK_PERIOD := 0.4         # 点滅の周期（秒）
const PINK_COLOR := Color(1.0, 0.55, 0.75)
const RED_COLOR := Color(1.0, 0.2, 0.2)
const ANGRY_COLOR := Color(1.0, 0.95, 0.95) # 激怒の点滅で、赤と交互に出る色

# 住人のドット絵（8×11ドット）。"c" の服の部分を、種類やストレスに応じた色で塗る
const BODY_SPRITE := [
	"..KKKK..",
	".KhhhhK.",
	".KssssK.",
	".KssssK.",
	"KKccccKK",
	"KccccccK",
	"KccccccK",
	"KKccccKK",
	".KLLLLK.",
	".KLKKLK.",
	".KK..KK.",
]
# 歩くときの足の形（下から2行ぶんを差し替える）。左右の足を交互に出して、歩いて見せる
const WALK_LEGS := [
	[".KLKKLK.", ".KK..KK."], # 立っている（両足そろえる）
	[".KLLKLK.", "KK...KK."], # 右足を前に
	[".KLKLLK.", ".KK..KK."], # 左足を前に
]
const WALK_FRAME_PIXELS := 5.0 # 何px進むごとに足を切り替えるか

const BODY_COLORS := {
	"K": Color("#1b1b24"), # 輪郭
	"h": Color("#4a3020"), # 髪
	"s": Color("#f1c27d"), # 肌
	"L": Color("#34405a"), # ズボン
}
const BODY_ORIGIN := Vector2(-4, -5) # マスの中心から見た、ドット絵の左上（足元が床の上に来る位置）

var world: Node2D              # main.gd（グリッド情報と経路探索を持つ）
var cell: Vector2i             # 現在いるマス（乗車中は乗ったマス）
var goal: Vector2i             # 目的地のマス
var path: Array[Vector2i] = [] # これから進むマス（先頭が次のマス）
var state := State.WALKING
var car = null                 # 乗っているカゴ
var ride_dir := 0              # 乗りたい方向（カゴのDirection.UP / DOWN）
var stress := 0.0
var walked := 0.0 # 歩いた距離（px。足の動かし方を決めるのに使う）
var base_color := Color.WHITE  # 平常時の体の色（社員: 白 / 宿泊客: 薄紫 / 清掃員: 水色）
var staff := false             # 裏方（清掃員など）。サービスエレベーターに乗れる
var sprite_offset := Vector2.ZERO # 体を描く位置のずれ（同じマスにいる連れ同士が重ならないように）
var selected := false:
	set(value):
		selected = value
		queue_redraw()

func setup(p_world: Node2D, start_cell: Vector2i) -> void:
	world = p_world
	cell = start_cell
	goal = start_cell
	position = world.tile_map.map_to_local(cell)
	z_index = 10 # タイルやカゴより手前に描く

func is_moving() -> bool:
	return not path.is_empty()

# 目的地を設定して経路を求める。経路がなければfalseを返す。
func go_to(target: Vector2i) -> bool:
	var new_path: Array[Vector2i] = world.find_path(cell, target, staff)
	if new_path.is_empty():
		return false
	new_path.pop_front() # 先頭は現在地なので除く
	path = new_path
	goal = target
	state = State.WALKING
	car = null
	queue_redraw()
	return true

func _process(delta: float) -> void:
	update_stress(delta)
	match state:
		State.WALKING:
			process_walking(delta)
		State.WAITING:
			process_waiting()
		State.RIDING:
			process_riding()
	queue_redraw()

# 歩く処理。1フレームでマスをまたいでも余った時間ぶんは続けて進む
#（そうしないと、早送り中やfpsが低いときに1フレーム1マスまでしか進めず、歩く速さが落ちてしまう）
func process_walking(delta: float) -> void:
	var time_left := delta
	while time_left > 0.0:
		# 立っているマスが撤去されたら退場する
		if world.is_cell_empty(cell):
			leave("住人の足元が撤去されたため、住人が退場しました")
			return
		if path.is_empty():
			return

		var next: Vector2i = path[0]
		var at_cell_center: bool = position == world.tile_map.map_to_local(cell)

		# マスの中心から次の一歩を踏み出す前に、まだ通れるか確認する
		if at_cell_center and not world.can_move(cell, next, staff):
			if not go_to(goal):
				path.clear()
				world.show_message("経路が途切れたため、住人が立ち止まりました")
			return

		# 次の一歩がエレベーターなら、乗り場のボタンを押して待つ
		if at_cell_center and world.is_elevator_ride(cell, next):
			ride_dir = ElevatorCar.Direction.UP if next.y < cell.y else ElevatorCar.Direction.DOWN
			world.elevator_system.request_hall(cell, ride_dir)
			state = State.WAITING
			return

		var target_pos: Vector2 = world.tile_map.map_to_local(next)
		var speed := WALK_SPEED
		if world.is_escalator_ride(cell, next):
			speed = ESCALATOR_SPEED
		elif next.y != cell.y:
			speed = STAIRS_SPEED
		var before := position
		var distance := position.distance_to(target_pos)
		if speed * time_left >= distance:
			position = target_pos # 次のマスに着いた。余った時間でさらに進む
			time_left -= distance / speed
			cell = next
			path.pop_front()
		else:
			position = position.move_toward(target_pos, speed * time_left)
			time_left = 0.0
		walked += before.distance_to(position)

func process_waiting() -> void:
	if world.is_cell_empty(cell):
		leave("住人の足元が撤去されたため、住人が退場しました")
		return
	# シャフトが変わってカゴがなくなった／行き先の階に行けなくなったら経路を探し直す
	if world.elevator_system.get_cars_at(cell).is_empty() or not world.can_move(cell, path[0], staff):
		if not go_to(goal):
			path.clear()
			state = State.WALKING
			world.show_message("経路が途切れたため、住人が立ち止まりました")
		return
	# 行きたい方向へ進む、空きのあるカゴがこの階で扉を開けたら、乗り込んで行き先の階を押す
	var boardable = world.elevator_system.find_boardable_car(cell, ride_dir)
	if boardable:
		car = boardable
		car.board(self, path[0].y)
		state = State.RIDING
	else:
		world.elevator_system.request_hall(cell, ride_dir) # 呼び出しが取り消されていたら押し直す

func process_riding() -> void:
	# 乗っているカゴがなくなったら退場する（シャフトごと撤去されたなど）
	if not is_instance_valid(car):
		leave("乗っていたエレベーターが撤去されたため、住人が退場しました")
		return
	position = car.position # カゴと一緒に動く
	var dest: Vector2i = path[0]
	if not car.has_floor(dest.y):
		dest = Vector2i(car.column, car.current_floor()) # 行き先の階がなくなったら、今の階で降りる
		if not car.is_doors_open_at(dest.y):
			car.request_floor(dest.y)
			return
	# 目的の階で扉が開いたら降りる
	if car.is_doors_open_at(dest.y):
		cell = dest
		position = world.tile_map.map_to_local(cell)
		car.alight(self)
		car = null
		state = State.WALKING
		if path[0] == dest:
			path.pop_front()
		elif not go_to(goal):
			path.clear()
			world.show_message("経路が途切れたため、住人が立ち止まりました")
	else:
		car.request_floor(dest.y) # 呼び出しが取り消されていたら押し直す

func update_stress(delta: float) -> void:
	if state == State.WAITING:
		stress = minf(stress + STRESS_WAIT_RATE * delta, MAX_STRESS)
	elif state == State.WALKING and path.is_empty():
		# メディカルセンターがあるビルでは、落ち着くのが速い（world.stress_recover_rate）
		stress = maxf(stress - STRESS_RECOVER_RATE * world.stress_recover_rate() * delta, 0.0)

# ストレスに応じた体の色
# 服の色（種類ごとの色。選択中は黄色）
func get_body_color() -> Color:
	return Color(1.0, 0.85, 0.1) if selected else base_color

# 今の体のドット絵（歩いているときは、進んだ距離で足の形を切り替える）
func body_sprite() -> Array:
	var sprite: Array = BODY_SPRITE.duplicate()
	if is_moving():
		var frame: int = int(walked / WALK_FRAME_PIXELS) % WALK_LEGS.size()
		sprite[sprite.size() - 2] = WALK_LEGS[frame][0]
		sprite[sprite.size() - 1] = WALK_LEGS[frame][1]
	return sprite

# 我慢の限界（激怒）か。顔が赤く点滅して、放っておくと評価が下がっていく
func is_angry() -> bool:
	return stress >= STRESS_ANGRY

# 顔（肌）の色。ストレスが高いほど赤くなり、限界を超えると点滅する
#（服は種類を表す色なので、ストレスは顔色で見せる）
func get_face_color() -> Color:
	if is_angry():
		# 点滅: BLINK_PERIOD の半分ごとに、赤と明るい色が入れ替わる
		var phase := fmod(Time.get_ticks_msec() / 1000.0, BLINK_PERIOD)
		return RED_COLOR if phase < BLINK_PERIOD / 2.0 else ANGRY_COLOR
	if stress >= STRESS_RED:
		return RED_COLOR
	if stress >= STRESS_PINK:
		return PINK_COLOR
	return BODY_COLORS["s"]

func leave(message: String) -> void:
	world.show_message(message)
	queue_free()

func _draw() -> void:
	# 残りの経路を線で表示する
	if not path.is_empty():
		var points := PackedVector2Array([Vector2.ZERO])
		for c in path:
			points.append(world.tile_map.map_to_local(c) - position)
		draw_polyline(points, Color(1.0, 1.0, 0.4, 0.8), 1.5)

	# 体（ドット絵）。服は種類ごとの色（選択中は黄色）、顔はストレスに応じた色
	var clothes := get_body_color()
	var face := get_face_color()
	var sprite := body_sprite()
	for y in sprite.size():
		var row: String = sprite[y]
		for x in row.length():
			var ch := row[x]
			if ch == ".":
				continue
			var color: Color = clothes if ch == "c" else (face if ch == "s" else BODY_COLORS[ch])
			draw_rect(Rect2(BODY_ORIGIN + sprite_offset + Vector2(x, y), Vector2.ONE), color)

	# カゴを待っている間は頭の上に「…」を出す
	if state == State.WAITING:
		for i in 3:
			draw_rect(Rect2(sprite_offset + Vector2(-3 + i * 2, -8), Vector2.ONE), Color.WHITE)
