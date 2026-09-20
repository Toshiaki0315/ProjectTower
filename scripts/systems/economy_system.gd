extends Node

# ---------------------------------------------------
# 収支：毎日0:00に前日分の決算をして、資金に反映する。
#   賃料収入: その日に社員が出勤したオフィス1マスにつき OFFICE_RENT
#             （社員が通勤できない空きオフィスからは入らない）
#             休日はオフィスが休みだが、入口からたどり着けるオフィスからは契約どおり入る
#             空室のオフィス（テナントが退去した）からは入らない
#   宿泊料:   その日にチェックアウトした客の宿泊料（hotel_system が記録する）
#   飲食売上: その日に飲食店で食事をした客の代金（commerce_system が記録する）
#   住宅販売: その日に入居が決まった住宅の販売収入（housing_system が記録する）
#   住宅の返金: 評価の悪い日が続いて家族が退去した住宅の販売収入を返す（tenant_system が決める）
#   イベント: その日に結婚式場・イベントホールに来た客の料金（event_system が記録する）
#   評価ボーナス: 賃料と宿泊料に、ビルの評価（★）に応じた割合を上乗せ（rating_system）
#   維持費:   建物ごとの MAINTENANCE × 建物（ユニット）の数
#   ゴミ処理: その日の活動で出たゴミのうち、ゴミ処理場で処理しきれない分を外部に委託する費用
#   ショップ: 外から来たお客さんの買い物代（visitor_system が記録する）
#             ゴミの量 = 出勤があったオフィス数 + チェックアウトした客室数 + 飲食店の客数 / 10
#                        + 入居済みの住宅数 + 会場の来客数 / 10
#             処理能力 = ゴミ処理場の数 × RECYCLING_CAPACITY
# ---------------------------------------------------

const OFFICE_RENT := 10000 # オフィス1マスの1日の賃料
const MAINTENANCE := {     # 建物1つの1日の維持費（エレベーターは1マスが1つ）
	"elevator": 2000,
	"express_elevator": 3000,
	"escalator": 2000,
	"service_elevator": 1500,
	"housekeeping": 10000,
	"shop": 3000,
	"recycling": 5000,
	"security": 5000,
	"medical": 10000,
	"subway": 10000,
	"parking": 5000,
	"ramp": 2000,
}
const MEALS_PER_GARBAGE := 10   # 飲食店の客・会場の来客の何人分でゴミ1になるか
const RECYCLING_CAPACITY := 20  # ゴミ処理場1施設が1日に処理できるゴミの量
const OUTSOURCE_COST := 1000    # 処理しきれないゴミ1あたりの外部委託費

var world: Node2D # main.gd
var last_day := 1 # 最後に決算した日の翌日（= 今日）
var last_report := {} # 最後の決算: {"day", "rent", "hotel", "food", "housing", "event", "bonus", "maintenance", "garbage", "garbage_cost", "refund", "total"}

func setup(p_world: Node2D) -> void:
	world = p_world
	last_day = world.clock.day

func _process(_delta: float) -> void:
	# 日付が変わったら、前日分を決算する（早送りで2日以上進んだ場合も1日ずつ）
	while last_day < world.clock.day:
		settle(last_day)
		last_day += 1

# 指定した日の決算
func settle(day: int) -> void:
	var active_offices := 0
	for cell in world.commute_system.workers:
		if world.commute_system.workers[cell].arrived_day == day and not world.commute_system.workers[cell].unreachable:
			active_offices += 1
	var rent_offices := active_offices
	if world.clock.is_holiday(day):
		rent_offices = count_reachable_offices()
	var rent := rent_offices * OFFICE_RENT
	var maintenance := 0
	for type in MAINTENANCE:
		maintenance += MAINTENANCE[type] * world.find_units_of_type(type).size()
	maintenance += world.elevator_system.CAR_MAINTENANCE * world.elevator_system.count_extra_cars()
	var hotel: int = world.hotel_system.revenue_by_day.get(day, 0)
	var food: int = world.commerce_system.revenue_by_day.get(day, 0)
	var checkouts: int = world.hotel_system.checkouts_by_day.get(day, 0)
	var meals: int = food / world.commerce_system.MEAL_PRICE
	var housing: int = world.housing_system.revenue_by_day.get(day, 0)
	var event: int = world.event_system.revenue_by_day.get(day, 0)
	var shop: int = world.visitor_system.revenue_by_day.get(day, 0)
	var shop_customers: int = world.visitor_system.customers_by_day.get(day, 0)
	var event_visitors: int = world.event_system.visitors_by_day.get(day, 0)
	var garbage: int = active_offices + checkouts + meals / MEALS_PER_GARBAGE + world.housing_system.count_moved_in() \
		+ (event_visitors + shop_customers) / MEALS_PER_GARBAGE
	var garbage_cost := maxi(garbage - recycling_capacity(), 0) * OUTSOURCE_COST
	var bonus := int((rent + hotel) * world.rating_system.bonus_rate())
	# テナントの評価（人のストレスから）と、オフィス・住宅の退去・入居。住宅の退去では販売収入を返金する
	var tenants: Dictionary = world.tenant_system.evaluate_day(day)
	var refund: int = tenants.refund
	var total := rent + hotel + food + shop + housing + event + bonus - maintenance - garbage_cost - refund
	last_report = {"day": day, "rent": rent, "hotel": hotel, "food": food, "shop": shop, "housing": housing, "event": event, "bonus": bonus, "maintenance": maintenance,
		"garbage": garbage, "garbage_cost": garbage_cost, "refund": refund, "total": total}
	world.funds += total
	world.update_funds_display() # last_reportを更新してから表示する（前日の収支も表示されるため）
	# 0円の項目は省いて短くする
	var items: Array[String] = []
	for item in [["賃料", rent], ["宿泊料", hotel], ["飲食", food], ["ショップ", shop], ["住宅販売", housing], ["イベント", event], ["評価ボーナス", bonus]]:
		if item[1] > 0:
			items.append("%s +%s円" % [item[0], world.format_money(item[1])])
	if maintenance > 0:
		items.append("維持費 -%s円" % world.format_money(maintenance))
	if garbage_cost > 0:
		items.append("ゴミ処理 -%s円（ゴミ%d・処理能力%d）" % [world.format_money(garbage_cost), garbage, recycling_capacity()])
	if refund > 0:
		items.append("住宅の返金 -%s円（%d戸退去）" % [world.format_money(refund), tenants.homes_left])
	items.append("合計 %s円" % world.format_money(total, true))
	var message := "%d日目の決算: %s" % [day, " / ".join(items)]
	if tenants.left > 0 or tenants.moved_in > 0:
		message += " / オフィス退去 %d棟・入居 %d棟" % [tenants.left, tenants.moved_in]
	# 評価（★）の判定。昇格したら、メッセージの先頭で知らせる（ボーナスは翌日の決算から）
	if world.rating_system.evaluate():
		message = "ビルの評価が★%dに上がりました！ %s" % [world.rating_system.stars, message]
	world.show_message(message)

# 入口からたどり着けるオフィスの数（休日の賃料の計算用）
func count_reachable_offices() -> int:
	var n := 0
	for cell in world.commute_system.workers:
		if not world.tenant_system.is_vacant(cell) and world.nearest_entrance(cell) != null:
			n += 1
	return n

# ビル全体のゴミ処理能力（1日あたり）
func recycling_capacity() -> int:
	return world.find_units_of_type("recycling").size() * RECYCLING_CAPACITY
