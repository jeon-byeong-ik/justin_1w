# 🦎 도마뱀 발사! (Lizard Launch)

> 게이지를 시간 안에 채워 도마뱀을 멀리 날리는 액션 게임
> **제작자: justin**

게이지 타이밍 게임 + 진화(도마뱀 → 모토마 → 미라이돈) + 1인/2인 플레이를 결합한
캐주얼 아케이드 게임입니다. 본 저장소는 **SDD(Spec-Driven Development, 명세 주도 개발)**
방식으로, 코드를 작성하기 전에 "무엇을, 왜, 어떻게" 만들 것인지 문서로 먼저 합의합니다.

---

## 📚 문서 읽는 순서 (SDD 흐름)

SDD는 아래 순서로 "명세 → 계획 → 작업 → 구현"을 단계적으로 진행합니다.
각 단계는 앞 단계가 합의되어야 다음으로 넘어갑니다.

| 단계 | 문서 | 내용 | 상태 |
|------|------|------|------|
| 0. 원칙 | [`.specify/memory/constitution.md`](.specify/memory/constitution.md) | 프로젝트가 절대 어기지 않을 핵심 원칙 | ✅ 초안 |
| 1. 명세 | [`specs/001-lizard-launch/spec.md`](specs/001-lizard-launch/spec.md) | 사용자 관점의 요구사항(WHAT/WHY) | ✅ 초안 |
| 2. 게임 설계 | [`specs/001-lizard-launch/game-design.md`](specs/001-lizard-launch/game-design.md) | 세계관·캐릭터·시나리오·시스템 상세(GDD) | ✅ 초안 |
| 3. 기술 계획 | [`specs/001-lizard-launch/plan.md`](specs/001-lizard-launch/plan.md) | 아키텍처·기술 스택·구현 방식(HOW) | ✅ 초안 |
| 4. 작업 분해 | [`specs/001-lizard-launch/tasks.md`](specs/001-lizard-launch/tasks.md) | 마일스톤·작업 목록·우선순위 | ✅ 초안 |
| 부록 | [`specs/001-lizard-launch/contracts/launch-formula.md`](specs/001-lizard-launch/contracts/launch-formula.md) | 발사 거리 계산식 등 핵심 공식 명세 | ✅ 초안 |

---

## 🎮 한 줄 요약

1. **파워 게이지**를 제한 시간 안에 연타로 채우고
2. **각도/타이밍**을 정확히 맞춰 발사하면
3. **비거리**에 따라 보상을 얻고 도마뱀이 **진화**합니다.
4. 혼자서는 스토리/챌린지를, 둘이서는 누가 더 멀리 날리는지 **대결**합니다.

---

## ⚖️ 지식재산권(IP) 주의

"모토마", "미라이돈" 등은 기존 IP(포켓몬스터, 닌텐도/게임프리크)를 연상시킵니다.
**상업적 배포 시 저작권 문제가 발생할 수 있으므로**, 본 프로젝트는 해당 콘셉트를
**오마주한 오리지널 디자인**(이름·외형·기술명 자체 제작)으로 구현하는 것을 기본 방침으로 합니다.
자세한 내용은 [`constitution.md`](.specify/memory/constitution.md)의 *원칙 6* 참고.

---

## 🗺️ 다음 단계

문서 검토 후 합의되면 → 기술 계획(`plan.md`)에 따라 프로토타입 구현을 시작합니다.
변경/이견이 있으면 해당 문서에 코멘트로 남겨 주세요.
