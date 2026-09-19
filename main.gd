extends Node2D

const Resident := preload("res://resident.gd")

@onready var tile_map = $TileMapLayer

# ---------------------------------------------------
# 建物の定義（種類を増やすときはここに追記する）
# ---------------------------------------------------
const BUILDINGS := {
	"office": {"name": "オフィス", "cost": 100000, "source_id": 0},
	"stairs": {"name": "階段", "cost": 50000, "source_id": 1},
}
const REFUND_RATE := 0.5 # 撤去時の払い戻し率
const MODE_RESIDENT := "resident" # 住人を配置・移動させるモード

var funds: int = 1000000
var current_mode: String = "office"
var funds_label: Label # 資金表示用のUIラベル
var message_label: Label # 操作結果のメッセージ表示用
var mode_buttons: Dictionary = {} # モード名 -> Button

var residents: Array = [] # 配置済みの住人
var selected_resident = null # 行き先の指示を待っている住人

# ---------------------------------------------------
# グリッド情報（建物のマップデータ）
# キー: Vector2i（タイル座標） / 値: {"type": String}
# 住人AIや経路探索はこのデータを参照して「どこに何があるか」を判別する。
# 負の座標も扱えるよう、二次元配列ではなくDictionaryで管理している。
# ---------------------------------------------------
var building_grid: Dictionary = {}

func _ready() -> void:
	apply_tile_types()
	load_grid_from_tilemap()
	create_ui()
	update_funds_display()

# ---------------------------------------------------
# UIの自動生成ロジック
# ---------------------------------------------------
func create_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)

	# 縦に並べるコンテナ（資金表示とボタン群を縦に分ける）
	var vbox = VBoxContainer.new()
	vbox.position = Vector2(20, 20)
	canvas.add_child(vbox)

	# 資金表示ラベルの作成
	funds_label = Label.new()
	funds_label.add_theme_font_size_override("font_size", 24) # 少し文字を大きく
	vbox.add_child(funds_label)

	# ボタンを横に並べるコンテナ
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	# 同じグループのボタンは1つだけ押下状態になる（ラジオボタン的な挙動）
	var group = ButtonGroup.new()
	for mode in BUILDINGS.keys() + [MODE_RESIDENT]:
		var btn = Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.pressed.connect(func(): select_mode(mode))
		hbox.add_child(btn)
		mode_buttons[mode] = btn

	# 操作説明
	var help_label = Label.new()
	help_label.text = "左クリック: 建設 / 右クリック: 撤去（建設費の半額を返金）\n住人モード: 建物をクリックで住人を配置 → 行き先をクリックで移動"
	vbox.add_child(help_label)

	# 操作結果のメッセージ
	message_label = Label.new()
	message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vbox.add_child(message_label)

	update_mode_buttons()

# モードを切り替える
func select_mode(mode: String):
	current_mode = mode
	if mode != MODE_RESIDENT:
		select_resident(null)
	update_mode_buttons()

# ボタンに表示するモード名
func get_mode_label(mode: String) -> String:
	if mode == MODE_RESIDENT:
		return "住人 (テスト)"
	var data = BUILDINGS[mode]
	return "%s (%d万円)" % [data.name, data.cost / 10000]

# 選択中のボタンを強調表示する
func update_mode_buttons():
	for mode in mode_buttons:
		var btn: Button = mode_buttons[mode]
		var label = get_mode_label(mode)
		if mode == current_mode:
			btn.text = "▶ " + label + " [選択中]"
			btn.button_pressed = true
			btn.modulate = Color(1.0, 0.9, 0.3) # 黄色っぽく強調
		else:
			btn.text = label
			btn.modulate = Color(1, 1, 1)

# 資金の表示を更新する関数
func update_funds_display():
	if funds_label:
		funds_label.text = "現在の資金: " + str(funds) + "円"

# 画面とログにメッセージを出す
func show_message(text: String):
	if message_label:
		message_label.text = text
	print(text)

# ---------------------------------------------------
# グリッド情報の管理
# ---------------------------------------------------

# BUILDINGSの定義をもとに、TileSetのカスタムデータ「type」を設定する
# （メモリ上のみ。.tscnには保存されないため、エディタ上では空のまま見える）
func apply_tile_types():
	var tile_set: TileSet = tile_map.tile_set
	for type in BUILDINGS:
		var source := tile_set.get_source(BUILDINGS[type].source_id) as TileSetAtlasSource
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			source.get_tile_data(coords, 0).set_custom_data("type", type)

# エディタで事前に置いたタイルをグリッド情報に取り込む
func load_grid_from_tilemap():
	building_grid.clear()
	for cell in tile_map.get_used_cells():
		var type = get_type_from_tile(cell)
		if BUILDINGS.has(type):
			building_grid[cell] = {"type": type}

