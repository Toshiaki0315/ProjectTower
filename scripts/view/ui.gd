extends Node

const ChartView := preload("res://scripts/view/chart_view.gd")

# ---------------------------------------------------
# 画面（UI）の組み立てと更新。main.gd から使う。
#   画面の文字・ボタン・余白は UI_SCALE 倍にしてある（見やすさのため）。
#   毎フレームの更新は update() で行う（資金・時刻・ビルの状況・案内・吹き出し・スクロールバー）。
# ---------------------------------------------------

const UI_SCALE := 2      # 画面表示（文字・ボタン・余白）の大きさの倍率
const BASE_FONT_SIZE := 16 # 倍率をかける前の文字の大きさ
const MESSAGE_LINES := 3 # 下部バーに出しておくメッセージの行数

var world: Node2D # main.gd

# 画面の部品
var funds_label: Label     # 資金
var clock_label: Label     # 日付・時刻・天気
var stats_label: Label     # ビルの状況（★・人口・社員・客室）
var speed_button: Button   # ゲームの速度（押すたびに切り替わる）
var mode_select: OptionButton # 建設メニュー
var mode_info_label: Label # 選んだものの建設費と大きさ
var message_label: Label   # 操作結果のメッセージ（下から数行ぶん流れる）
var hover_label: Label     # カーソル下のマスの情報（吹き出しの中身）
var hover_tooltip: Control # 吹き出し
var help_panel: Control    # 操作説明（⌘H）
var log_panel: Control     # メッセージの記録（⌘L）
var log_label: Label
var log_scroll: ScrollContainer
var chart_panel: Control   # 収支のグラフ（⌘G）
var tutorial_panel: Control # はじめての案内
var tutorial_label: Label
var title_panel: Control   # タイトル画面
var goal_panel: Control    # 目標を達成したときの画面
var goal_title: Label
var goal_text: Label
var v_scroll: VScrollBar   # 右端の上下スクロールバー

func setup(p_world: Node2D) -> void:
	world = p_world

# 毎フレームの更新（main.gd の _process から呼ぶ）
func update() -> void:
	if v_scroll == null:
		return # まだ画面を組み立てていない
	update_scrollbar()
	update_hover_label()
	clock_label.text = "%s  %s" % [world.clock.get_time_text(), world.weather_system.get_weather_text()]
	stats_label.text = world.rating_system.get_status_text()
	stats_label.text += " / 社員: 在館 %d / 全 %d人" % [world.commute_system.count_in_building(), world.commute_system.workers.size()]
	var unreachable: int = world.commute_system.count_unreachable()
	if unreachable > 0:
		stats_label.text += "（通勤できない %d人）" % unreachable
	stats_label.text += " / " + world.goal_system.get_goal_text()
	var angry := 0
	for r in world.residents:
		if is_instance_valid(r) and r.is_angry():
			angry += 1
	if angry > 0:
		stats_label.text += " / 怒っている人 %d人" % angry
	var leaving: int = world.tenant_system.count_about_to_leave()
	if leaving > 0:
		stats_label.text += " / 退去しそうなテナント %d件" % leaving
	if world.economy_system.pollution > 0:
		stats_label.text += " / 衛生の悪化 レベル%d" % world.economy_system.pollution
	if world.incident_system.has_roaches():
		stats_label.text += " / " + world.incident_system.get_roach_text()
	if world.incident_system.has_fire():
		stats_label.text += " / " + world.incident_system.get_fire_text()
	if world.incident_system.has_bomb():
		stats_label.text += " / " + world.incident_system.get_bomb_text()
	if world.vip_system.is_visiting():
		stats_label.text += " / VIPが来館中（ストレス %d）" % int(world.vip_system.vip.stress)
	if world.tenant_system.count_rating(world.tenant_system.Rating.GOOD) + world.tenant_system.count_rating(world.tenant_system.Rating.NORMAL) \
			+ world.tenant_system.count_rating(world.tenant_system.Rating.BAD) + world.tenant_system.count_vacant() > 0:
		stats_label.text += " / オフィス: 良い%d・普通%d・悪い%d・空室%d" % [
			world.tenant_system.count_rating(world.tenant_system.Rating.GOOD),
			world.tenant_system.count_rating(world.tenant_system.Rating.NORMAL),
			world.tenant_system.count_rating(world.tenant_system.Rating.BAD),
			world.tenant_system.count_vacant()]
	if world.hotel_system.rooms.size() > 0:
		stats_label.text += " / 客室: 宿泊 %d・清掃待ち %d・空室 %d" % [
			world.hotel_system.count_rooms(world.hotel_system.RoomState.OCCUPIED),
			world.hotel_system.count_rooms(world.hotel_system.RoomState.DIRTY),
			world.hotel_system.count_rooms(world.hotel_system.RoomState.CLEAN)]
	tutorial_label.text = world.tutorial_system.current_text()
	tutorial_panel.visible = tutorial_label.text != ""

