extends Node

# ---------------------------------------------------
# VIPの宿泊（★4への昇格イベント）:
#   人口や建物の条件（rating_system.REQUIREMENTS）を満たすと、その日の ARRIVE_MINUTE にVIPが来館する。
#   VIPは入口から、きれいな空きスイートへ向かう。
#   合格の条件: 部屋に着いたときのストレスが STRESS_LIMIT 以下で、部屋がまだきれいなこと。
#     合格 … その部屋に泊まり（普通の宿泊客と同じく朝チェックアウトする）、★4に昇格できるようになる。
#     不合格 … そのまま帰る。次の日にまた来る。
#   きれいな空きスイートがない日や、スイートまでの道がない日は来られない（メッセージで知らせる）。
# ---------------------------------------------------

const VIP_COLOR := Color(1.0, 0.85, 0.2) # VIPの服の色（金色）
const STRESS_LIMIT := 30.0 # これを超えるストレスでスイートに着くと不合格
const ARRIVE_MINUTE := 16 * 60 # VIPが来る時刻（普通の宿泊客のチェックイン17時より前）
const LEAVE_MINUTE := 22 * 60  # この時刻までにたどり着けなければ、その日は不合格

var world: Node2D # main.gd

var passed := false      # VIPを満足させたか（★4の条件の1つ）
var visit_day := 0       # 最後にVIPが来た日
var vip = null           # 来館中のVIP（住人）
var room_origin := Vector2i.ZERO # 向かっているスイート（左端のマス）

func setup(p_world: Node2D) -> void:
	world = p_world

# 今、VIPが来館中か
func is_visiting() -> bool:
	return is_instance_valid(vip)

func _process(_delta: float) -> void:
	var day: int = world.clock.day
	var now: int = world.clock.minute_of_day()
	if not passed and visit_day != day and now >= ARRIVE_MINUTE and now < LEAVE_MINUTE and world.rating_system.waiting_for_vip():
		visit_day = day
		invite()
	if is_visiting():
		process_vip(day, now)

# VIPを呼ぶ（きれいな空きスイートを探して、入口から向かわせる）
func invite() -> void:
	var suite = find_clean_suite()
	if suite == null:
		world.show_message("VIPが来ようとしましたが、泊まれるスイート（きれいな空室）がありません")
		return
	room_origin = suite
	var entrance = world.nearest_entrance(room_origin)
	if entrance == null:
		world.show_message("VIPが来ようとしましたが、スイートまでの道がありません")
		return
	vip = world.spawn_resident(entrance)
	vip.base_color = VIP_COLOR
	if not vip.go_to(room_origin):
		world.show_message("VIPがスイートまでたどり着けないため、帰ってしまいました")
		vip.queue_free()
		vip = null
		return
	world.show_message("VIPが来館しました！ スイートまで待たせずに案内できれば、★4に昇格できます")

# きれいな空きスイート（左端のマス）を探す。なければnull
func find_clean_suite():
	var hotel = world.hotel_system
	for origin in world.find_units_of_type("hotel_suite"):
		if hotel.rooms.has(origin) and hotel.rooms[origin].state == hotel.RoomState.CLEAN:
			return origin
	return null

func process_vip(day: int, now: int) -> void:
	# 時間切れ（夜までに着かなかった）
	if now >= LEAVE_MINUTE:
		fail("VIPは待ちくたびれて帰ってしまいました（明日もう一度来ます）")
		return
	if vip.is_moving():
		return
	if vip.cell != room_origin:
		fail("VIPがスイートまでたどり着けず、帰ってしまいました")
		return
	# スイートに着いた: ストレスと部屋の状態で合否を決める
	var hotel = world.hotel_system
	if not hotel.rooms.has(room_origin) or hotel.rooms[room_origin].state != hotel.RoomState.CLEAN:
		fail("VIPが着いたとき、スイートが使えませんでした（明日もう一度来ます）")
		return
	if vip.stress > STRESS_LIMIT:
		fail("VIPを待たせてしまいました（ストレス%d）。★4の昇格はおあずけです" % int(vip.stress))
		return
	succeed(day)

# 合格: VIPはその部屋に泊まる（朝は普通の宿泊客と同じようにチェックアウトする）
func succeed(day: int) -> void:
	passed = true
	var room: Dictionary = world.hotel_system.rooms[room_origin]
	room.state = world.hotel_system.RoomState.OCCUPIED
	room.guests = [vip]
	room.checkin_day = day
	room.stay_peak = vip.stress
	vip = null
	world.show_message("VIPがスイートに満足しました！ 条件がそろえば、次の決算で★4に昇格します")

# 不合格: VIPは帰る（次の日にまた来る）
func fail(message: String) -> void:
	if is_visiting():
		vip.queue_free()
	vip = null
	world.show_message(message)
