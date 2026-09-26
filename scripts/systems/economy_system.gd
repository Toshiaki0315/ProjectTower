extends Node

# ---------------------------------------------------
# 収支：毎日0:00に前日分の決算をして、資金に反映する。
#   賃料収入: その日に社員が出勤したオフィス1マスにつき OFFICE_RENTS（オフィスの種類・家賃の設定・何階かで変わる）
#             （社員が通勤できない空きオフィスからは入らない）
#             休日はオフィスが休みだが、入口からたどり着けるオフィスからは契約どおり入る
#             空室のオフィス（テナントが退去した）からは入らない
#   宿泊料:   その日にチェックアウトした客の宿泊料（hotel_system が記録する）
#   飲食売上: その日に飲食店で食事をした客の代金（commerce_system が記録する）
#   住宅販売: その日に入居が決まった住宅の販売収入（housing_system が記録する）
#   管理費:   入居している住宅1戸につき housing_system.MANAGEMENT_FEE
#   住宅の返金: 評価の悪い日が続いて家族が退去した住宅の販売収入を返す（tenant_system が決める）
#   イベント: その日に結婚式場・イベントホールに来た客の料金（event_system が記録する）
#   評価ボーナス: 賃料と宿泊料に、ビルの評価（★）に応じた割合を上乗せ（rating_system）
#   維持費:   建物ごとの MAINTENANCE × 建物（ユニット）の数
#   ゴミ処理: その日の活動で出たゴミのうち、ゴミ処理場で処理しきれない分を外部に委託する費用。
#             処理しきれない日が続くとビルが汚れ（衛生の悪化）、すべてのテナントの評価が下がる。
#             夜0時の決算でまだ掃除されていない客室（ハウスキーパーが足りない）も、衛生を悪くする
#   ショップ: 外から来たお客さんの買い物代（visitor_system が記録する）
#   映画館:   上映ごとに来たお客さんの料金（visitor_system が記録する）
#             ゴミの量 = 出勤があったオフィス数 + チェックアウトした客室数 + 飲食店の客数 / 10
#                        + 入居済みの住宅数 + 会場の来客数 / 10
#             処理能力 = ゴミ処理場の数 × RECYCLING_CAPACITY
# ---------------------------------------------------

# オフィス1マスの1日の賃料。小さいオフィスは割高、大きいオフィスはまとめ借りで割安
const OFFICE_RENTS := {
	"small_office": 11000,
	"office": 10000,
	"large_office": 9000,
}
# 高い階ほど賃料が高い（眺めがよい）: FLOOR_RENT_STEP 階ごとに FLOOR_RENT_BONUS ずつ上がる（上限 FLOOR_RENT_MAX 倍）。
# 2〜5階は1倍、6〜10階は1.1倍、11〜15階は1.2倍…。地下は日が当たらないので BASEMENT_RENT_RATE 倍
const FLOOR_RENT_STEP := 5
const FLOOR_RENT_BONUS := 0.1
const FLOOR_RENT_MAX := 2.0
const BASEMENT_RENT_RATE := 0.8
const MAINTENANCE := {     # 建物1つの1日の維持費（エレベーターは1マスが1つ）
	"elevator": 2000,
	"express_elevator": 3000,
	"large_elevator": 3000, # 大型は1階ぶん（横2マス）で3,000Cr
	"escalator": 2000,
	"service_elevator": 1500,
	"housekeeping": 10000,
	"shop": 3000,
	"fastfood": 2000,
	"cinema": 20000,
	"recycling": 5000,
	"security": 5000,
	"medical": 10000,
	"subway": 10000,
	"helipad": 10000,
	"garden": 5000,
	"observatory": 15000,
	"parking": 5000,
	"ramp": 2000,
}
const MEALS_PER_GARBAGE := 10   # 飲食店の客・会場の来客の何人分でゴミ1になるか
const RECYCLING_CAPACITY := 20  # ゴミ処理場1施設が1日に処理できるゴミの量
const OUTSOURCE_COST := 1000    # 処理しきれないゴミ1あたりの外部委託費
const HISTORY_MAX := 60         # 収支のグラフに残す日数
# 衛生の悪化: ゴミ処理が追いつかない日が続くと、ビルが汚れてテナントの評価が下がる
const GARBAGE_PER_POLLUTION := 5 # 処理しきれないゴミがこの量になるごとに、悪化のレベルが1上がる
const POLLUTION_MAX := 5         # 悪化のレベルの上限
const POLLUTION_STRESS := 5.0    # 悪化のレベル1につき、テナントの評価に足されるストレス
const UNCLEAN_PER_POLLUTION := 2 # 決算のときに掃除されていない客室が、この数ごとに悪化のレベルが1上がる

