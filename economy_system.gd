extends Node

# ---------------------------------------------------
# 収支：毎日0:00に前日分の決算をして、資金に反映する。
#   賃料収入: その日に社員が出勤したオフィス1マスにつき OFFICE_RENT
#             （社員が通勤できない空きオフィスからは入らない）
#   宿泊料:   その日にチェックアウトした客の宿泊料（hotel_system が記録する）
#   飲食売上: その日に飲食店で食事をした客の代金（commerce_system が記録する）
#   維持費:   建物ごとの MAINTENANCE × マス数
# ---------------------------------------------------

const OFFICE_RENT := 10000 # オフィス1マスの1日の賃料
const MAINTENANCE := {     # 1マスの1日の維持費
	"elevator": 2000,
	"housekeeping": 5000,
}

var world: Node2D # main.gd
var last_day := 1 # 最後に決算した日の翌日（= 今日）
var last_report := {} # 最後の決算: {"day", "rent", "hotel", "food", "maintenance", "total"}

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
	var rent := 0
	for cell in world.commute_system.workers:
		if world.commute_system.workers[cell].arrived_day == day and not world.commute_system.workers[cell].unreachable:
			rent += OFFICE_RENT
	var maintenance := 0
	for type in MAINTENANCE:
		maintenance += MAINTENANCE[type] * world.find_cells_of_type(type).size()
	var hotel: int = world.hotel_system.revenue_by_day.get(day, 0)
	var food: int = world.commerce_system.revenue_by_day.get(day, 0)
	var total := rent + hotel + food - maintenance
	last_report = {"day": day, "rent": rent, "hotel": hotel, "food": food, "maintenance": maintenance, "total": total}
	world.funds += total
	world.update_funds_display() # last_reportを更新してから表示する（前日の収支も表示されるため）
	world.show_message("%d日目の決算: 賃料 +%s円 / 宿泊料 +%s円 / 飲食 +%s円 / 維持費 -%s円 / 合計 %s円" % [
		day, world.format_money(rent), world.format_money(hotel), world.format_money(food),
		world.format_money(maintenance), world.format_money(total, true)])
