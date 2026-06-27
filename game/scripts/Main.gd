# Main.gd — 도마뱀 발사!  (M0 핵심루프 + M1 저장 + M2 진화연출·사운드 + M3 2인대결 + M4 지역·상점)
#
# 모드: SOLO(혼자) / VERSUS(둘이 턴제 대결)
# 상태: TITLE→READY→CHARGE→AIM→FLIGHT→(EVOLVE)→RESULT→MATCH, 그리고 SHOP
#
# 입력 요약:
#   타이틀: [1]/좌측탭=혼자, [2]/우측탭=둘이대결, [3]=상점
#   솔로  : 탭/Space/클릭
#   대결  : P1=A 또는 왼쪽 / P2=L 또는 오른쪽 (자기 차례에만)
#   상점  : [1]/[2] 구매, Esc 뒤로
#   공통  : Esc=타이틀
extends Node2D

enum State { TITLE, READY, CHARGE, AIM, FLIGHT, EVOLVE, RESULT, MATCH, SHOP }
enum Mode { SOLO, VERSUS }

# --- 튜닝 값 ---
const CHARGE_TIME := 3.0
const POWER_PER_TAP := 0.06
const POWER_DECAY := 0.10
const POWER_MAX := 1.2
const ANGLE_SWEEP_SPEED := 75.0   # 튜닝: 110→75 (퍼펙트 타이밍 창 ~3.8프레임, 운→실력)
const SWEET_WINDOW := 24.0        # 스위트스팟 반폭(도) × 진화 sweet_w
const FLIGHT_TIME := 1.4
const EVOLVE_TIME := 2.0
const METER_TO_PX := 2.0          # 튜닝: 4→2 (긴 비거리도 화면 안에서 변별)
const WIN_ROUNDS := 2

# 상점 가격/효과
const SHOP_SCALE_COST := 300   # 가벼운 비늘: drag -0.02
const SHOP_CORE_COST := 500    # 강화 코어: p_mul +0.05

# --- 화면 좌표 ---
const GROUND_Y := 560.0
const LAUNCH_X := 170.0
const MID_X := 640.0

# --- 게임 상태 ---
var state: int = State.TITLE
var mode: int = Mode.SOLO

# 발사 진행
var power := 0.0
var charge_timer := 0.0
var angle := 0.0
var angle_dir := 1.0
var sweet := 0.0
var flight_t := 0.0
var current_wind := 0.0
var last_distance := 0.0
var last_perfect := false
var last_energy := 0

# 진화 연출
var evolve_t := 0.0
var result_center := ""
var result_hint := ""

# 솔로 진척(저장 대상)
var wallet := 0            # 사용 가능한 에너지
var lifetime_energy := 0   # 누적 획득(진화 기준)
var best_distance := 0.0
var total_distance := 0.0  # 누적 비거리(지역 해금)
var drag_bonus := 0.0      # 상점 영구 강화
var pmul_bonus := 0.0
var evo_stage := 0
var region_idx := 0

# 대결 상태
var current_player := 1
var versus_dist := [0.0, 0.0]
var scores := [0, 0]
var round_num := 1
var match_over := false

# --- 노드 ---
var title_label: Label
var center_label: Label
var hint_label: Label
var hud_label: Label
var audio: AudioManager

# --- 스프라이트 ---
var stage_textures: Array = [null, null, null]
const STAGE_IMAGE_EXTS := [".png", ".webp", ".jpg", ".jpeg"]

func _load_stage_textures() -> void:
	for i in range(stage_textures.size()):
		for ext in STAGE_IMAGE_EXTS:
			var path := "res://assets/stage%d%s" % [i, ext]
			if ResourceLoader.exists(path):
				stage_textures[i] = load(path)
				break

func _ready() -> void:
	randomize()
	_load_stage_textures()
	audio = AudioManager.new()
	add_child(audio)
	title_label = _make_label(24, Color.WHITE, Vector2(0, 14), 1280, HORIZONTAL_ALIGNMENT_CENTER)
	hud_label = _make_label(22, Color(0.95, 0.97, 1.0), Vector2(24, 52), 1232, HORIZONTAL_ALIGNMENT_LEFT)
	center_label = _make_label(50, Color.WHITE, Vector2(0, 208), 1280, HORIZONTAL_ALIGNMENT_CENTER)
	hint_label = _make_label(25, Color(1, 1, 1, 0.92), Vector2(0, 612), 1280, HORIZONTAL_ALIGNMENT_CENTER)

	var d := SaveData.load_data()
	wallet = int(d.wallet)
	lifetime_energy = int(d.lifetime_energy)
	best_distance = float(d.best_distance)
	total_distance = float(d.total_distance)
	drag_bonus = float(d.drag_bonus)
	pmul_bonus = float(d.pmul_bonus)
	evo_stage = Evolution.stage_for_energy(lifetime_energy)
	_enter_title()

