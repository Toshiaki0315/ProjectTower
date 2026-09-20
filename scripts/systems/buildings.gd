extends Node

# ---------------------------------------------------
# 建物の表と、建てる・撤去するときのルール。
#   TABLE:  建物の種類ごとの名前・値段・大きさ・建てられる階（main.gd の BUILDINGS から使う）
#   ルール: 重なり・大きさの上限・建てられる階・建物の支え・資金 の順に確かめる
# ---------------------------------------------------

const TABLE := {
	"office": {"name": "オフィス", "cost": 400000, "source_id": 0, "width": 4},
	"stairs": {"name": "階段", "cost": 50000, "source_id": 1, "floors": "any"},
	"elevator": {"name": "エレベーター", "cost": 80000, "source_id": 2, "floors": "any"},
	"hotel": {"name": "シングル", "cost": 150000, "source_id": 3, "width": 2},
	"hotel_twin": {"name": "ツイン", "cost": 200000, "source_id": 10, "width": 3},
	"hotel_suite": {"name": "スイート", "cost": 500000, "source_id": 11, "width": 4},
	"housekeeping": {"name": "ハウスキーパー室", "cost": 200000, "source_id": 4, "width": 2},
	"restaurant": {"name": "飲食店", "cost": 200000, "source_id": 5, "width": 3},
	"fastfood": {"name": "ファストフード", "cost": 120000, "source_id": 28, "width": 2},
	"shop": {"name": "ショップ", "cost": 250000, "source_id": 24, "width": 3},
	"cinema": {"name": "映画館", "cost": 1500000, "source_id": 25, "width": 8, "height": 2},
	"recycling": {"name": "ゴミ処理場", "cost": 150000, "source_id": 6, "width": 3},
	"security": {"name": "警備室", "cost": 100000, "source_id": 7, "width": 2},
	"medical": {"name": "メディカルセンター", "cost": 200000, "source_id": 8, "width": 3},
	"housing": {"name": "住宅", "cost": 400000, "source_id": 9, "width": 3},
	"wedding": {"name": "結婚式場", "cost": 1000000, "source_id": 12, "width": 6},
	"event_hall": {"name": "イベントホール", "cost": 800000, "source_id": 13, "width": 6},
	"subway": {"name": "地下鉄駅", "cost": 1000000, "source_id": 14, "width": 4, "floors": "deep_basement"},
	"garden": {"name": "屋上庭園", "cost": 400000, "source_id": 27, "width": 4, "floors": "rooftop"},
	"helipad": {"name": "ヘリポート", "cost": 800000, "source_id": 26, "width": 4, "floors": "rooftop"},
	"parking": {"name": "地下駐車場", "cost": 300000, "source_id": 22, "width": 4, "floors": "basement"},
	"ramp": {"name": "スロープ", "cost": 200000, "source_id": 23, "width": 2, "floors": "basement1"},
	"lobby": {"name": "ロビー", "cost": 15000, "source_id": 15, "floors": "ground", "lobby": true},
	"lobby2": {"name": "吹き抜けロビー（2階分）", "cost": 30000, "source_id": 16, "floors": "ground", "height": 2, "lobby": true},
	"lobby3": {"name": "吹き抜けロビー（3階分）", "cost": 45000, "source_id": 17, "floors": "ground", "height": 3, "lobby": true},
	"sky_lobby": {"name": "スカイロビー", "cost": 50000, "source_id": 18, "floors": "sky_lobby"},
	"express_elevator": {"name": "急行エレベーター", "cost": 120000, "source_id": 19, "floors": "any"},
	"escalator": {"name": "エスカレーター", "cost": 100000, "source_id": 20, "width": 2, "floors": "any"},
	"service_elevator": {"name": "サービスエレベーター", "cost": 80000, "source_id": 21, "floors": "any"},
}

const SKY_LOBBY_INTERVAL := 15 # スカイロビーを建てられる階の間隔（15階・30階・45階…）
const MAX_FLOORS_ABOVE := 150  # 建てられる一番上の階（地上150階）
const MAX_FLOORS_BELOW := 50   # 掘れる一番下の階（地下50階）
const MAX_WIDTH := 100         # ビルの横幅（マス数）。0を中心に左右へ半分ずつ
const SUBWAY_MIN_DEPTH := 5    # 地下鉄駅を建てられる深さ（地下5階より下）

var world: Node2D # main.gd

func setup(p_world: Node2D) -> void:
	world = p_world

# 建物の横幅（マス数）
func get_width(type: String) -> int:
	return TABLE[type].get("width", 1)

# 建物の高さ（階数）
func get_height(type: String) -> int:
	return TABLE[type].get("height", 1)

func is_lobby_type(type: String) -> bool:
	return TABLE.has(type) and TABLE[type].get("lobby", false)

