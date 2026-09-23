extends RefCounted

# ---------------------------------------------------
# 計測の道具（perf_check.gd・fire_check.gd）で使う、大きなビル（35階・人口およそ550。★5までの通しプレイの終盤と
# 同じくらい）を、お金をかけずに組み立てる。
#   1階: ロビー（x=-8〜22）。x=8〜10 にエレベーター3本（各4台）。
#   2〜16階: オフィス7棟ずつ（x=-8〜7 と x=11〜22）。17〜35階: 住宅9戸ずつ（すき間は空きフロア）。
#   地下1〜2階: ゴミ処理場。地下3階: 警備室7つ（guards で数を変えられる）。
# ---------------------------------------------------

const GROUND := 18
const TOP_FLOOR := 35
const OFFICE_FLOORS := 16
const SHAFT_XS := [8, 9, 10]

static func build(main: Node2D, guards := 7) -> void:
	for x in range(-8, 23):
		main.place_unit(Vector2i(x, GROUND), "lobby" if not SHAFT_XS.has(x) else "elevator")
	for y in range(GROUND - 1, GROUND - TOP_FLOOR, -1):
		for x in SHAFT_XS:
			main.place_unit(Vector2i(x, y), "elevator")
		var floor_number: int = GROUND - y + 1
		if floor_number <= OFFICE_FLOORS:
			for x in [-8, -4, 0, 4, 11, 15, 19]:
				main.place_unit(Vector2i(x, y), "office")
		else:
			for x in [-8, -5, -2, 1, 4, 11, 14, 17, 20]:
				main.place_unit(Vector2i(x, y), "housing")
			main.place_unit(Vector2i(7, y), "frame")
			main.place_unit(Vector2i(23, y), "frame")
	for y in range(GROUND + 1, GROUND + 4): # 地下1〜3階
		for x in SHAFT_XS:
			main.place_unit(Vector2i(x, y), "elevator")
	for y in range(GROUND + 1, GROUND + 3): # 地下1〜2階: ゴミ処理場
		for x in [-8, -5, -2, 1, 4, 11, 14, 17, 20]:
			main.place_unit(Vector2i(x, y), "recycling")
		main.place_unit(Vector2i(7, y), "frame")
	for i in guards: # 地下3階: 警備室（x=-8 から右へ。エレベーターの列は飛ばす）
		var x: int = -8 + i * 2
		if x >= 7:
			x += 4
		main.place_unit(Vector2i(x, GROUND + 3), "security")
	for x in range(-8, 23): # 地下3階のすき間は空きフロアで埋める（警備員が歩いてエレベーターまで行けるように）
		if main.is_cell_empty(Vector2i(x, GROUND + 3)):
			main.place_unit(Vector2i(x, GROUND + 3), "frame")
	main.rebuild_systems()
	for x in SHAFT_XS:
		for i in 3:
			main.elevator_system.add_car(Vector2i(x, GROUND))
	main.funds = 100000000
