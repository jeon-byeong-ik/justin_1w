# 기술 계획 (Plan) — 도마뱀 발사!

> **단계 3: 어떻게(HOW) 구현하는가.** 기술 스택·아키텍처·모듈 구조를 정의한다.
> "무엇/왜"는 [`spec.md`](./spec.md), 게임 내용은 [`game-design.md`](./game-design.md) 참조.

- **제작자:** justin
- **상태:** 초안 (검토 대기)
- **작성일:** 2026-06-27

---

## 1. 기술 스택 (제안)

### 1.1 권장안: 웹 기반 (HTML5 Canvas)
| 항목 | 선택 | 이유 |
|------|------|------|
| 런타임 | **웹 브라우저** | 설치 불필요, 터치·키보드 동시 지원, 2인 같은 화면 쉬움 |
| 언어 | **TypeScript** | 타입 안정성, 협업·리팩터 용이 |
| 렌더링 | **HTML5 Canvas 2D** (또는 경량 엔진 PixiJS) | 2D 사이드뷰에 충분, 가벼움 |
| 물리 | **자체 구현(포물선)** | 단순 포물선+바운스라 엔진 불필요. 반응성·예측성↑ |
| 빌드 | **Vite** | 빠른 개발 서버, 간단한 번들링 |
| 저장 | **localStorage** | v1 로컬 세이브로 충분(온라인은 비목표) |
| 테스트 | **Vitest** | 공식 공식 로직(순수 함수) 단위 테스트 |

> **대안:** 풀 게임엔진(Phaser, Godot, Unity)도 가능하나, 본 게임은 로직이 단순하고
> 반응성이 핵심이라 **경량 자체 구현**이 원칙 5(입력 지연 0)에 가장 유리. 최종 스택은
> justin 확정 필요(미해결 질문 참고).

### 1.2 폴더 구조 (제안)
```
/src
  /core            # 순수 로직 (렌더링·DOM 무관, 테스트 가능)
    physics.ts     # 발사·비행·바운스 계산 (launch-formula.md 구현)
    gauge.ts       # 파워 충전/감소, 각도 바늘 상태머신
    evolution.ts   # 진화 단계·능력치 테이블
    economy.ts     # 에너지 획득·상점 가격
    rng.ts         # 시드 기반 난수 (일일 도전 등 재현성)
  /game            # 게임 상태 & 루프
    stateMachine.ts# 타이틀→충전→각도→비행→결과 상태 전이
    session.ts     # 1인/2인 세션, 턴 관리
    save.ts        # localStorage 직렬화
  /render          # 그리기 (Canvas)
    renderer.ts    # 스프라이트·HUD·배경 패럴랙스
    effects.ts     # 발사/진화/퍼펙트 연출
  /input           # 입력 추상화
    input.ts       # 터치/마우스/키보드 → 추상 액션(연타/확정)
  /ui              # 메뉴·상점·설정 화면
  /assets          # 오리지널 스프라이트·사운드 (헌장 6)
  main.ts          # 부트스트랩
/specs             # 본 SDD 문서들
/tests             # 단위 테스트
index.html
```

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