# 下部バーのメッセージ（新しいものが下に出て、古いものは上へ流れる）
func show_messages(log: Array) -> void:
	if message_label:
		message_label.text = "\n".join(log.slice(maxi(log.size() - MESSAGE_LINES, 0)))
	if log_label and log_panel.visible:
		update_log_panel()

func clear_message() -> void:
	if message_label:
		message_label.text = ""

# ---------------------------------------------------
# UIの自動生成ロジック
# ---------------------------------------------------
# 画面構成:
#   上部バー    … 1段目: 資金 / 日付と時刻 / 速度
#                  2段目: ビルの状況（★・人口・社員・客室）
#                  3段目: 建設メニュー
#   操作説明    … 上部バーの下に表示（⌘Hで開閉）。メッセージの記録は⌘Lで開閉
#   （マップ）  … クリックはそのままマップに届く
#   下部バー    … 操作結果のメッセージ（新しいものが下に出て、古いものは流れる）
#   吹き出し    … カーソル下のマスの情報（建物や人がいるマスで、マウスの横に出る）
# バーの上のクリックはバーが受け止めるので、下のマスに建設されることはない。
func build() -> void:
	build_bars()
	build_title()
	world.update_funds_display()

# 上下のバー・操作説明・記録・グラフ・吹き出しを組み立てる
func build_bars() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var layout = VBoxContainer.new()
	# 画面の文字・ボタン・余白をまとめて UI_SCALE 倍にする（テーマで文字の大きさを決め、
	# 余白や幅の指定にも同じ倍率をかける）
	var theme := Theme.new()
	theme.default_font_size = BASE_FONT_SIZE * UI_SCALE
	layout.theme = theme
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 0)
	canvas.add_child(layout)
	
	# --- 上部バー（2段） ---
	#   1段目: 資金 / 日付と時刻 / 速度
	#   2段目: モード切り替えボタン
	var top_rows = VBoxContainer.new()
	top_rows.add_theme_constant_override("separation", 4 * UI_SCALE)
	layout.add_child(make_bar(top_rows))
	var status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8 * UI_SCALE)
	top_rows.add_child(status_row)
	# ビルの状況（★・人口・社員・客室）は上部バーの2段目
	stats_label = Label.new()
	stats_label.clip_text = true
	stats_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_rows.add_child(stats_label)
	var build_row = HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 8 * UI_SCALE)
	top_rows.add_child(build_row)
	
	funds_label = Label.new()
	funds_label.add_theme_font_size_override("font_size", 20 * UI_SCALE)
	funds_label.custom_minimum_size.x = 420 * UI_SCALE # 金額の桁が変わっても時刻の位置がずれないように
	status_row.add_child(funds_label)
	
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 20 * UI_SCALE)
	status_row.add_child(clock_label)
	
	status_row.add_child(make_spacer())
	
	# ゲームの速度（Engine.time_scaleで、時計・住人・エレベーターをまとめて早送りする）。
	# ボタンは1つで、押すたびに 1x → 4x → 16x → 1x と切り替わり、今の速度だけを表示する
	speed_button = Button.new()
	speed_button.custom_minimum_size.x = 60 * UI_SCALE
	speed_button.pressed.connect(func(): world.set_speed(world.SPEEDS[(world.SPEEDS.find(int(Engine.time_scale)) + 1) % world.SPEEDS.size()]))
	status_row.add_child(speed_button)
	world.set_speed(1)
	
	# 操作説明（⌘H）とメッセージの記録（⌘L）は、ボタンではなくショートカットで開く
	
	# 建設メニュー: リストから選んで、マップをクリックして建てる（見出しごとにまとめる）
	var build_label = Label.new()
	build_label.text = "建設:"
	build_row.add_child(build_label)
	mode_select = OptionButton.new()
	mode_select.custom_minimum_size.x = 260 * UI_SCALE
	for group in world.MODE_GROUPS:
		mode_select.add_separator(group.name)
		for mode in group.modes:
			mode_select.add_item(get_mode_label(mode))
			mode_select.set_item_metadata(mode_select.item_count - 1, mode)
	mode_select.item_selected.connect(func(index): world.select_mode(mode_select.get_item_metadata(index)))
	for type in world.BUILDINGS:
		assert(world.MODE_GROUPS.any(func(group): return group.modes.has(type)), "%s が建設メニュー（world.MODE_GROUPS）にありません" % type)
	build_row.add_child(mode_select)
	mode_info_label = Label.new()
	mode_info_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	build_row.add_child(mode_info_label)
	
	# --- はじめての案内（上部バーの下。画面の横幅いっぱいに出す） ---
	var tutorial_box = HBoxContainer.new()
	tutorial_box.add_theme_constant_override("separation", 12 * UI_SCALE)
	tutorial_label = Label.new()
	tutorial_label.add_theme_color_override("font_color", Color(0.65, 0.95, 1.0))
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_label.clip_text = true
	tutorial_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tutorial_box.add_child(tutorial_label)
	var skip_button = Button.new()
	skip_button.text = "案内を閉じる"
	skip_button.pressed.connect(func(): world.tutorial_system.skip())
	tutorial_box.add_child(skip_button)
	tutorial_panel = make_bar(tutorial_box)
	tutorial_panel.visible = false
	layout.add_child(tutorial_panel)
	
	# --- 操作説明（上部バーの下、右寄せ） ---
	var help_row = HBoxContainer.new()
	help_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(help_row)
	help_row.add_child(make_spacer())
	var help_label = Label.new()
	help_label.text = "\n".join([
		"建設: 上の「建設」メニューで選び、マップを左クリック / 右クリック: 撤去（建設費の半額を返金）",
		"更地から始まる。1階はロビー専用（ロビー・階段・エレベーターだけ）。人はロビーの左端（入口）から出入りする",
		"吹き抜けロビー: 2階分・3階分の高さのロビー。上の階には床がないので、人は1階だけを歩く",
		"スカイロビー: 15階・30階・45階…にだけ建てられる乗り換え専用のフロア（何階かはカーソル下の情報に出る）",
		"住人モード: 建物をクリックで住人を配置 → 行き先をクリックで移動",
		"エレベーター: 縦に並べるとシャフトになる。シャフトをクリックでその階にカゴを呼ぶ",
		"カゴ追加: シャフトをクリックすると、その階にカゴを1台追加（1本に4台まで、維持費3千円/日）。カゴの定員は8人",
		"社員: オフィスは横4マスで、1マスに1人（計4人）。8〜9時に入口から出勤し、17〜18時に帰る",
		"建設: クリックしたマスを左端に、建物の横幅ぶんのマスを使う。撤去はどのマスを右クリックしても建物ごと",
		"入口: 1階の左端と地下鉄駅（地下5階より深いところにだけ建てられる）。人は近い方の入口から出入りする",
		"　地下鉄駅があると、店や映画館へ来る外からのお客さんが1駅につき5割増える（最大2倍）",
		"速度: 上部バーの速度ボタンを押すたびに 1x → 4x → 16x → 1x と切り替わる",
		"ショートカット: ⌘H（この説明の開閉） / ⌘L（メッセージの記録） / ⌘+・⌘-（画面の拡大・縮小） / ⌘0（拡大率をもとに戻す）",
		"収支のグラフ: ⌘G で、最近60日ぶんの決算の合計を棒グラフで見られる",
		"音: ⌘M で音のオン・オフ（効果音とBGMは、波形からゲームの中で作っている）",
		"撤去: 建設メニューの「撤去」を選ぶと左クリックで撤去できる（右クリックはいつでも撤去）。ドラッグで続けて建設・撤去できる",
		"セーブ: ⌘S で保存、⌘O で読み込み（ビル・資金・日付・評価・各設備の状態が戻る）",
		"天気: 日ごとに晴れ・くもり・雨が決まる（6月は梅雨）。雨の日は入口から来る店の客が半分（車で来る客は減らない）",
		"日付: 1日目は4月1日（月）。1年は365日で、12月24日・25日の夜にはサンタクロースのソリが空を横切る",
		"曜日: 1日目は月曜日。土日は休日でオフィスは休み（賃料は入る）、住宅の入居者は遅めに出かける",
		"結婚式場（横6マス）: 休日の10〜11時に12人が来て13時まで（1人1万円）",
		"イベントホール（横6マス）: 休日の13〜14時に15人が来て17時まで（1人3千円）",
		"ホテル: 17〜21時に客が来て泊まり、翌朝7〜10時に宿泊料を払って帰る。清掃が済むまで次の客は泊まれない",
		"　シングル（横2マス）: 1人・2万円・清掃20分 / ツイン（横3マス）: 2人・3.5万円・清掃30分 / スイート（横4マス）: 2人・8万円・清掃45分",
		"ハウスキーパー室（横2マス）: 清掃員が2人。清掃待ちの部屋を近い順に掃除する",
		"飲食店（横3マス）: 12〜13時に社員が一番近い店へ昼食に来る（30分、1人1千円の売上）",
		"ファストフード（横2マス）: 飲食店の小さくて速い版。食事は10分で、1人600円の売上",
		"住宅（横3マス・3人家族）: 17〜20時に入居者が来て入居（販売収入70万円、1回だけ）。毎朝7〜9時に出かけ、17〜20時に帰る",
		"ゴミ処理場（横3マス）: 1施設で1日20のゴミを処理。処理しきれないゴミは外部委託で1につき1千円かかる",
		"　処理が足りない日が続くとビルが汚れ（衛生の悪化）、レベル1につきストレス5ぶん全テナントの評価が下がる",
		"メディカルセンター（横3マス）: ビル全体のストレスの回復が速くなる（1施設で1.5倍・最大2.5倍）",
		"埋蔵金: 地下に建てるとマスごとに見つかることがある（深いほど確率も金額も上がる。同じマスは一度きり）",
		"ゴキブリ: 衛生の悪化が続くと大繁殖し、いるテナントの評価がストレス15ぶん悪くなる（悪化が0に戻ると消える）",
		"ヘリポート（横4マス）: 屋上にだけ建てられる。火事のとき消防ヘリが飛んできて、上の階の火から消す",
		"火災: ★2以上のビルでときどき出火。20分ごとに隣と上へ燃え広がり、60分燃えたテナントは焼け落ちる（警備員が消火する）",
		"爆破予告: ★2以上のビルにときどき届く。警備員が現場で解体できないと、120分後にそのテナントが吹き飛ぶ",
		"VIP: ★4の条件がそろうと16時にVIPが来館。ストレス30以下できれいな空きスイートに着けば合格（不合格なら翌日また来る）",
		"評価（★）: 決算時に条件を満たすと昇格。★2: 人口50・警備室 / ★3: 人口120・メディカルセンター・ゴミ処理場",
		"　★が1つ上がるごとに、賃料と宿泊料に25%の評価ボーナスが付く（人口 = 通勤できる社員 + 客室の定員 + 入居者）",
		"オフィスの評価: 毎日の決算で、社員のその日の最大ストレスの平均から 良い（緑）・普通（黄）・悪い（赤）を付ける",
		"　悪い日が3日続くとテナントが退去して空室（賃料なし）。2日後に新しいテナントが入居する",
		"　退去まであと1日のテナントは、評価のマークが点滅して知らせる（上部バーにも件数が出る）",
		"激怒: ストレスが95以上になると人の顔が赤く点滅する（上部バーに人数が出る）",
		"ホテル・住宅の評価: 客室は泊まった客のストレスで決まり、悪いと客が来にくい。住宅は悪い日が3日続くと家族が退去（販売収入を返金）",
		"収支: 毎日0時に決算。賃料・宿泊料・飲食の売上 − 維持費 − ゴミの外部委託費",
		"スクロール: マウスホイールで上下、Shift+ホイールで左右、右端のスクロールバー",
		"ズーム: Ctrl（⌘）+マウスホイール / トラックパッドのピンチ",
		"カメラ移動: 2本指スクロール / 中ボタンドラッグ / WASD・矢印キー",
	])
	help_label.add_theme_font_size_override("font_size", 13 * UI_SCALE) # 行数が多いので少し小さめ
	var help_scroll = ScrollContainer.new()
	help_scroll.custom_minimum_size = Vector2(1000, 420) # 画面に収まる高さ。はみ出す分はスクロールする
	help_scroll.add_child(help_label)
	help_panel = make_bar(help_scroll)
	help_panel.visible = false
	help_row.add_child(help_panel)
	
	# --- メッセージの記録（⌘Lで開閉。ゲーム開始からのメッセージを全部見られる） ---
	var log_row = HBoxContainer.new()
	log_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(log_row)
	log_label = Label.new()
	log_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	log_label.add_theme_font_size_override("font_size", 13 * UI_SCALE)
	log_scroll = ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(1000, 420)
	log_scroll.add_child(log_label)
	log_panel = make_bar(log_scroll)
	log_panel.visible = false
	log_row.add_child(log_panel)
	log_row.add_child(make_spacer())
	
	# --- 収支のグラフ（⌘Gで開閉） ---
	var chart_row = HBoxContainer.new()
	chart_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(chart_row)
	var chart_view = ChartView.new()
	chart_view.world = world
	chart_view.custom_minimum_size = Vector2(620 * UI_SCALE, 150 * UI_SCALE)
	chart_panel = make_bar(chart_view)
	chart_panel.visible = false
	chart_row.add_child(chart_panel)
	chart_row.add_child(make_spacer())
	
	# --- マップ部分（クリックはそのまま通す）。右端に上下スクロールバー ---
	var map_row = HBoxContainer.new()
	map_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(map_row)
	map_row.add_child(make_spacer())
	v_scroll = VScrollBar.new()
	v_scroll.custom_minimum_size.x = 14 * UI_SCALE
	v_scroll.value_changed.connect(func(value): world.camera.position.y = value + v_scroll.page / 2.0)
	map_row.add_child(v_scroll)
	
	# --- 下部バー（2段） ---
	#   1段目: 操作結果のメッセージ（新しいものが下に出て、古いものは流れていく）
	#   2段目: カーソル下のマスの情報
	var bottom_rows = VBoxContainer.new()
	bottom_rows.add_theme_constant_override("separation", 2 * UI_SCALE)
	layout.add_child(make_bar(bottom_rows))
	
	message_label = Label.new()
	message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	# メッセージは行数が多いので、ほかの文字の半分の大きさにする
	message_label.add_theme_font_size_override("font_size", BASE_FONT_SIZE * UI_SCALE / 2)
	message_label.clip_text = true
	message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 新しいメッセージが一番下に出て、古いメッセージは上へ流れていく（MESSAGE_LINES 行ぶん）
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	message_label.custom_minimum_size.y = MESSAGE_LINES * BASE_FONT_SIZE * UI_SCALE / 2 * 1.3
	bottom_rows.add_child(message_label)
	
	# カーソル下のマスの情報は、マウスの横に吹き出し（ツールチップ）で出す
	hover_label = Label.new()
	hover_tooltip = make_bar(hover_label)
	hover_tooltip.theme = theme
	hover_tooltip.visible = false
	hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_tooltip.top_level = true # 画面の好きな位置に出せるようにする
	canvas.add_child(hover_tooltip)
	
	update_mode_select()

