---
description: Azure 워크로드 장애·이상 동작을 다층 진단합니다. 사용자가 "503 떠요", "왜 느려졌어?", "장애 분석", "App Service 죽었어", "AKS 파드 재시작", "리소스 헬스 확인", "이상 알림 왔어" 등 운영 중 문제 증상을 호소할 때 사용
---

# Azure Incident Investigator

Azure 워크로드의 장애 또는 이상 동작을 **증상 → 가설 → 증거 → 결론 → 조치** 순으로 추적합니다. 추측이 아닌 **로그·메트릭·헬스 데이터**에 근거한 진단을 목표로 합니다.

## 사용 시점
- "갑자기 5xx 떠요"
- "어제부터 응답이 느림"
- "AKS 파드가 CrashLoopBackOff"
- "Functions 콜드 스타트가 너무 김"
- "Storage throttled됨"
- "왜 이 리소스가 Unavailable로 표시돼?"

복잡한 다단계 진단(서비스 간 인과관계 추적, 5 Whys 등)은 `azure-troubleshooter` 에이전트로 자동 위임 권장.

## ⚠️ 안전 원칙

### 읽기 전용
이 스킬은 **조회만** 수행합니다. 진단 중 수정·재시작·스케일 조정이 필요하면:
- 사용자에게 명시적으로 권장 조치 보고
- 실제 변경은 `resource-deploy` 스킬로 위임 (사용자 승인 필요)
- KQL 쿼리는 `read-only` 권한 컨텍스트에서만 실행

### 시크릿 노출 금지
- App Insights/Log Analytics 결과에 connection string, password, token이 섞일 수 있음
- 출력 전에 마스킹: `***REDACTED***`
- 특히 `customDimensions`, `requestBody`, `exception.message` 필드 주의

### 데이터 지연 인지
- Activity Log: 1–5분 지연
- App Insights: 2–5분 지연
- Resource Health: 5–15분 지연
- Cost Management: 24–48시간 지연
- 사용자에게 "현재 시각 기준 X분 이전까지의 데이터" 명시

## 진단 워크플로우

### Phase 0: 증상 구조화

사용자 입력에서 다음을 추출. 누락된 항목은 **반드시 질문**:

```
## 🩺 증상 정리

- **영향받는 리소스**: <ID 또는 이름>
- **타입**: App Service / AKS / Functions / SQL / ...
- **증상**: 5xx 폭주 / 응답 지연 / 비가용 / 메트릭 이상
- **시작 시각**: 2026-04-25 14:32 KST (사용자 보고)
- **영향 범위**: 전체 / 특정 엔드포인트 / 특정 사용자
- **최근 변경 여부**: 배포 / 설정 변경 / 트래픽 급증
```

### Phase 1: 광역 헬스 체크 (서비스 측 이슈 배제)

**목적**: Azure 플랫폼 자체 장애인지, 우리 워크로드 문제인지 먼저 분리.

1. **Service Health** — 해당 리전·서비스의 알려진 incident
   - `mcp__azure__resourcehealth` 또는 `az rest` (Service Health API)
2. **Resource Health** — 대상 리소스의 가용성 상태
   - `mcp__azure__resourcehealth` 활용
   - Available / Unavailable / Degraded / Unknown 중 어느 상태인가

플랫폼 측 incident가 확인되면 → 사용자에게 즉시 보고하고 진단 종료 (워크로드 측 조사 불필요).

### Phase 2: 변경 이력 (Activity Log)

**목적**: "방금 멀쩡했는데 갑자기"라면 99% 변경이 원인.

```bash
# 최근 24시간 Activity Log
az monitor activity-log list \
  --resource-id <RESOURCE_ID> \
  --start-time $(date -u -d '24 hours ago' +%FT%TZ) \
  --query "[?level=='Warning' || level=='Error' || operationName.localizedValue!=null].{time:eventTimestamp, op:operationName.localizedValue, status:status.value, caller:caller}" \
  --output table
```

확인 포인트:
- **Write 작업** (배포, 설정 변경, RBAC 변경)
- **Restart / Scale** 이벤트
- 시작 시각 ± 30분 윈도우 내 작업
- 누가(`caller`) 무엇을 변경했는가

### Phase 3: 진단 신호 수집 (리소스 타입별)

#### App Service / Functions
- `mcp__azure__applens` — Microsoft가 제공하는 자동 진단 (가장 먼저)
- App Insights KQL:
  ```kusto
  // 최근 1시간 5xx
  requests
  | where timestamp > ago(1h)
  | where success == false
  | summarize count() by resultCode, name, bin(timestamp, 5m)
  | render timechart

  // 최근 예외 Top 10
  exceptions
  | where timestamp > ago(1h)
  | summarize count(), any(outerMessage) by problemId, type
  | top 10 by count_

  // P95/P99 응답 시간
  requests
  | where timestamp > ago(1h)
  | summarize p50=percentile(duration, 50),
              p95=percentile(duration, 95),
              p99=percentile(duration, 99)
              by bin(timestamp, 5m), name
  ```
- **메트릭**: `CpuPercentage`, `MemoryPercentage`, `Http5xx`, `AverageResponseTime`