# 左下のマス origin から建物を建てたときに使うマスの一覧（横幅 × 高さ。上の階は y が小さい）
func get_footprint(origin: Vector2i, type: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for k in get_height(type):
		for i in get_width(type):
			cells.append(origin + Vector2i(i, -k))
	return cells

# 左端 origin に type の建物を建てられない理由（建てられるなら ""）
func get_build_problem(origin: Vector2i, type: String) -> String:
	for cell in get_footprint(origin, type):
		if not world.is_cell_empty(cell):
			return "ほかの建物と重なるため建てられません"
	var limit := get_size_limit_problem(origin, type)
	if limit != "":
		return limit
	var floors: String = TABLE[type].get("floors", "")
	if floors == "ground" and origin.y != world.ground_y:
		return "%sは1階にしか建てられません" % TABLE[type].name
	if floors == "basement" and origin.y <= world.ground_y:
		return "%sは地下（1階より下）にしか建てられません" % TABLE[type].name
	if floors == "rooftop":
		for cell in get_footprint(origin, type):
			if cell.y >= world.ground_y or not world.is_cell_empty(cell + Vector2i.UP):
				return "%sは屋上（上に建物がないところ）にしか建てられません" % TABLE[type].name
	for cell in get_footprint(origin, type):
		if world.get_building_type(cell + Vector2i.DOWN) == "helipad":
			return "ヘリポートの上には建てられません"
	if floors == "deep_basement" and origin.y < world.ground_y + SUBWAY_MIN_DEPTH:
		return "%sは地下%d階より深いところにしか建てられません（ここは%s）" % [TABLE[type].name, SUBWAY_MIN_DEPTH, world.get_floor_name(origin.y)]
	if floors == "basement1" and origin.y != world.ground_y + 1:
		return "%sは地下1階にしか建てられません（1階から車で下りる道なので）" % TABLE[type].name
	if floors == "sky_lobby" and not world.is_sky_lobby_floor(origin.y):
		return "%sは%d階・%d階・%d階…にしか建てられません（ここは%s）" % [TABLE[type].name,
			SKY_LOBBY_INTERVAL, SKY_LOBBY_INTERVAL * 2, SKY_LOBBY_INTERVAL * 3, world.get_floor_name(origin.y)]
	if floors == "" and origin.y == world.ground_y:
		return "1階はロビー専用です（1階に建てられるのはロビー・階段・エレベーターだけ）"
	var support := get_support_problem(origin, type)
	if support != "":
		return support
	if world.funds < TABLE[type].cost:
		return "資金不足です！"
	return ""

# 建物の支え: 地上の建物は、一番下の階の全部のマスの真下に建物がないと建てられない（空中に浮かせない）。
# 地下の建物は、一番上の階の全部のマスの真上に建物がないと建てられない（上の階から掘り進める）。
# 1階の建物は地面が支えるので、条件なし。支えられているなら "" を返す
func get_support_problem(origin: Vector2i, type: String) -> String:
	if origin.y == world.ground_y:
		return ""
	for i in get_width(type):
		if origin.y < world.ground_y and world.is_cell_empty(origin + Vector2i(i, 1)):
			return "下の階に建物がないと建てられません（建物の下は全部埋まっている必要があります）"
		if origin.y > world.ground_y and world.is_cell_empty(origin + Vector2i(i, -get_height(type))):
			return "地下は、上の階に建物がある場所にしか建てられません"
	return ""

# 撤去すると支えを失う建物があるか。地上の建物は真上、地下の建物は真下に、別の建物があると撤去できない
#（撤去できるなら "" を返す）
func get_demolish_problem(cell: Vector2i) -> String:
	var unit: Array[Vector2i] = world.get_unit_cells(cell)
	for c in unit:
		var neighbor: Vector2i = c + (Vector2i.DOWN if c.y > world.ground_y else Vector2i.UP)
		if not world.is_cell_empty(neighbor) and not unit.has(neighbor):
			if c.y > world.ground_y:
				return "下の階の建物を支えているため撤去できません（下の階から撤去してください）"
			return "上の階の建物を支えているため撤去できません（上の階から撤去してください）"
	return ""

# ビルの大きさの上限（地上150階・地下50階・横100マス）を超えていないか。よければ ""
func get_size_limit_problem(origin: Vector2i, type: String) -> String:
	for cell in get_footprint(origin, type):
		if cell.y < world.ground_y - (MAX_FLOORS_ABOVE - 1):
			return "ビルは地上%d階までです" % MAX_FLOORS_ABOVE
		if cell.y > world.ground_y + MAX_FLOORS_BELOW:
			return "地下は%d階までです" % MAX_FLOORS_BELOW
		if cell.x < -MAX_WIDTH / 2 or cell.x >= MAX_WIDTH / 2:
			return "ビルの幅は%dマスまでです（マスのx座標は %d〜%d）" % [MAX_WIDTH, -MAX_WIDTH / 2, MAX_WIDTH / 2 - 1]
	return ""