# 半透明の背景を持つバーを作る（中身をcontentとして入れる）
func make_bar(content: Control) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.9)
	style.set_content_margin_all(6 * UI_SCALE)
	style.content_margin_left = 12 * UI_SCALE
	style.content_margin_right = 12 * UI_SCALE
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(content)
	return panel

# 余白を埋めるだけの透明なControl（クリックは通す）
func make_spacer() -> Control:
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

func get_mode_label(mode: String) -> String:
	if mode == world.MODE_RESIDENT:
		return "住人（テスト）"
	if mode == world.MODE_ADD_CAR:
		return "カゴ追加"
	if mode == world.MODE_SET_HOME:
		return "待機階を設定"
	if mode == world.MODE_SERVICE:
		return "稼働時間帯"
	if mode == world.MODE_DEMOLISH:
		return "撤去"
	var width: int = world.get_width(mode)
	return world.BUILDINGS[mode].name + ("（横%dマス）" % width if width > 1 else "")

# 選んだものの費用・大きさの説明
func get_mode_info(mode: String) -> String:
	if mode == world.MODE_RESIDENT:
		return "建物をクリックで住人を置き、行き先をクリック"
	if mode == world.MODE_SET_HOME:
		return "無料（シャフトをクリックでその階を待機階に。もう一度クリックで解除）"
	if mode == world.MODE_SERVICE:
		return "無料（シャフトをクリックで 終日 → 6時〜24時 → 8時〜20時 と切り替え）"
	if mode == world.MODE_DEMOLISH:
		return "クリックした建物を撤去（建設費の半額が戻る。ドラッグで続けて撤去）"
	if mode == world.MODE_ADD_CAR:
		return "1台 %s円（シャフトをクリック。1本に%d台まで）" % [world.format_money(world.elevator_system.CAR_COST), world.elevator_system.MAX_CARS]
	var info := "建設費 %s円・横%dマス" % [world.format_money(world.BUILDINGS[mode].cost), world.get_width(mode)]
	if world.get_height(mode) > 1:
		info += "・高さ%d階分" % world.get_height(mode)
	if mode == "express_elevator":
		info += "（1階とスカイロビーの階だけに停まる）"
	return info