func _make_label(font_size: int, color: Color, pos: Vector2, width: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.position = pos
	l.size = Vector2(width, 90)
	l.horizontal_alignment = align
	add_child(l)
	return l

func _persist() -> void:
	SaveData.save_data({
		"wallet": wallet,
		"lifetime_energy": lifetime_energy,
		"best_distance": best_distance,
		"total_distance": total_distance,
		"drag_bonus": drag_bonus,
		"pmul_bonus": pmul_bonus,
	})

# 진화 단계 능력치 + 상점 영구 강화 반영
func _effective_stats() -> Dictionary:
	var s: Dictionary = Evolution.stats(evo_stage).duplicate()
	s["drag"] = max(0.5, float(s.drag) - drag_bonus)
	s["p_mul"] = float(s.p_mul) + pmul_bonus
	return s

# ==================== 입력 ====================
func _unhandled_input(event: InputEvent) -> void:
	var kc := -1
	if event is InputEventKey and event.pressed and not event.echo:
		kc = event.keycode
	var mb := event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var touch := event is InputEventScreenTouch and event.pressed
	if kc == -1 and not mb and not touch:
		return
	var px := 0.0
	if mb or touch:
		px = event.position.x

	if kc == KEY_ESCAPE:
		_enter_title()
		return

	match state:
		State.TITLE:
			_title_input(kc, mb, touch, px)
		State.SHOP:
			if kc in [KEY_1, KEY_KP_1]:
				_buy("scale")
			elif kc in [KEY_2, KEY_KP_2]:
				_buy("core")
		State.EVOLVE:
			_finish_evolve()
		State.RESULT:
			if _is_confirm(kc, mb, touch):
				_advance_result()
		State.MATCH:
			if _is_confirm(kc, mb, touch):
				_advance_match()
		_:
			var pid := _acting_player(kc, mb, touch, px)
			if pid == 0:
				return
			if mode == Mode.VERSUS and pid != current_player:
				return
			_gameplay_tap()

func _is_confirm(kc: int, mb: bool, touch: bool) -> bool:
	return mb or touch or kc in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_A, KEY_L]

func _acting_player(kc: int, mb: bool, touch: bool, px: float) -> int:
	if mode == Mode.SOLO:
		return 1
	if kc == KEY_A:
		return 1
	if kc == KEY_L:
		return 2
	if kc in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		return current_player
	if mb or touch:
		return 1 if px < MID_X else 2
	return 0

func _title_input(kc: int, mb: bool, touch: bool, px: float) -> void:
	if kc in [KEY_3, KEY_KP_3]:
		_enter_shop()
		return
	var pick_solo := kc in [KEY_1, KEY_KP_1, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] or ((mb or touch) and px < MID_X)
	var pick_versus := kc in [KEY_2, KEY_KP_2] or ((mb or touch) and px >= MID_X)
	if pick_solo:
		mode = Mode.SOLO
		_enter_ready()
	elif pick_versus:
		mode = Mode.VERSUS
		_start_versus()

func _gameplay_tap() -> void:
	match state:
		State.READY:
			_enter_charge()
		State.CHARGE:
			power = min(power + POWER_PER_TAP, POWER_MAX)
			audio.play("tap")
		State.AIM:
			_lock_angle_and_fly()

# ==================== 상태 전이 ====================
func _enter_title() -> void:
	state = State.TITLE
	evo_stage = Evolution.stage_for_energy(lifetime_energy)
	region_idx = Region.index_for(total_distance)
	center_label.text = "🦎 도마뱀 발사!"
	hint_label.text = "[1] 혼자하기      [2] 둘이 대결      [3] 상점       (화면 좌/우 탭으로도 선택)"
	_refresh_hud()

func _enter_ready() -> void:
	state = State.READY
	power = 0.0
	charge_timer = 0.0
	angle = 0.0
	sweet = 0.0
	if mode == Mode.SOLO:
		region_idx = Region.index_for(total_distance)
		var rg := Region.get_region(region_idx)
		current_wind = randf_range(float(rg.wind_min), float(rg.wind_max))
		center_label.text = ""
		hint_label.text = "[탭/스페이스] 발사 시작!" + _wind_text()
	else:
		current_wind = 0.0
		var key_name := "A" if current_player == 1 else "L"
		var side := "왼쪽" if current_player == 1 else "오른쪽"
		center_label.text = "P%d 준비!" % current_player
		hint_label.text = "P%d 차례 — [%s] 연타 또는 화면 %s 탭으로 시작" % [current_player, key_name, side]
	_refresh_hud()