#### AKS
- `mcp__azure__aks` — 클러스터·노드풀 상태
- Container Insights KQL:
  ```kusto
  // 파드 재시작
  KubePodInventory
  | where TimeGenerated > ago(1h)
  | where ContainerRestartCount > 0
  | summarize MaxRestarts=max(ContainerRestartCount) by Name, Namespace
  | order by MaxRestarts desc

  // 노드 NotReady
  KubeNodeInventory
  | where TimeGenerated > ago(1h)
  | where Status != "Ready"
  | distinct Computer, Status
  ```
- 이벤트: `kubectl get events --sort-by='.lastTimestamp' -A | tail -50` (Bash로)
- **체크 항목**: 노드 풀 quota, PVC 바인딩, ImagePull 실패, OOMKilled

#### SQL Database
- `mcp__azure__sql` — DTU/vCore 사용률, 차단 쿼리
- 메트릭: `dtu_consumption_percent`, `connection_failed`, `deadlock`
- Query Store에서 회귀 쿼리 식별

#### Storage
- `mcp__azure__storage` 메트릭: `Transactions`, `Availability`, `SuccessE2ELatency`
- 429 (Throttling) 응답 비율 확인 → 파티션 핫스팟 의심

#### Cosmos DB
- `mcp__azure__cosmos` — RU 소비, 파티션 키 분포
- 메트릭: `TotalRequestUnits`, `ProvisionedThroughput`, `ServerSideLatency`
- 429 비율 → RU 부족 / 핫 파티션

### Phase 4: Azure Advisor 권장사항

`mcp__azure__advisor`로 해당 리소스의 기존 권장사항 조회 — 종종 장애의 *근본 원인이 이미 권고되어 있는* 경우가 많음 (예: "이 SQL DB는 vCore 부족 권고 받음").

### Phase 5: 가설 정리 및 결론

다음 형식으로 보고:

```
## 🔬 진단 결과

**조사 대상**: <리소스 ID>
**증상**: <한 줄 요약>
**진단 시각**: 2026-04-25 14:55 KST

### 📈 핵심 발견

1. **변경 이벤트**: 14:28에 App Service 'app-prod-001'에 배포 (caller: ci-bot@org.com)
2. **에러 신호**: 14:30부터 `Microsoft.Data.SqlClient.SqlException` 폭증 (분당 200+)
3. **헬스 상태**: Resource Health는 Available — Azure 플랫폼 측 이슈 아님
4. **Advisor**: SQL DB가 DTU 95% 권고 받은 상태 (3일 전부터)

### 🎯 가설 (가능성 순)

| # | 가설 | 근거 | 가능성 |
|---|------|------|-------|
| 1 | 신규 배포의 N+1 쿼리 회귀 | 14:28 배포 직후 SQL 예외 폭증 | 🔴 높음 |
| 2 | SQL DB DTU 한계 | Advisor 권고 + 동시 영향 | 🟡 중간 |
| 3 | Connection Pool 고갈 | 가능 — 추가 KQL 필요 | 🟢 낮음 |

### 🛠️ 권장 조치

**즉시 완화 (5분)**
- 14:28 배포 롤백 또는 Slot Swap 되돌리기
- 명령 예시: `az webapp deployment slot swap -g <rg> -n <app> --slot staging --target-slot production`
- ⚠️ 변경 작업은 `resource-deploy` 스킬로 위임하세요 (사용자 승인 필요)

**근본 원인 (24시간)**
- App Insights에서 `dependencies | where target contains 'sql'` 으로 N+1 확인
- 회귀 PR 식별 → 핫픽스
- SQL DB는 별도 vCore 증설 검토 (cost-analyzer 스킬로 비용 영향 산출)

**재발 방지**
- App Insights Smart Detection 알림 활성화
- Action Group으로 Slack/Teams 연동
- Pre-deployment health gate 도입
```

## KQL 작성 안전 규칙

- `| limit 1000` 또는 `| top N` 항상 명시 — 쿼리 폭주 방지
- 시간 범위 **반드시** 지정: `| where timestamp > ago(...)` — Log Analytics 비용 보호
- `customDimensions`/`message` 필드는 출력 전 마스킹 검토
- 작성한 KQL은 **사용자에게 보여주고 실행** — 블랙박스 금지

## 참고: 자주 쓰는 KQL Snippet

```kusto
// 1. 최근 30분 가장 느린 요청 Top 20
requests
| where timestamp > ago(30m)
| top 20 by duration desc
| project timestamp, name, duration, resultCode, operation_Id

// 2. 의존성 실패율
dependencies
| where timestamp > ago(1h)
| summarize total=count(), failed=countif(success == false) by target, type
| extend failureRate = round(100.0 * failed / total, 2)
| where failureRate > 1
| order by failureRate desc

// 3. 사용자 영향 범위
requests
| where timestamp > ago(1h) and success == false
| summarize affectedUsers=dcount(user_Id), failedRequests=count() by bin(timestamp, 5m)
| render timechart
```

## 다른 컴포넌트로 위임

- 변경/롤백 실행 → `resource-deploy` 스킬
- 비용 영향 산출 → `cost-analyzer` 스킬
- 정책 위반 발견 → `governance-check` 스킬
- 복잡한 다단계 진단 → `azure-troubleshooter` 에이전트
