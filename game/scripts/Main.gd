# Main.gd — 도마뱀 발사! M0 프로토타입
#
# 핵심 루프(2단계 발사): READY → CHARGE(파워 연타) → AIM(각도 타이밍) → FLIGHT → RESULT
# 입력: Space/Enter(ui_accept) 또는 마우스 클릭/터치 = "탭"
# 본 프로토타입은 1인 플레이. 2인 턴제는 M3에서 Session 분리 예정.
extends Node2D

enum State { READY, CHARGE, AIM, FLIGHT, RESULT }

# --- 튜닝 값 (game-design.md §9) ---
const CHARGE_TIME := 3.0          # 파워 충전 제한시간(초)
const POWER_PER_TAP := 0.06       # 연타 1회당 파워 증가
const POWER_DECAY := 0.10         # 게이지 자연 감소/초
const POWER_MAX := 1.2            # 오버차지 상한
const ANGLE_SWEEP_SPEED := 110.0  # 각도 바늘 왕복 속도(도/초)
const FLIGHT_TIME := 1.4          # 비행 연출 시간(초)
const METER_TO_PX := 4.0          # 비거리 1m당 화면 픽셀(연출용)

# --- 화면 좌표 ---
const GROUND_Y := 560.0
const LAUNCH_X := 170.0

# --- 상태 ---
var state: int = State.READY
var power := 0.0
var charge_timer := 0.0
var angle := 0.0
var angle_dir := 1.0
var sweet := 0.0
var flight_t := 0.0
var last_distance := 0.0
var last_perfect := false
var last_energy := 0

# --- 진척(누적) ---
var total_energy := 0
var best_distance := 0.0
var evo_stage := 0

# --- UI 노드 ---
var title_label: Label
var center_label: Label
var hint_label: Label
var hud_label: Label

func _ready() -> void:
	title_label = _make_label(28, Color.WHITE)
	title_label.position = Vector2(0, 16)
	title_label.size = Vector2(1280, 40)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	hud_label = _make_label(22, Color(0.9, 0.95, 1.0))
	hud_label.position = Vector2(24, 56)

	center_label = _make_label(52, Color.WHITE)
	center_label.position = Vector2(0, 230)
	center_label.size = Vector2(1280, 120)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	hint_label = _make_label(26, Color(1, 1, 1, 0.85))
	hint_label.position = Vector2(0, 620)
	hint_label.size = Vector2(1280, 40)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_enter_ready()

func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l

# ---------------- 입력 ----------------
func _unhandled_input(event: InputEvent) -> void:
	var tapped := false
	if event.is_action_pressed("ui_accept"):
		tapped = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true
	if tapped:
		_on_tap()

func _on_tap() -> void:
	match state:
		State.READY:
			_enter_charge()
		State.CHARGE:
			power = min(power + POWER_PER_TAP, POWER_MAX)
		State.AIM:
			_lock_angle_and_fly()
		State.RESULT:
			_enter_ready()

# ---------------- 상태 전이 ----------------
func _enter_ready() -> void:
	state = State.READY
	power = 0.0
	charge_timer = 0.0
	angle = 0.0
	sweet = 0.0
	evo_stage = Evolution.stage_for_energy(total_energy)
	center_label.text = ""
	hint_label.text = "[탭/스페이스]로 발사 시작!"
	_refresh_hud()

func _enter_charge() -> void:
	state = State.CHARGE
	power = 0.0
	charge_timer = CHARGE_TIME
	center_label.text = ""
	hint_label.text = "연타해서 파워를 채워라! (시간 끝나면 각도 단계로)"

func _enter_aim() -> void:
	state = State.AIM
	angle = 0.0
	angle_dir = 1.0
	hint_label.text = "[탭]으로 각도 확정! 45° 근처가 퍼펙트"

func _lock_angle_and_fly() -> void:
	# 스위트스팟: 45°에 가까울수록 1.0 (진화 시 sweet_w로 너그러워짐)
	var stats := Evolution.stats(evo_stage)
	var window: float = 20.0 * float(stats.sweet_w)
	sweet = clamp(1.0 - abs(angle - LaunchFormula.ANGLE_IDEAL) / window, 0.0, 1.0)

	var result := LaunchFormula.compute(power, angle, sweet, stats)
	last_distance = result.distance
	last_perfect = result.perfect
	last_energy = LaunchFormula.energy_gain(last_distance, last_perfect)

	state = State.FLIGHT
	flight_t = 0.0
	hint_label.text = ""
	center_label.text = ""