func _wind_text() -> String:
	if abs(current_wind) < 0.1:
		return "   바람 없음"
	elif current_wind > 0:
		return "   뒷바람 +%.1f" % current_wind
	else:
		return "   맞바람 %.1f" % current_wind

func _enter_charge() -> void:
	state = State.CHARGE
	power = 0.0
	charge_timer = CHARGE_TIME
	center_label.text = ""
	hint_label.text = "연타해서 파워를 채워라! (시간 끝나면 각도 단계)"

func _enter_aim() -> void:
	state = State.AIM
	angle = 0.0
	angle_dir = 1.0
	hint_label.text = "확정 입력! 45° 초록 스위트스팟이 퍼펙트"

func _lock_angle_and_fly() -> void:
	var stats := _effective_stats()
	var window: float = SWEET_WINDOW * float(stats.sweet_w)
	sweet = clamp(1.0 - abs(angle - LaunchFormula.ANGLE_IDEAL) / window, 0.0, 1.0)
	var result := LaunchFormula.compute(power, angle, sweet, stats, current_wind)
	last_distance = result.distance
	last_perfect = result.perfect
	last_energy = LaunchFormula.energy_gain(last_distance, last_perfect)
	state = State.FLIGHT
	flight_t = 0.0
	center_label.text = ""
	hint_label.text = ""
	audio.play("launch")

func _enter_result() -> void:
	audio.play("land")
	if last_perfect:
		audio.play("perfect")
	var perfect_txt := "  ✨PERFECT" if last_perfect else ""
	if mode == Mode.SOLO:
		wallet += last_energy
		lifetime_energy += last_energy
		total_distance += last_distance
		if last_distance > best_distance:
			best_distance = last_distance
		var ns := Evolution.stage_for_energy(lifetime_energy)
		var evolved := ns > evo_stage
		var newly_unlocked := Region.index_for(total_distance) > region_idx
		evo_stage = ns
		region_idx = Region.index_for(total_distance)
		_persist()
		result_center = "%.1f m%s" % [last_distance, perfect_txt]
		if newly_unlocked:
			result_hint = "🗺️ 새 지역 해금! %s   [탭] 계속" % Region.get_region(region_idx).name
		else:
			result_hint = "+%d 에너지   [탭]으로 다시하기" % last_energy
		if evolved:
			_start_evolve()
			return
		state = State.RESULT
		center_label.text = result_center
		hint_label.text = result_hint
	else:
		versus_dist[current_player - 1] = last_distance
		state = State.RESULT
		center_label.text = "P%d : %.1f m%s" % [current_player, last_distance, perfect_txt]
		if current_player == 1:
			hint_label.text = "[L / 오른쪽 탭] → P2 차례로"
		else:
			hint_label.text = "[탭] 라운드 결과 보기"
	_refresh_hud()

func _start_evolve() -> void:
	state = State.EVOLVE
	evolve_t = 0.0
	audio.play("evolve")
	center_label.text = "EVOLVED!"
	hint_label.text = "→ %s   [탭] 건너뛰기" % Evolution.stats(evo_stage).name

func _finish_evolve() -> void:
	state = State.RESULT
	center_label.text = result_center
	hint_label.text = result_hint
	_refresh_hud()

func _advance_result() -> void:
	if mode == Mode.SOLO:
		_enter_ready()
	elif current_player == 1:
		current_player = 2
		_enter_ready()
	else:
		_resolve_round()

# ---- 대결 ----
func _start_versus() -> void:
	scores = [0, 0]
	round_num = 1
	current_player = 1
	versus_dist = [0.0, 0.0]
	match_over = false
	_enter_ready()

func _resolve_round() -> void:
	var d1: float = versus_dist[0]
	var d2: float = versus_dist[1]
	var winner := 0
	if d1 > d2:
		winner = 1
		scores[0] += 1
	elif d2 > d1:
		winner = 2
		scores[1] += 1
	state = State.MATCH
	match_over = scores[0] >= WIN_ROUNDS or scores[1] >= WIN_ROUNDS
	var head := "무승부!" if winner == 0 else "P%d 라운드 승!" % winner
	center_label.text = "%s\nP1 %.1fm   vs   P2 %.1fm" % [head, d1, d2]
	if match_over:
		var champ := 1 if scores[0] > scores[1] else 2
		audio.play("win")
		hint_label.text = "🏆 최종 승자 P%d!  (%d:%d)   [탭] 리매치 · [Esc] 타이틀" % [champ, scores[0], scores[1]]
	else:
		hint_label.text = "스코어 P1 %d : %d P2   [탭] 다음 라운드" % [scores[0], scores[1]]
	_refresh_hud()

