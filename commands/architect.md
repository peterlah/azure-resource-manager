Azure 신규 워크로드의 아키텍처를 인터뷰 기반으로 설계하고, 의사결정용 다이어그램(Mermaid 인라인 + D2 산출물)·ADR·Terraform IaC까지 한 흐름으로 생성합니다.

사용자가 제공한 인자(`$ARGUMENTS`)를 1차 요구사항으로 해석. 인자가 없으면 빈 상태로 인터뷰 시작.

## 실행 절차

### 1단계: 인터뷰 (architecture-interview 스킬 호출)
`architecture-interview` 스킬의 3-Phase 워크플로우를 그대로 진행:
- Phase 1: 트리아지 5–7개 질문 (워크로드/규모/위치/스택/컴플라이언스/예산)
- Phase 2: 후보 아키텍처 1–3개 선정 후 심화 질문 (가용성/데이터/통합/보안/운영)
- Phase 3: 산출물 (각 뷰마다 두 가지 동시 생성):
  - **Mermaid** — 채팅 인라인 미리보기 (즉시 검토)
  - **Drawpyo Python** — `./diagrams/<adr-id>-<view>.py` (의사결정용 MS Learn 스타일 산출물)
  - **D2 폴백** — `./diagrams/<adr-id>-<view>.d2` (Python 미설치 시)
  - **ADR** — `./diagrams/<adr-id>.md`
  - 비용 추정

각 Phase 끝마다 사용자 확인. 수정 요청 받으면 ADR/다이어그램 갱신 후 재출력.

산출물 작성 끝나면:
1. **스킬이 직접** 각 뷰 `.py` 를 `python3` 으로 실행 → `.drawio` 파일까지 자동 생성
2. drawpyo 미설치면 사용자에게 `pip3 install drawpyo` 안내 후 자동 실행은 중단 (설치 후 다시 트리거)
3. 사용자에게 보고할 것:
```bash
# 1회만 (안 깔려있다면)
pip3 install drawpyo

# .drawio 열기 — 셋 중 하나
#  (a) https://app.diagrams.net/ 에서 File > Open from > Device
#  (b) drawio Desktop
#  (c) VS Code 확장 "Draw.io Integration" by Henning Dieterichs
```

### 2단계: 사용자가 ADR 확정한 뒤 다음 옵션 제시

```
ADR이 확정되었습니다. 다음 중 어떤 것을 진행할까요?

1) **Terraform 코드 생성** — terraform-generator 스킬로 IaC 산출
2) **Bicep 코드 생성** — bicep-generator 스킬로 IaC 산출
3) **비용 약정 시뮬레이션** — cost-analyzer 스킬에서 RI/Savings Plan 적용 시 절감액
4) **거버넌스 사전 검증** — governance-check 스킬로 네이밍·태그 컨벤션 점검
5) **단계별 마이그레이션 계획** — azure-architect 에이전트에 위임
6) **종료** — 산출물만 받고 끝
```

### 3단계: 선택에 따라 위임
- 1) → `terraform-generator` 스킬, ADR 경로를 입력으로 전달
- 2) → `bicep-generator` 스킬
- 3) → `cost-analyzer` 스킬, ADR의 컴포넌트 표 전달
- 4) → `governance-check` 스킬
- 5) → `azure-architect` 에이전트

## 안전 원칙
- 이 명령은 **읽기 전용** 인터뷰 + 파일 생성만. Azure 리소스 실제 배포는 절대 X
- D2 파일 저장 시 `./diagrams/` 디렉토리 없으면 사용자에게 생성 동의 받기
- 생성된 ADR·`.d2`·Terraform 파일 경로를 **사용자에게 명시적으로 보고**
- 사용자가 답하지 않은 항목을 추측으로 채우지 말 것 (기본값 사용 시에도 표시)

## 빠른 시작 예시

```
/azure-resource-manager:architect B2C 주문 플랫폼, 한국+일본, 10만 MAU, Spring Boot
```

→ Phase 1을 위 정보 기반으로 시작, 누락된 항목(컴플라이언스/예산/RTO 등)만 질문.

```
/azure-resource-manager:architect
```

→ 빈 상태, Phase 1의 모든 질문부터 시작.