# 建設メニューの選択と説明を、今のモードに合わせる
func update_mode_select():
	for i in mode_select.item_count:
		if mode_select.get_item_metadata(i) == world.current_mode:
			mode_select.select(i)
	mode_info_label.text = get_mode_info(world.current_mode)

# 資金の表示を更新する関数
func update_funds_display():
	if not funds_label:
		return
	funds_label.text = "現在の資金: %s円" % world.format_money(world.funds)
	if world.economy_system and not world.economy_system.last_report.is_empty():
		funds_label.text += "（前日 %s円）" % world.format_money(world.economy_system.last_report.total, true)

func update_scrollbar():
	var tile_h: float = world.tile_map.tile_set.tile_size.y
	var top_row: int = world.ground_y
	var bottom_row: int = world.ground_y
	for cell: Vector2i in world.building_grid:
		top_row = mini(top_row, cell.y)
		bottom_row = maxi(bottom_row, cell.y)
	var page: float = world.get_viewport_rect().size.y / world.camera.zoom.y # 画面に映っている高さ
	var view_top: float = world.camera.position.y - page / 2.0
	# 範囲を変えると値が範囲内に押し戻されて value_changed が出るので、合わせている間は通知を止める
	# （通知でカメラが動くと、毎フレーム少しずつカメラがずれていってしまう）
	v_scroll.set_block_signals(true)
	v_scroll.min_value = minf((top_row - world.SCROLL_MARGIN_ROWS) * tile_h, view_top)
	v_scroll.max_value = maxf((bottom_row + 1 + world.SCROLL_MARGIN_ROWS) * tile_h, view_top + page)
	v_scroll.page = page
	v_scroll.value = view_top
	v_scroll.set_block_signals(false)