func _advance_match() -> void:
	if match_over:
		_start_versus()
	else:
		round_num += 1
		current_player = 1
		versus_dist = [0.0, 0.0]
		_enter_ready()

# ---- 상점 ----
func _enter_shop() -> void:
	state = State.SHOP
	center_label.text = "🛒 상점"
	_refresh_shop_hint()
	_refresh_hud()

func _refresh_shop_hint() -> void:
	hint_label.text = "[1] 가벼운 비늘 -공기저항 (%d)    [2] 강화 코어 +파워 (%d)    [Esc] 뒤로" % [
		SHOP_SCALE_COST, SHOP_CORE_COST]

func _buy(item: String) -> void:
	var cost := SHOP_SCALE_COST if item == "scale" else SHOP_CORE_COST
	if wallet < cost:
		audio.play("land")
		center_label.text = "🛒 상점 — 에너지 부족!"
		_refresh_hud()
		return
	wallet -= cost
	if item == "scale":
		drag_bonus += 0.02
	else:
		pmul_bonus += 0.05
	audio.play("perfect")
	_persist()
	center_label.text = "🛒 상점 — 구매 완료!"
	_refresh_hud()

# ==================== 업데이트 ====================
func _process(delta: float) -> void:
	match state:
		State.CHARGE:
			power = max(power - POWER_DECAY * delta, 0.0)
			charge_timer -= delta
			if charge_timer <= 0.0:
				charge_timer = 0.0
				_enter_aim()
		State.AIM:
			angle += angle_dir * ANGLE_SWEEP_SPEED * delta
			if angle >= 90.0:
				angle = 90.0
				angle_dir = -1.0
			elif angle <= 0.0:
				angle = 0.0
				angle_dir = 1.0
		State.FLIGHT:
			flight_t += delta / FLIGHT_TIME
			if flight_t >= 1.0:
				flight_t = 1.0
				_enter_result()
		State.EVOLVE:
			evolve_t += delta
			if evolve_t >= EVOLVE_TIME:
				_finish_evolve()
	queue_redraw()

func _evo_dots() -> String:
	var dots := ""
	for i in range(Evolution.STAGES.size()):
		dots += "●" if i <= evo_stage else "○"
	return dots

func _refresh_hud() -> void:
	title_label.text = "🦎 도마뱀 발사!  —  제작: justin"
	if mode == Mode.VERSUS and state in [State.READY, State.CHARGE, State.AIM, State.FLIGHT, State.RESULT, State.MATCH]:
		hud_label.text = "VERSUS · R%d (3판 2선승)    P1 %d : %d P2    ▶ 현재 P%d" % [
			round_num, scores[0], scores[1], current_player]
	else:
		var nxt := Evolution.energy_to_next(lifetime_energy)
		var nxt_txt := "다음 진화 %d" % nxt if nxt > 0 else "진화 완료"
		var rg := Region.get_region(region_idx)
		hud_label.text = "진화 %s %s   💠 %d (%s)   🏅 %.1fm   📍 %s" % [
			_evo_dots(), Evolution.stats(evo_stage).name, wallet, nxt_txt, best_distance, rg.name]

