# Evolution.gd — 진화 단계·능력치 테이블 (순수 로직)
#
# specs/001-lizard-launch/game-design.md §3 의 구현체.
# 진화 기준: 누적 성운 에너지(원칙 4). 수치는 초기 제안값.
class_name Evolution
extends RefCounted

# 인덱스 = 진화 단계(0:리지, 1:모토마, 2:미라이돈)
const STAGES := [
	{
		"name": "리지", "form": "도마뱀", "threshold": 0,
		"p_mul": 1.00, "drag": 1.00, "boost_eff": 1.00, "weight": 1.00, "sweet_w": 1.00,
		"color": Color(0.45, 0.78, 0.36),  # 초록
	},
	{
		"name": "모토마", "form": "청년기", "threshold": 1000,
		"p_mul": 1.25, "drag": 0.90, "boost_eff": 1.10, "weight": 1.15, "sweet_w": 1.10,
		"color": Color(0.30, 0.70, 0.95),  # 청록 발광
	},
	{
		"name": "미라이돈", "form": "각성체", "threshold": 6000,
		"p_mul": 1.60, "drag": 0.75, "boost_eff": 1.30, "weight": 1.30, "sweet_w": 1.20,
		"color": Color(0.85, 0.35, 0.95),  # 네온 보라
	},
]

# 누적 에너지로 현재 진화 단계 인덱스 계산
static func stage_for_energy(total_energy: int) -> int:
	var s := 0
	for i in range(STAGES.size()):
		if total_energy >= int(STAGES[i].threshold):
			s = i
	return s

static func stats(stage_index: int) -> Dictionary:
	return STAGES[clamp(stage_index, 0, STAGES.size() - 1)]

# 다음 단계까지 남은 에너지 (마지막 단계면 0)
static func energy_to_next(total_energy: int) -> int:
	var s := stage_for_energy(total_energy)
	if s >= STAGES.size() - 1:
		return 0
	return int(STAGES[s + 1].threshold) - total_energy