# タイルのカスタムデータ「type」から建物の種類を取得する（空マスなら ""）
func get_type_from_tile(cell: Vector2i) -> String:
	var tile_data: TileData = tile_map.get_cell_tile_data(cell)
	if tile_data == null:
		return ""
	return tile_data.get_custom_data("type")

# 指定マスの建物の種類を返す（空マスなら ""）
func get_building_type(cell: Vector2i) -> String:
	if building_grid.has(cell):
		return building_grid[cell].type
	return ""

func is_cell_empty(cell: Vector2i) -> bool:
	return not building_grid.has(cell)

# 指定した種類の建物がある座標をすべて返す（住人AIの目的地探索用）
func find_cells_of_type(type: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in building_grid:
		if building_grid[cell].type == type:
			result.append(cell)
	return result

# ---------------------------------------------------
# 移動ルールと経路探索
# ---------------------------------------------------

# 隣り合う2マス間を移動できるか（住人の移動可否はすべてこの関数で判断する）
# - 横移動: 両方のマスに建物があれば通れる
# - 上下移動: 下側のマスが階段なら通れる（階段はそのマスと1つ上の階をつなぐ）
func can_move(from: Vector2i, to: Vector2i) -> bool:
	if is_cell_empty(from) or is_cell_empty(to):
		return false
	var diff := to - from
	if diff.y == 0:
		return absi(diff.x) == 1
	if diff.x != 0 or absi(diff.y) != 1:
		return false
	var lower := from if from.y > to.y else to # yが大きい方が下の階
	return get_building_type(lower) == "stairs"

# 指定マスから1歩で移動できるマスの一覧
func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if can_move(cell, cell + dir):
			result.append(cell + dir)
	return result

# 幅優先探索で最短経路を求める
# 戻り値: [from, ..., to] のマス配列。経路がなければ空配列。
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if is_cell_empty(from) or is_cell_empty(to):
		return result

	var came_from := {} # マス -> 1つ前のマス
	came_from[from] = from
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == to:
			# ゴールからスタートまで逆にたどって経路を組み立てる
			var c := to
			while c != from:
				result.push_front(c)
				c = came_from[c]
			result.push_front(from)
			return result
		for next in get_neighbors(current):
			if not came_from.has(next):
				came_from[next] = current
				queue.append(next)
	return result

# ---------------------------------------------------
# 住人の管理
# ---------------------------------------------------

func spawn_resident(cell: Vector2i):
	var resident = Resident.new()
	resident.setup(self, cell)
	tile_map.add_child(resident)
	residents = residents.filter(is_instance_valid) # 退場した住人を除く
	residents.append(resident)
	return resident

func select_resident(resident):
	if is_instance_valid(selected_resident):
		selected_resident.selected = false
	selected_resident = resident
	if resident:
		resident.selected = true

# 住人モードでのクリック処理
# 1回目: 住人を配置 / 2回目: その住人の行き先を指定
func handle_resident_click(cell: Vector2i):
	if is_cell_empty(cell):
		show_message("建物のあるマスをクリックしてください")
		return

	if not is_instance_valid(selected_resident):
		select_resident(spawn_resident(cell))
		show_message("住人を配置しました。行き先のマスをクリックしてください")
		return

	if selected_resident.go_to(cell):
		show_message("住人が %s へ移動を始めました（%dマス）" % [cell, selected_resident.path.size()])
		select_resident(null)
	else:
		show_message("そこへの経路がありません（上の階へ行くには階段が必要です）")

# ---------------------------------------------------
# クリックして建設・撤去するロジック
# ---------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	# イベントに含まれるクリック位置をタイルマップの座標系に変換する
	var local_event = tile_map.make_input_local(event)
	var map_pos: Vector2i = tile_map.local_to_map(local_event.position)
	if event.button_index == MOUSE_BUTTON_LEFT:
		if current_mode == MODE_RESIDENT:
			handle_resident_click(map_pos)
		else:
			build_at(map_pos)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		demolish_at(map_pos)

# 建設処理
func build_at(map_pos: Vector2i):
	if not is_cell_empty(map_pos):
		return

	var data = BUILDINGS[current_mode]
	if funds < data.cost:
		show_message("資金不足です！")
		return

	funds -= data.cost
	tile_map.set_cell(map_pos, data.source_id, Vector2i(0, 0))
	building_grid[map_pos] = {"type": current_mode}
	update_funds_display()
	show_message("%sを建設しました %s" % [data.name, map_pos])

# 撤去（売却）処理
func demolish_at(map_pos: Vector2i):
	if is_cell_empty(map_pos):
		return

	var type = get_building_type(map_pos)
	var refund = int(BUILDINGS[type].cost * REFUND_RATE)

	funds += refund
	tile_map.erase_cell(map_pos)
	building_grid.erase(map_pos)
	update_funds_display()
	show_message("%sを撤去しました %s 払い戻し: %d円" % [BUILDINGS[type].name, map_pos, refund])
