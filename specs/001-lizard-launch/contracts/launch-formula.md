# 계약 명세 — 발사 거리 공식 (Launch Formula)

> 핵심 재미를 좌우하는 **비거리 계산식**의 단일 진실 공급원(Single Source of Truth).
> `core/physics.ts`는 이 문서를 구현하고, 단위 테스트는 이 표를 검증한다.
> 모든 수치는 **초기 제안값**이며 밸런싱 단계에서 조정한다.

- **제작자:** justin
- **작성일:** 2026-06-27

---

## 1. 입력 변수

| 기호 | 이름 | 범위 | 출처 |
|------|------|------|------|
| `power` | 파워 충전율 | 0.0 ~ 1.2 | 파워 게이지(1.0 초과는 오버차지) |
| `angle` | 발사 각도(도) | 0 ~ 90 | 각도 게이지 |
| `sweet` | 스위트스팟 정확도 | 0.0 ~ 1.0 | 각도 확정 시점 정확도(1=퍼펙트) |
| `P_mul` | 진화 파워 배수 | 1.0 ~ 1.6 | 진화 단계(GDD 3.3) |
| `drag` | 공기저항 계수 | 0.75 ~ 1.0 | 진화 단계 |
| `boost_eff` | 부스터 효율 | 1.0 ~ 1.3 | 진화 단계 |
| `weight` | 무게(바운스 역계수) | 1.0 ~ 1.3 | 진화 단계 |
| `wind` | 바람(m/s) | -8 ~ +8 | 지역(맞/뒷바람) |
| `boost` | 부스터 합 | 0 ~ N | 장착 아이템 |

## 2. 상수 (초기 제안)
```
BASE_VELOCITY   = 28      # 100% 파워의 기본 발사 속도(m/s)
GRAVITY         = 9.8     # 중력 가속도(m/s^2)
OVERCHARGE_GAIN = 0.10    # 오버차지(1.0~1.1) 보너스 비율
OVERCHARGE_PEN  = 0.30    # 과충전(>1.1) 페널티 비율
PERFECT_MULT    = 1.50    # 퍼펙트(sweet=1.0) 비거리 배수
ANGLE_IDEAL     = 45      # 이상적 발사 각도(도)
BOUNCE_BASE     = 0.20    # 착지 바운스 기본 비율
```

## 3. 계산 절차

### 3.1 유효 파워 보정 (오버차지 처리)
```
if power <= 1.0:        eff_power = power
elif power <= 1.1:      eff_power = 1.0 + (power - 1.0) * (1 + OVERCHARGE_GAIN)
else:                   eff_power = 1.0 - OVERCHARGE_PEN     # 과충전 페널티
```

### 3.2 발사 속도
```
v0 = BASE_VELOCITY * eff_power * P_mul
```

### 3.3 각도 효율 (45°에서 최대, 멀어질수록 감소)
```
angle_factor = cos(radians(abs(ANGLE_IDEAL - angle)))   # 45°→1.0, 0°/90°→약 0.707
```

### 3.4 스위트스팟 배수
```
sweet_mult = 1.0 + (PERFECT_MULT - 1.0) * sweet          # sweet=1 → 1.5배
```

### 3.5 이상적 포물선 비거리 (공기저항·바람 반영)
```
# 기본 사거리(진공 포물선): R = v0^2 * sin(2*angle) / g
range_vacuum = (v0^2) * sin(2 * radians(angle)) / GRAVITY
range_air    = range_vacuum / drag                       # drag<1이면 더 멀리
range_wind   = range_air + wind * 1.5                     # 바람 보정(선형 근사)
```

### 3.6 부스터 적용
```
range_boost = range_wind + (boost_total * boost_eff)
```

### 3.7 스위트스팟·각도 효율 결합
```
range_skill = range_boost * sweet_mult * angle_factor
```

### 3.8 착지 바운스 (무게 반비례)
```
bounce = range_skill * BOUNCE_BASE / weight
distance_m = max(0, range_skill + bounce)
```

### 3.9 퍼펙트 판정
```
perfect = (sweet >= 0.95)
```

## 4. 검증용 예시 (단위 테스트 기준값)
> 아래는 공식의 **상대적 경향**을 검증하기 위한 시나리오. 정확한 절대값은
> 상수 확정 후 테스트에 고정한다. 핵심은 **순서(부등호)가 유지되는가**이다.

| 시나리오 | power | angle | sweet | 단계 | 기대 경향 |
|----------|-------|-------|-------|------|-----------|
| A. 초보 평범 | 0.6 | 30 | 0.3 | 리지 | 기준(낮음) |
| B. 좋은 발사 | 0.9 | 45 | 0.8 | 리지 | A보다 확실히 멀리 |
| C. 퍼펙트 | 1.0 | 45 | 1.0 | 리지 | B보다 멀리(퍼펙트 배수) |
| D. 퍼펙트+진화 | 1.0 | 45 | 1.0 | 미라이돈 | C보다 멀리(P_mul·drag) |
| E. 과충전 실패 | 1.2 | 45 | 1.0 | 리지 | C보다 짧음(페널티) |
| F. 맞바람 | 1.0 | 45 | 1.0 | 리지 | C보다 짧음(wind<0) |

**불변식(테스트로 보장):**
- `dist(B) > dist(A)` — 실력이 비거리에 반영된다.
- `dist(C) > dist(B)` — 퍼펙트는 보상된다.
- `dist(D) > dist(C)` — 진화는 확실한 상향이다(원칙 4).
- `dist(E) < dist(C)` — 과충전은 손해다(고위험).
- `dist(F) < dist(C)` — 맞바람은 불리하다.
- 모든 입력에서 `distance_m >= 0`.

## 5. 에너지(재화) 획득
```
combo_bonus = perfect ? 1.5 : 1.0
energy = floor(distance_m / 2) * combo_bonus
```

---

### 비고
- 본 공식은 "진공 포물선 근사 + 보정항" 방식으로, 정확한 물리보다 **예측 가능한 손맛**과
  **밸런싱 용이성**을 우선한다(원칙 5). 실측 후 BASE_VELOCITY/GRAVITY를 게임플레이에
  맞게 조정한다(현실 물리값일 필요 없음).
