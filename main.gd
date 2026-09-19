extends Node2D

@onready var tile_map = $TileMapLayer

# ---------------------------------------------------
# 建物の定義（種類を増やすときはここに追記する）
# ---------------------------------------------------
const BUILDINGS := {
	"office": {"name": "オフィス", "cost": 100000, "source_id": 0},
	"stairs": {"name": "階段", "cost": 50000, "source_id": 1},
}
const REFUND_RATE := 0.5 # 撤去時の払い戻し率

var funds: int = 1000000
var current_mode: String = "office"
var funds_label: Label # 資金表示用のUIラベル
var mode_buttons: Dictionary = {} # モード名 -> Button

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
	for mode in BUILDINGS:
		var btn = Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.pressed.connect(func(): select_mode(mode))
		hbox.add_child(btn)
		mode_buttons[mode] = btn

	# 操作説明
	var help_label = Label.new()
	help_label.text = "左クリック: 建設 / 右クリック: 撤去（建設費の半額を返金）"
	vbox.add_child(help_label)

	update_mode_buttons()

# モードを切り替える
func select_mode(mode: String):
	current_mode = mode
	update_mode_buttons()

# 選択中のボタンを強調表示する
func update_mode_buttons():
	for mode in mode_buttons:
		var btn: Button = mode_buttons[mode]
		var data = BUILDINGS[mode]
		var label = "%s (%d万円)" % [data.name, data.cost / 10000]
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
# クリックして建設・撤去するロジック
# ---------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	# イベントに含まれるクリック位置をタイルマップの座標系に変換する
	var local_event = tile_map.make_input_local(event)
	var map_pos: Vector2i = tile_map.local_to_map(local_event.position)
	if event.button_index == MOUSE_BUTTON_LEFT:
		build_at(map_pos)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		demolish_at(map_pos)

# 建設処理
func build_at(map_pos: Vector2i):
	if not is_cell_empty(map_pos):
		return

	var data = BUILDINGS[current_mode]
	if funds < data.cost:
		print("資金不足です！")
		return

	funds -= data.cost
	tile_map.set_cell(map_pos, data.source_id, Vector2i(0, 0))
	building_grid[map_pos] = {"type": current_mode}
	update_funds_display()
	print(data.name, "を建設しました ", map_pos)

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
	print(BUILDINGS[type].name, "を撤去しました ", map_pos, " 払い戻し: ", refund, "円")
