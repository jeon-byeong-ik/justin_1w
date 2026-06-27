# 기술 계획 (Plan) — 도마뱀 발사!

> **단계 3: 어떻게(HOW) 구현하는가.** 기술 스택·아키텍처·모듈 구조를 정의한다.
> "무엇/왜"는 [`spec.md`](./spec.md), 게임 내용은 [`game-design.md`](./game-design.md) 참조.

- **제작자:** justin
- **상태:** 초안 (검토 대기)
- **작성일:** 2026-06-27

---

## 1. 기술 스택 (확정: Godot 4)

> **결정 (2026-06-27, justin):** 발사=2단계(연타+각도), 2인=턴제(v1), 엔진=**Godot 4**.

### 1.1 확정안: Godot 4 (GDScript)
| 항목 | 선택 | 이유 |
|------|------|------|
| 엔진 | **Godot 4.3+** | 무료·오픈소스, 2D에 강함, 씬/스크립트가 **텍스트라 Git 친화** |
| 언어 | **GDScript** | 빠른 반복, 엔진 통합, 학습 곡선 완만 |
| 렌더링 | Godot 2D (`Node2D` + `_draw()` / 스프라이트) | 사이드뷰 2D에 충분, 가벼움 |
| 물리 | **자체 계산(포물선)** | 단순 포물선+바운스. `LaunchFormula.gd` 순수 함수로 분리 |
| 입력 | Godot Input (`ui_accept` + 마우스/터치) | 터치·키보드 동시 지원, 2인 키 분리 용이 |
| 저장 | `user://` JSON 세이브 | v1 로컬 세이브로 충분(온라인은 비목표) |
| 렌더러 | GL Compatibility | 모바일·저사양 호환 |

> **대안 검토:** 웹(Canvas+TS)·Phaser도 후보였으나, 정식 게임엔진의 씬/애니메이션/사운드
> 파이프라인과 모바일 내보내기를 고려해 Godot으로 확정. 핵심 로직은 엔진 비의존
> 순수 GDScript로 분리해 테스트·이식성을 유지(원칙 7).

### 1.2 폴더 구조 (Godot 프로젝트)
```
/game                    # Godot 프로젝트 루트
  project.godot          # 프로젝트 설정 (메인 씬·해상도·렌더러)
  icon.svg
  /scenes
    Main.tscn            # 루트 씬 (M0: 발사대+도마뱀+HUD)
  /scripts
    Main.gd              # 게임 루프 & 상태머신 (타이틀→충전→각도→비행→결과)
    LaunchFormula.gd     # 순수 로직: 발사 거리 계산 (launch-formula.md 구현)
    Evolution.gd         # 순수 로직: 진화 단계·능력치 테이블
  /assets                # 오리지널 스프라이트·사운드 (헌장 6, 추후)
/specs                   # 본 SDD 문서들
```
> 향후 모듈 분리: `Session.gd`(1·2인 턴), `Save.gd`, `Shop.gd`, `Effects.gd` 등은
> 마일스톤 진행에 맞춰 추가(tasks.md).

## 2. 아키텍처 핵심

### 2.1 상태 머신 (게임 흐름)
```
TITLE ──▶ MODE_SELECT ──▶ READY
                            │
                            ▼
                    ┌─ POWER_CHARGE ─(시간초과/확정)─▶ ANGLE_AIM
                    │                                     │
                    │                              (확정 입력)
                    │                                     ▼
                    └────────────────────────────── FLIGHT ──▶ RESULT
                                                                 │
                            (다시하기/리매치) ◀────────────────────┤
                            (진화 조건 충족) ──▶ EVOLVE ──▶ RESULT 복귀
```
- 각 상태는 `update(dt)`와 `onInput(action)`만 가진다 → 테스트·디버그 단순.
- **2인 모드**는 `session.ts`가 상태머신을 플레이어별 턴으로 감싼다(턴제 v1).

### 2.2 입력 추상화 (반응성·2인 분리)
- 물리 입력(touchstart/keydown/mousedown) → **추상 액션**(`TAP`, `CONFIRM`)으로 정규화.
- 2인 모드: 입력 소스에 `playerId` 태깅(`A`=P1, `L`=P2 / 화면 좌우 영역=P1/P2).
- 입력 이벤트는 **프레임 큐**에 쌓고 `update`에서 소비 → 지연·유실 최소화(원칙 5).

### 2.3 렌더-로직 분리
- `/core`는 DOM·Canvas를 절대 import하지 않는다(순수). → Vitest로 공식 검증.
- 렌더러는 코어 상태를 "읽어서 그리기만" 한다(단방향 데이터 흐름).

### 2.4 결정성(Determinism)
- 모든 난수는 `rng.ts`의 시드 기반. 일일 도전·리플레이·테스트 재현성 확보.

## 3. 핵심 인터페이스 (계약 요약)
> 상세 수식은 [`contracts/launch-formula.md`](./contracts/launch-formula.md).

```ts
// physics.ts
interface LaunchInput {
  power: number;        // 0..1 (게이지 충전율; 오버차지면 >1 일부 허용)
  angleDeg: number;     // 발사 각도(도)
  sweetness: number;    // 0..1 스위트스팟 정확도 (1=퍼펙트)
  stats: EvoStats;      // 진화 단계 능력치 (P_mul, drag, boost_eff, weight, sweet_w)
  wind: number;         // m/s (+뒷바람 / -맞바람)
  boosters: Booster[];  // 장착 부스터
}
interface LaunchResult {
  distanceM: number;    // 최종 비거리
  perfect: boolean;     // 퍼펙트 여부
  trajectory: Point[];  // 렌더용 궤적 샘플
}
function computeLaunch(i: LaunchInput): LaunchResult;
```

## 4. 마일스톤 매핑 (요약 — 상세는 tasks.md)
1. **M0 프로토타입:** 단일 입력으로 충전→발사→비거리 표시 (US-1).
2. **M1 코어 루프:** 각도/타이밍·결과화면·저장 (US-2, US-4).
3. **M2 진화:** 진화 단계·능력치·연출 (US-3).
4. **M3 2인 대결:** 턴제 대결·리매치 (US-5).
5. **M4 살붙이기:** 상점·스킨·지역·사운드 (US-6,7,8).

## 5. 위험 요소 & 대응
| 위험 | 영향 | 대응 |
|------|------|------|
| 입력 지연으로 손맛 저하 | 핵심 재미 손상 | 입력 큐+프레임 동기, 디바이스 실측 테스트 |
| 밸런싱이 운에 좌우 | 원칙 4 위반 | 랜덤 비중 최소화, 시드 기반 공정성 |
| 2인 입력 충돌 | 대결 모드 불가 | 입력 소스 playerId 분리, 영역/키 격리 |
| IP 침해 | 배포 불가 | 오리지널 자산 원칙(헌장 6) 준수 |
| 모바일 성능 | 프레임 드랍 | Canvas 최소 드로콜, 오브젝트 풀링 |

## 6. 미해결 질문 (justin 결정 필요)
- [ ] **T1.** 스택: 자체 Canvas+TS(권장) vs Phaser vs Godot/Unity?
- [ ] **T2.** 배포 타깃: 웹만 vs 추후 모바일 네이티브 래핑(Capacitor)?
- [ ] **T3.** 자산 제작: 직접 제작 vs 에셋 구매 vs 생성형 도구(라이선스 확인)?

---

### 다음 단계
스택이 확정되면 → [`tasks.md`](./tasks.md)의 M0부터 프로토타입 구현을 시작한다.
