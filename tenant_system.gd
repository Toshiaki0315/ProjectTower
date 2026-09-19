extends Node2D

# ---------------------------------------------------
# テナントの評価：オフィスごとに、社員のストレスから 良い・普通・悪い の評価を付ける。
#   その日のストレス: 社員一人ひとりについて、その日にたまったストレスの一番高い値を記録する
#                     （通勤や昼食のエレベーター待ちでたまった分）
#   評価:            毎日の決算のときに、その日に出勤した社員の平均で決める（evaluate_day）
#                     平均 < GOOD_BELOW … 良い / < BAD_FROM … 普通 / それ以上 … 悪い
#                     出勤がなかった日（休日など）は前の評価のまま
# オフィスは左端のマスで表す。各オフィスの左上に評価の顔のマークを描く。
# TileMapLayerの子として追加するので、座標はタイルマップ座標系。
# ---------------------------------------------------

enum Rating { GOOD, NORMAL, BAD }

const GOOD_BELOW := 30.0
const BAD_FROM := 60.0
const RATING_NAMES := {Rating.GOOD: "良い", Rating.NORMAL: "普通", Rating.BAD: "悪い"}
const RATING_COLORS := {
	Rating.GOOD: Color(0.3, 0.9, 0.4),
	Rating.NORMAL: Color(1.0, 0.85, 0.2),
	Rating.BAD: Color(1.0, 0.3, 0.3),
}

var world: Node2D # main.gd
var day_peak_stress := {} # 社員（オフィスのマス） -> 今日たまったストレスの一番高い値
# オフィス（左端のマス） -> {rating, average}
#   average: 最後に評価した日の、社員のストレスの平均
var offices := {}

func setup(p_world: Node2D) -> void:
	world = p_world
	z_index = 9 # カゴより手前、住人より奥

func _process(_delta: float) -> void:
	# 社員ごとに、今日たまったストレスの一番高い値を記録する
	var workers: Dictionary = world.commute_system.workers
	for cell in workers:
		var resident = workers[cell].resident
		if is_instance_valid(resident):
			day_peak_stress[cell] = maxf(day_peak_stress.get(cell, 0.0), resident.stress)
	queue_redraw()

# 決算のときに呼ばれる: その日のストレスからオフィスごとの評価を決める
func evaluate_day(day: int) -> void:
	var workers: Dictionary = world.commute_system.workers
	var origins: Array[Vector2i] = world.find_units_of_type("office")
	for origin in origins:
		var total := 0.0
		var count := 0
		for cell in world.get_unit_cells(origin):
			if workers.has(cell) and workers[cell].arrived_day == day and not workers[cell].unreachable:
				total += day_peak_stress.get(cell, 0.0)
				count += 1
		if count == 0:
			if not offices.has(origin):
				offices[origin] = {"rating": Rating.GOOD, "average": 0.0}
			continue # 出勤がなかった日は前の評価のまま
		var average := total / count
		offices[origin] = {"rating": rating_for(average), "average": average}
	# なくなったオフィスの評価を消す
	for origin in offices.keys():
		if not origins.has(origin):
			offices.erase(origin)
	day_peak_stress.clear()

func rating_for(average: float) -> Rating:
	if average < GOOD_BELOW:
		return Rating.GOOD
	if average < BAD_FROM:
		return Rating.NORMAL
	return Rating.BAD

# 指定マスを含むオフィスの評価の説明（まだ評価がなければ ""）
func get_rating_text(cell: Vector2i) -> String:
	if world.building_grid.has(cell):
		cell = world.building_grid[cell].origin
	if not offices.has(cell):
		return ""
	var office = offices[cell]
	return "評価: %s・平均ストレス%d" % [RATING_NAMES[office.rating], int(office.average)]

func count_rating(rating: Rating) -> int:
	var n := 0
	for origin in offices:
		if offices[origin].rating == rating:
			n += 1
	return n

# 各オフィスの左上に、評価の顔のマーク（5×5ドット）を描く
func _draw() -> void:
	var tile_size := Vector2(world.tile_map.tile_set.tile_size)
	for origin in offices:
		if not world.building_grid.has(origin):
			continue
		var rating: Rating = offices[origin].rating
		var p := Vector2(origin) * tile_size + Vector2(1, 1)
		draw_rect(Rect2(p - Vector2.ONE, Vector2(7, 7)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p, Vector2(5, 5)), RATING_COLORS[rating])
		var ink := Color(0.1, 0.1, 0.1)
		draw_rect(Rect2(p + Vector2(1, 1), Vector2.ONE), ink) # 目
		draw_rect(Rect2(p + Vector2(3, 1), Vector2.ONE), ink)
		match rating:
			Rating.GOOD: # 笑顔
				draw_rect(Rect2(p + Vector2(0, 3), Vector2.ONE), ink)
				draw_rect(Rect2(p + Vector2(1, 4), Vector2(3, 1)), ink)
				draw_rect(Rect2(p + Vector2(4, 3), Vector2.ONE), ink)
			Rating.NORMAL: # ふつう
				draw_rect(Rect2(p + Vector2(1, 3), Vector2(3, 1)), ink)
			Rating.BAD: # 怒った顔
				draw_rect(Rect2(p + Vector2(1, 3), Vector2(3, 1)), ink)
				draw_rect(Rect2(p + Vector2(0, 4), Vector2.ONE), ink)
				draw_rect(Rect2(p + Vector2(4, 4), Vector2.ONE), ink)
