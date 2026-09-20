extends Node

# ---------------------------------------------------
# 目標（シナリオ）：やることの道しるべ。上から順に1つずつ挑戦する。
#   毎日の決算のあとに達成を確かめ、達成したら画面で知らせて次の目標へ進む。
#   期限を過ぎても続けられる（ゲームオーバーにはしない）。遅れて達成してもよい。
# 目標の中身:
#   stars: この評価（★）以上にする   funds: この資金以上にする
#   population: この人口以上にする    day: 何日目までに（0なら期限なし）
# ---------------------------------------------------

const GOALS := [
	{"name": "ロビーとオフィスを建てて、人口50人と★2をめざそう", "stars": 2, "day": 0},
	{"name": "30日目までに★3（人口120・メディカルセンター・ゴミ処理場）", "stars": 3, "day": 30},
	{"name": "60日目までに★4（人口250・地下鉄駅・VIPの宿泊）", "stars": 4, "day": 60},
	{"name": "90日目までに資金5,000万円をためよう", "funds": 50000000, "day": 90},
]

var world: Node2D # main.gd
var index := 0        # 今挑戦している目標の番号（GOALS.size() になったら全部達成）
var cleared := false  # 全部の目標を達成したか
var warned := {}      # 期限切れを知らせた目標の番号

func setup(p_world: Node2D) -> void:
	world = p_world

func current():
	return GOALS[index] if index < GOALS.size() else null

# 今の目標を達成しているか
func is_achieved(goal: Dictionary) -> bool:
	if goal.has("stars") and world.rating_system.stars < goal.stars:
		return false
	if goal.has("funds") and world.funds < goal.funds:
		return false
	if goal.has("population") and world.rating_system.population() < goal.population:
		return false
	return true

# 決算のあとに呼ばれる。達成・期限切れを確かめる
func check_day(day: int) -> void:
	var goal = current()
	if goal == null:
		return
	if is_achieved(goal):
		index += 1
		world.audio_system.play("money")
		if current() == null:
			cleared = true
			world.show_goal_panel("すべての目標を達成しました！", "おめでとうございます。ここからは、好きなだけビルを大きくしてください。")
		else:
			world.show_goal_panel("目標を達成しました！", "%s\n\n次の目標: %s" % [goal.name, current().name])
		return
	# 期限を過ぎたら一度だけ知らせる（続けて挑戦できる）
	if goal.day > 0 and day >= goal.day and not warned.has(index):
		warned[index] = true
		world.show_message("目標の期限（%d日目）を過ぎました: %s（続けて挑戦できます）" % [goal.day, goal.name])

# 上部バーに出す文
func get_goal_text() -> String:
	var goal = current()
	if goal == null:
		return "目標: すべて達成！"
	if goal.day > 0:
		var left: int = goal.day - world.clock.day
		return "目標: %s（あと%d日）" % [goal.name, maxi(left, 0)]
	return "目標: %s" % goal.name