# カーソル下のマスの座標と建物を、マウスの横の吹き出しに表示する
func update_hover_label():
	if not hover_label:
		return
	if not world.grid_overlay.hover_visible:
		hover_label.text = ""
		hover_tooltip.visible = false
		return
	var cell: Vector2i = world.grid_overlay.hover_cell
	var type = world.get_building_type(cell)
	var text = "%s: %s" % [world.get_floor_name(cell.y), world.BUILDINGS[type].name if type != "" else "空き"]
	if world.incident_system.has_roach_at(cell):
		text += "（ゴキブリ発生中）"
	if type == "office" and world.tenant_system.get_rating_text(cell) != "":
		text += "（%s）" % world.tenant_system.get_rating_text(cell)
	if world.hotel_system.is_room_type(type):
		var room_rating: String = world.tenant_system.get_room_rating_text(cell)
		text += "（%s%s・%s）" % [world.hotel_system.get_room_state_text(cell), "・" + room_rating if room_rating != "" else "",
			world.noise_system.get_noise_text(cell)]
	elif type == "restaurant" or type == "fastfood":
		text += "（客 %d人）" % (world.commerce_system.count_eating_at(cell) + world.visitor_system.count_at_shop(cell))
	elif type == "shop":
		text += "（客 %d人）" % world.visitor_system.count_at_shop(cell)
	elif type == "cinema":
		text += "（%s）" % world.visitor_system.get_cinema_text(cell)
	elif world.event_system.is_hall_type(type):
		text += "（来客 %d人）" % world.event_system.count_at_hall(cell)
	elif world.elevator_system.is_shaft_type(type):
		var cars: Array = world.elevator_system.get_cars_at(cell)
		if type == "express_elevator" and not world.is_express_stop_floor(cell.y):
			text += "（この階には停まりません）"
		elif not cars.is_empty():
			if world.elevator_system.get_home(cell) == cell.y:
				text += "（待機階）"
			var service: Dictionary = world.elevator_system.get_service(cell)
			if service.name != "終日":
				text += "（稼働 %s%s）" % [service.name, "" if cars[0].in_service else "・今は停止中"]
			var loads: Array[String] = []
			for car in cars:
				loads.append("%d/%d" % [car.passengers.size(), car.capacity])
			text += "（カゴ%d台: %s人）" % [cars.size(), "・".join(loads)]
	elif type == "housing":
		var home_rating: String = world.tenant_system.get_home_rating_text(cell)
		text += "（%s%s・%s）" % [world.housing_system.get_home_state_text(cell), "・" + home_rating if home_rating != "" else "",
			world.noise_system.get_noise_text(cell)]
	elif type == "parking":
		text += "（%s）" % world.parking_system.get_parking_text(cell)
	elif type == "garden":
		text += "（ストレスの回復 %.1f倍・騒音をやわらげる）" % world.stress_recover_rate()
	elif type == "medical":
		text += "（ビル全体のストレスの回復 %.1f倍）" % world.stress_recover_rate()
	elif type == "recycling":
		text += "（ビル全体の処理能力 %d/日）" % world.economy_system.recycling_capacity()
	var resident = world.get_resident_at(cell)
	if resident:
		text += " / 住人のストレス: %d" % int(resident.stress)
	hover_label.text = text
	show_tooltip(cell)

