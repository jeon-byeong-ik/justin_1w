# LaunchFormula.gd — 발사 거리 계산 (순수 로직)
#
# specs/001-lizard-launch/contracts/launch-formula.md 의 구현체.
# 엔진/렌더링에 의존하지 않는 순수 함수만 둔다(원칙 7). 수치는 초기 제안값.
class_name LaunchFormula
extends RefCounted

const BASE_VELOCITY := 28.0   # 100% 파워의 기본 발사 속도(m/s)
const GRAVITY := 9.8          # 중력 가속도
const OVERCHARGE_GAIN := 0.10 # 오버차지(1.0~1.1) 보너스 비율
const OVERCHARGE_PEN := 0.30  # 과충전(>1.1) 페널티 비율
const PERFECT_MULT := 1.50    # 퍼펙트(sweet=1.0) 비거리 배수
const ANGLE_IDEAL := 45.0     # 이상적 발사 각도(도)
const BOUNCE_BASE := 0.20     # 착지 바운스 기본 비율

# 오버차지 처리 (contracts §3.1)
static func eff_power(power: float) -> float:
	if power <= 1.0:
		return power
	elif power <= 1.1:
		return 1.0 + (power - 1.0) * (1.0 + OVERCHARGE_GAIN)
	else:
		return 1.0 - OVERCHARGE_PEN

# stats: { p_mul, drag, boost_eff, weight, sweet_w } (Evolution.gd 제공)
# 반환: { distance: float(m), perfect: bool }
static func compute(power: float, angle_deg: float, sweet: float,
		stats: Dictionary, wind := 0.0, boost_total := 0.0) -> Dictionary:
	var ep := eff_power(power)
	var v0 := BASE_VELOCITY * ep * float(stats.p_mul)                       # §3.2
	var angle_factor := cos(deg_to_rad(abs(ANGLE_IDEAL - angle_deg)))       # §3.3
	var sweet_mult := 1.0 + (PERFECT_MULT - 1.0) * sweet                    # §3.4
	var range_vacuum := (v0 * v0) * sin(2.0 * deg_to_rad(angle_deg)) / GRAVITY  # §3.5
	var range_air := range_vacuum / float(stats.drag)
	var range_wind := range_air + wind * 1.5
	var range_boost := range_wind + boost_total * float(stats.boost_eff)    # §3.6
	var range_skill := range_boost * sweet_mult * angle_factor             # §3.7
	var bounce := range_skill * BOUNCE_BASE / float(stats.weight)          # §3.8
	var distance: float = max(0.0, range_skill + bounce)
	return { "distance": distance, "perfect": sweet >= 0.95 }

# 에너지(재화) 획득 (contracts §5)
static func energy_gain(distance_m: float, perfect: bool) -> int:
	var combo := 1.5 if perfect else 1.0
	return int(floor(distance_m / 2.0) * combo)
