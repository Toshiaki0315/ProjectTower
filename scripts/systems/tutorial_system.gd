extends Node

# ---------------------------------------------------
# はじめての案内（チュートリアル）：最初に何をすればよいかを順に見せる。
#   画面の上のほうに1行ずつ出し、その通りにできたら次の案内へ進む。
#   「案内を閉じる」でいつでもやめられる（もう出ない）。進み具合はセーブに入る。
# ---------------------------------------------------

const STEPS := [
	"① まず1階にロビーを建てよう（建設メニューで「ロビー」を選び、地面の上をクリック。ドラッグで横に伸ばせる）",
	"② ロビーの隣に「エレベーター」か「階段」を建てて、上の階へ行けるようにしよう",
	"③ 2階から上に「オフィス」を建てよう（社員が出勤すると賃料が入る）",
	"④ 速度ボタン（1x）を押して時間を進め、社員が出勤するようすを見てみよう",
	"⑤ 毎日0時に決算がある。⌘G で収支のグラフ、⌘H でくわしい操作説明を見られる",
]

var world: Node2D # main.gd
var step := 0      # 今の案内の番号
var finished := false # 案内を終えた（または閉じた）か

func setup(p_world: Node2D) -> void:
	world = p_world

func current_text() -> String:
	return "" if finished or step >= STEPS.size() else STEPS[step]

func _process(_delta: float) -> void:
	if finished or not world.started:
		return
	if is_step_done(step):
		step += 1
		if step >= STEPS.size():
			finished = true
			world.show_message("案内はここまでです。目標をめざして、ビルを大きくしていきましょう！")
		else:
			world.audio_system.play("build")

# その案内のとおりにできたか
func is_step_done(index: int) -> bool:
	match index:
		0:
			return not world.find_cells_of_type("lobby").is_empty()
		1:
			for type in ["stairs", "escalator", "elevator", "express_elevator", "service_elevator"]:
				if not world.find_cells_of_type(type).is_empty():
					return true
			return false
		2:
			return not world.find_units_of_type("office").is_empty()
		3:
			return world.clock.minute_of_day() >= 9 * 60 or Engine.time_scale > 1.0
		4:
			return not world.economy_system.history.is_empty()
	return false

# 「案内を閉じる」を押したとき
func skip() -> void:
	finished = true
	world.show_message("案内を閉じました（操作の説明は ⌘H でいつでも見られます）")