# 吹き出しを、マウスの右下に出す（画面からはみ出すときは左や上に寄せる）。
# 空きマスのときは出さない（建物や人がいるマスだけ）
func show_tooltip(cell: Vector2i) -> void:
	hover_tooltip.visible = not world.is_cell_empty(cell) or world.get_resident_at(cell) != null
	if not hover_tooltip.visible:
		return
	var offset := Vector2(12, 12) * UI_SCALE
	var size := hover_tooltip.get_combined_minimum_size()
	var screen: Vector2 = world.get_viewport_rect().size
	var pos: Vector2 = world.grid_overlay.hover_screen_pos + offset
	if pos.x + size.x > screen.x:
		pos.x = world.grid_overlay.hover_screen_pos.x - size.x - offset.x
	if pos.y + size.y > screen.y:
		pos.y = world.grid_overlay.hover_screen_pos.y - size.y - offset.y
	hover_tooltip.position = pos.clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))

func update_log_panel() -> void:
	log_label.text = "\n".join(world.message_log)
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

# ---------------------------------------------------
# タイトル画面: 「はじめから」で更地から、「続きから」でセーブデータから始める。
# 始まるまでは時計を止めて、マップの操作も受け付けない。
# ---------------------------------------------------
func build_title() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 2 # ほかのUIより手前に出す
	add_child(canvas)
	var back = ColorRect.new()
	back.color = Color(0.06, 0.07, 0.12, 0.92)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(back)
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # 画面いっぱいに広げて、中身を真ん中にそろえる
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12 * UI_SCALE)
	var theme := Theme.new()
	theme.default_font_size = BASE_FONT_SIZE * UI_SCALE
	box.theme = theme
	back.add_child(box)
	
	var title = Label.new()
	title.text = "ProjectTower"
	title.add_theme_font_size_override("font_size", 48 * UI_SCALE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle = Label.new()
	subtitle.text = "更地から始めて、テナントを入れ、エレベーターを工夫して、ビルの評価（★）を上げよう"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	
	var new_button = Button.new()
	new_button.text = "はじめから"
	new_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	new_button.custom_minimum_size.x = 320 * UI_SCALE
	new_button.pressed.connect(func(): world.start_game())
	box.add_child(new_button)
	var continue_button = Button.new()
	continue_button.text = "続きから（セーブデータを読み込む）"
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.custom_minimum_size.x = 320 * UI_SCALE
	continue_button.disabled = not world.save_system.has_save()
	continue_button.pressed.connect(func():
		world.start_game()
		world.save_system.load_game())
	box.add_child(continue_button)
	var hint = Label.new()
	hint.text = "遊び方は ⌘H（操作説明）。⌘S で保存、⌘O で読み込み、⌘M で音のオン・オフ"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	title_panel = back
	build_goal_panel(canvas, theme)

# 目標を達成したときの画面を作る（中身はそのつど差し替える）
func build_goal_panel(canvas: CanvasLayer, theme: Theme) -> void:
	var back = ColorRect.new()
	back.color = Color(0.06, 0.07, 0.12, 0.88)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.visible = false
	canvas.add_child(back)
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12 * UI_SCALE)
	box.theme = theme
	back.add_child(box)
	goal_title = Label.new()
	goal_title.add_theme_font_size_override("font_size", 32 * UI_SCALE)
	goal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(goal_title)
	goal_text = Label.new()
	goal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(goal_text)
	var close_button = Button.new()
	close_button.text = "つづける"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.custom_minimum_size.x = 240 * UI_SCALE
	close_button.pressed.connect(func(): goal_panel.visible = false)
	box.add_child(close_button)
	goal_panel = back

# 目標の達成などを画面で知らせる（時間は止めずに、ボタンで閉じる）
func show_goal_panel(title: String, text: String) -> void:
	goal_title.text = title
	goal_text.text = text
	goal_panel.visible = true
	world.show_message("%s %s" % [title, text.replace("\n", " ")])

# タイトル画面を閉じる
func hide_title() -> void:
	if title_panel:
		title_panel.visible = false