# ==================== 렌더링 ====================
func _draw() -> void:
	var rg := Region.get_region(region_idx)
	var sky: Color = rg.sky if mode == Mode.SOLO else Color(0.52, 0.78, 0.92)
	var ground: Color = rg.ground if mode == Mode.SOLO else Color(0.40, 0.62, 0.32)
	draw_rect(Rect2(0, 0, 1280, 720), sky)
	draw_rect(Rect2(0, GROUND_Y, 1280, 720 - GROUND_Y), ground)

	if state == State.TITLE:
		_draw_lizard(Vector2(MID_X, 400), Evolution.stats(evo_stage).color, 1.0)
		return
	if state == State.SHOP:
		_draw_lizard(Vector2(MID_X, 400), Evolution.stats(evo_stage).color, 1.0)
		return

	if state == State.EVOLVE:
		# 진화 연출: 점멸 + 확대 펄스
		var flash := 0.5 + 0.5 * sin(evolve_t * 18.0)
		draw_rect(Rect2(0, 0, 1280, 720), Color(1, 1, 1, flash * 0.6))
		var pulse := 1.0 + 0.6 * sin(evolve_t * 6.0)
		_draw_lizard(Vector2(MID_X, 380), Evolution.stats(evo_stage).color, pulse)
		return

	draw_rect(Rect2(LAUNCH_X - 40, GROUND_Y - 14, 90, 14), Color(0.35, 0.25, 0.18))

	if mode == Mode.VERSUS and state in [State.READY, State.CHARGE, State.AIM, State.FLIGHT]:
		var pcol := Color(0.95, 0.4, 0.4) if current_player == 1 else Color(0.4, 0.6, 0.95)
		draw_circle(Vector2(LAUNCH_X + 5, GROUND_Y - 90), 10.0, pcol)

	var liz_pos := Vector2(LAUNCH_X, GROUND_Y - 26)
	if state == State.FLIGHT:
		liz_pos = _flight_pos(flight_t)
	_draw_lizard(liz_pos, Evolution.stats(evo_stage).color, 1.0)

	match state:
		State.CHARGE:
			_draw_power_bar()
			_draw_timer_bar()
		State.AIM:
			_draw_power_bar()
			_draw_angle_indicator()

func _flight_pos(t: float) -> Vector2:
	var reach: float = min(last_distance * METER_TO_PX, 980.0)
	var x := LAUNCH_X + reach * t
	var arc := 220.0 + sin(deg_to_rad(angle)) * 160.0
	var y := (GROUND_Y - 26) - arc * sin(PI * t)
	return Vector2(x, y)

func _draw_lizard(pos: Vector2, body: Color, scale := 1.0) -> void:
	var tex: Texture2D = stage_textures[evo_stage]
	if tex != null:
		var target := 110.0 * scale
		var sc := target / float(max(tex.get_width(), tex.get_height()))
		var w := tex.get_width() * sc
		var h := tex.get_height() * sc
		draw_texture_rect(tex, Rect2(pos.x - w / 2.0, pos.y - h / 2.0, w, h), false)
		return
	var r := 20.0 * scale
	draw_circle(pos, r, body)
	draw_circle(pos + Vector2(12, -8) * scale, 6.0 * scale, Color.WHITE)
	draw_circle(pos + Vector2(14, -8) * scale, 3.0 * scale, Color.BLACK)
	draw_circle(pos + Vector2(-18, 6) * scale, 8.0 * scale, body.darkened(0.15))

func _draw_power_bar() -> void:
	var x := 200.0
	var y := 660.0
	var w := 880.0
	var h := 26.0
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.35))
	var fill: float = clamp(power, 0.0, POWER_MAX) / POWER_MAX
	var col := Color(0.95, 0.75, 0.2)
	if power > 1.0:
		col = Color(0.40, 0.85, 0.55)  # 100% 초과: 보너스 구간(초록)
	draw_rect(Rect2(x, y, w * fill, h), col)
	var mark := x + w * (1.0 / POWER_MAX)
	draw_line(Vector2(mark, y - 4), Vector2(mark, y + h + 4), Color.WHITE, 2.0)

func _draw_timer_bar() -> void:
	var x := 200.0
	var y := 694.0
	var w := 880.0
	draw_rect(Rect2(x, y, w, 8), Color(0, 0, 0, 0.25))
	var frac: float = clamp(charge_timer / CHARGE_TIME, 0.0, 1.0)
	draw_rect(Rect2(x, y, w * frac, 8), Color(1, 1, 1, 0.85))

func _draw_angle_indicator() -> void:
	var origin := Vector2(LAUNCH_X, GROUND_Y - 26)
	var stats := _effective_stats()
	var window: float = SWEET_WINDOW * float(stats.sweet_w)
	var lo := LaunchFormula.ANGLE_IDEAL - window
	var hi := LaunchFormula.ANGLE_IDEAL + window
	_draw_angle_ray(origin, lo, Color(0.3, 0.9, 0.4, 0.5), 160.0)
	_draw_angle_ray(origin, hi, Color(0.3, 0.9, 0.4, 0.5), 160.0)
	_draw_angle_ray(origin, LaunchFormula.ANGLE_IDEAL, Color(0.3, 0.9, 0.4, 0.8), 175.0)
	_draw_angle_ray(origin, angle, Color(0.95, 0.25, 0.2), 200.0)

func _draw_angle_ray(origin: Vector2, deg: float, color: Color, length: float) -> void:
	var dir := Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)))
	draw_line(origin, origin + dir * length, color, 4.0)