var world: Node2D # main.gd
var last_day := 1 # 最後に決算した日の翌日（= 今日）
var pollution := 0    # 衛生の悪化のレベル（0〜POLLUTION_MAX）
var history: Array = [] # 決算の記録（新しいものが後ろ。収支のグラフで使う）
var last_report := {} # 最後の決算: {"day", "rent", "hotel", "food", "housing", "event", "bonus", "maintenance", "garbage", "garbage_cost", "refund", "total"}

func setup(p_world: Node2D) -> void:
	world = p_world
	last_day = world.clock.day

func _process(_delta: float) -> void:
	# 日付が変わったら、前日分を決算する（早送りで2日以上進んだ場合も1日ずつ）
	while last_day < world.clock.day:
		settle(last_day)
		last_day += 1

# 衛生の悪化のぶん、テナントの評価に足されるストレス
func pollution_stress() -> float:
	return pollution * POLLUTION_STRESS

# 指定した日の決算
func settle(day: int) -> void:
	var active_offices := 0
	var rent := 0
	for cell in world.commute_system.workers:
		if world.commute_system.workers[cell].arrived_day == day and not world.commute_system.workers[cell].unreachable:
			active_offices += 1
			rent += office_rent(cell)
	if world.clock.is_holiday(day):
		rent = holiday_rent() # 休日はオフィスが休みでも、契約どおり賃料が入る
	var maintenance := 0
	for type in MAINTENANCE:
		maintenance += MAINTENANCE[type] * world.find_units_of_type(type).size()
	maintenance += world.elevator_system.CAR_MAINTENANCE * world.elevator_system.count_extra_cars()
	var hotel: int = world.hotel_system.revenue_by_day.get(day, 0)
	var food: int = world.commerce_system.revenue_by_day.get(day, 0)
	var checkouts: int = world.hotel_system.checkouts_by_day.get(day, 0)
	var meals: int = world.commerce_system.meals_by_day.get(day, 0)
	var housing: int = world.housing_system.revenue_by_day.get(day, 0)
	var housing_fee: int = world.housing_system.count_moved_in() * world.housing_system.MANAGEMENT_FEE
	var event: int = world.event_system.revenue_by_day.get(day, 0)
	var shop: int = world.visitor_system.revenue_by_day.get(day, 0)
	var cinema: int = world.visitor_system.cinema_revenue_by_day.get(day, 0)
	var observatory: int = world.visitor_system.observatory_revenue_by_day.get(day, 0)
	var shop_customers: int = world.visitor_system.customers_by_day.get(day, 0)
	var event_visitors: int = world.event_system.visitors_by_day.get(day, 0)
	var garbage: int = active_offices + checkouts + meals / MEALS_PER_GARBAGE + world.housing_system.count_moved_in() \
		+ (event_visitors + shop_customers) / MEALS_PER_GARBAGE
	var overflow := maxi(garbage - recycling_capacity(), 0)
	var garbage_cost := overflow * OUTSOURCE_COST
	# 処理しきれないゴミが多い日や、掃除が追いつかない客室が残った日は衛生が悪化し、
	# どちらもない日は少しずつよくなる
	var unclean: int = world.hotel_system.count_rooms(world.hotel_system.RoomState.DIRTY)
	if overflow > 0 or unclean > 0:
		pollution = mini(pollution + overflow / GARBAGE_PER_POLLUTION + unclean / UNCLEAN_PER_POLLUTION, POLLUTION_MAX)
	else:
		pollution = maxi(pollution - 1, 0)
	var bonus := int((rent + hotel) * world.rating_system.bonus_rate())
	# テナントの評価（人のストレスから）と、オフィス・住宅の退去・入居。住宅の退去では販売収入を返金する
	var tenants: Dictionary = world.tenant_system.evaluate_day(day)
	var refund: int = tenants.refund
	var total := rent + hotel + food + shop + cinema + observatory + housing + housing_fee + event + bonus - maintenance - garbage_cost - refund
	last_report = {"day": day, "rent": rent, "hotel": hotel, "food": food, "shop": shop, "cinema": cinema, "observatory": observatory, "housing": housing, "housing_fee": housing_fee, "event": event, "bonus": bonus, "maintenance": maintenance,
		"garbage": garbage, "garbage_cost": garbage_cost, "unclean": unclean, "pollution": pollution, "refund": refund, "total": total}
	history.append(last_report)
	if history.size() > HISTORY_MAX:
		history.remove_at(0)
	world.funds += total
	world.update_funds_display() # last_reportを更新してから表示する（前日の収支も表示されるため）
	# 0の項目は省いて短くする
	var items: Array[String] = []
	for item in [["賃料", rent], ["宿泊料", hotel], ["飲食", food], ["ショップ", shop], ["映画館", cinema], ["展望台", observatory], ["住宅販売", housing], ["管理費", housing_fee], ["イベント", event], ["評価ボーナス", bonus]]:
		if item[1] > 0:
			items.append("%s +%s" % [item[0], world.money_text(item[1])])
	if maintenance > 0:
		items.append("維持費 -%s" % world.money_text(maintenance))
	if garbage_cost > 0:
		items.append("ゴミ処理 -%s（ゴミ%d・処理能力%d）" % [world.money_text(garbage_cost), garbage, recycling_capacity()])
	if unclean > 0:
		items.append("掃除の済んでいない客室 %d室（ハウスキーパー室が足りません）" % unclean)
	if pollution > 0:
		items.append("衛生の悪化 レベル%d（テナントの評価が下がります）" % pollution)
	if refund > 0:
		items.append("住宅の返金 -%s（%d戸退去）" % [world.money_text(refund), tenants.homes_left])
	items.append("合計 %s" % world.money_text(total, true))
	var message := "%s（%d日目）の決算: %s" % [world.clock.date_text(day), day, " / ".join(items)]
	if tenants.left > 0 or tenants.moved_in > 0:
		message += " / オフィス退去 %d棟・入居 %d棟" % [tenants.left, tenants.moved_in]
	# 評価（★）の判定。上がった・下がったら、メッセージの先頭で知らせる（ボーナスは翌日の決算から）
	var rating = world.rating_system
	match rating.evaluate():
		1:
			message = "ビルの評価が★%dに上がりました！ %s" % [rating.stars, message]
		-1:
			message = "★%dの条件を%d日続けて満たせなかったので、ビルの評価が★%dに下がりました… %s" % [rating.stars + 1,
				rating.DEMOTE_DAYS, rating.stars, message]
		_:
			if rating.demotion_warning() != "":
				message += " / " + rating.demotion_warning()
	# 入口のあたりに「+◯◯Cr」を浮かせる（黒字のときだけ）
	var entrance = world.get_entrance()
	if total > 0 and entrance != null:
		world.effects.play_money(entrance, total)
	world.audio_system.play("money")
	world.show_message(message)
	world.goal_system.check_day(day) # 目標を達成したか確かめる
	world.request_system.check_day(day) # テナントからの頼みごとが、かなったか・期限が切れたか
	world.save_system.autosave() # 決算のあとの状態を、オートセーブの枠に保存する

# オフィスの1マスの1日の賃料（オフィスの種類で変わる）
func office_rent(cell: Vector2i) -> int:
	# 家賃の設定と、何階か（高い階ほど高い）で変わる
	return int(OFFICE_RENTS.get(world.get_building_type(cell), 0) * world.tenant_system.rent_rate(cell) * floor_rent_rate(cell.y))

# その階の賃料の倍率（高い階ほど高い。地下は安い）
func floor_rent_rate(y: int) -> float:
	if y > world.ground_y:
		return BASEMENT_RENT_RATE
	var floor_number: int = world.ground_y - y + 1 # 1階 = 1
	return minf(1.0 + FLOOR_RENT_BONUS * ((floor_number - 1) / FLOOR_RENT_STEP), FLOOR_RENT_MAX)

# 入口からたどり着けるオフィスの賃料の合計（休日の計算用）
func holiday_rent() -> int:
	var total := 0
	for cell in world.commute_system.workers:
		if not world.tenant_system.is_vacant(cell) and world.nearest_entrance(cell) != null:
			total += office_rent(cell)
	return total

# ビル全体のゴミ処理能力（1日あたり）
func recycling_capacity() -> int:
	return world.find_units_of_type("recycling").size() * RECYCLING_CAPACITY