func _enter_result() -> void:
	state = State.RESULT
	# 정산
	total_energy += last_energy
	if last_distance > best_distance:
		best_distance = last_distance
	var new_stage := Evolution.stage_for_energy(total_energy)
	var evolved := new_stage > evo_stage
	evo_stage = new_stage

	var line := "%.1f m" % last_distance
	if last_perfect:
		line += "  ✨PERFECT"
	center_label.text = line
	if evolved:
		hint_label.text = "🌟 진화! → %s   [탭]으로 계속" % Evolution.stats(evo_stage).name
	else:
		hint_label.text = "+%d 에너지   [탭]으로 다시하기" % last_energy
	_refresh_hud()

# ---------------- 업데이트 ----------------
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
	queue_redraw()

func _refresh_hud() -> void:
	var st := Evolution.stats(evo_stage)
	var dots := ""
	for i in range(Evolution.STAGES.size()):
		dots += "●" if i <= evo_stage else "○"
	var nxt := Evolution.energy_to_next(total_energy)
	var nxt_txt := ("다음 진화까지 %d" % nxt) if nxt > 0 else "최종 진화 달성"
	hud_label.text = "진화 %s  %s    💠 %d (%s)    🏅 최고 %.1fm" % [
		dots, st.name, total_energy, nxt_txt, best_distance]
	title_label.text = "🦎 도마뱀 발사!  —  제작: justin"

# ---------------- 렌더링 ----------------
func _draw() -> void:
	# 배경(하늘) + 땅
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.52, 0.78, 0.92))
	draw_rect(Rect2(0, GROUND_Y, 1280, 720 - GROUND_Y), Color(0.40, 0.62, 0.32))
	# 발사대
	draw_rect(Rect2(LAUNCH_X - 40, GROUND_Y - 14, 90, 14), Color(0.35, 0.25, 0.18))

	var st := Evolution.stats(evo_stage)

	# 도마뱀 위치
	var liz_pos := Vector2(LAUNCH_X, GROUND_Y - 26)
	if state == State.FLIGHT:
		liz_pos = _flight_pos(flight_t)
	_draw_lizard(liz_pos, st.color)

	# 단계별 게이지/인디케이터
	match state:
		State.CHARGE:
			_draw_power_bar()
			_draw_timer_bar()
		State.AIM:
			_draw_power_bar()
			_draw_angle_indicator()

func _flight_pos(t: float) -> Vector2:
	# 연출용 포물선: 비거리에 비례해 도착 x, 발사각에 비례해 정점 높이
	var reach := min(last_distance * METER_TO_PX, 980.0)
	var x := LAUNCH_X + reach * t
	var arc := 220.0 + sin(deg_to_rad(angle)) * 160.0
	var y := (GROUND_Y - 26) - arc * sin(PI * t)
	return Vector2(x, y)

func _draw_lizard(pos: Vector2, body: Color) -> void:
	draw_circle(pos, 20.0, body)                                  # 몸통
	draw_circle(pos + Vector2(12, -8), 6.0, Color.WHITE)          # 눈 흰자
	draw_circle(pos + Vector2(14, -8), 3.0, Color.BLACK)          # 눈동자
	draw_circle(pos + Vector2(-18, 6), 8.0, body.darkened(0.15))  # 꼬리

func _draw_power_bar() -> void:
	var x := 200.0
	var y := 660.0
	var w := 880.0
	var h := 26.0
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.35))
	var fill: float = clamp(power, 0.0, POWER_MAX) / POWER_MAX
	var col := Color(0.95, 0.75, 0.2)
	if power > 1.0:
		col = Color(0.95, 0.35, 0.25)  # 오버차지 경고색
	draw_rect(Rect2(x, y, w * fill, h), col)
	# 100% 기준선
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
	# 발사 각도 바늘 (발사대에서 뻗는 선) + 스위트스팟 표시
	var origin := Vector2(LAUNCH_X, GROUND_Y - 26)
	var stats := Evolution.stats(evo_stage)
	var window: float = 20.0 * float(stats.sweet_w)
	# 스위트스팟 부채꼴(초록)
	var lo := LaunchFormula.ANGLE_IDEAL - window
	var hi := LaunchFormula.ANGLE_IDEAL + window
	_draw_angle_ray(origin, lo, Color(0.3, 0.9, 0.4, 0.5), 160.0)
	_draw_angle_ray(origin, hi, Color(0.3, 0.9, 0.4, 0.5), 160.0)
	_draw_angle_ray(origin, LaunchFormula.ANGLE_IDEAL, Color(0.3, 0.9, 0.4, 0.8), 175.0)
	# 현재 각도 바늘(빨강)
	_draw_angle_ray(origin, angle, Color(0.95, 0.25, 0.2), 200.0)

func _draw_angle_ray(origin: Vector2, deg: float, color: Color, length: float) -> void:
	var dir := Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg)))
	draw_line(origin, origin + dir * length, color, 4.0)
