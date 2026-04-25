Azure 워크로드 장애·이상 동작에 대한 빠른 1차 진단을 시작합니다.

사용자가 제공한 인자(`$ARGUMENTS`)를 영향받는 리소스 ID·이름·증상으로 해석하세요. 인자가 없으면 사용자에게 다음 항목을 먼저 물어보세요:
- 영향받는 리소스 (ID 또는 이름)
- 증상 시작 시각
- 증상 요약 (5xx, 지연, 비가용 등)

## 1차 진단 (5분 안에)

다음을 **병렬로** 수집한 뒤 한국어로 요약하세요. 깊은 분석은 `incident-investigator` 스킬 또는 `azure-troubleshooter` 에이전트로 위임하세요.

### A. Service Health (광역 장애 배제)
```bash
az rest --method get \
  --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.ResourceHealth/events?api-version=2022-10-01&\$filter=Properties/EventType eq 'ServiceIssue' and Properties/Status eq 'Active'" \
  --query "value[].{title:properties.title, status:properties.status, region:properties.impact[0].impactedRegions[0].impactedRegion, services:properties.impact[0].impactedService}" \
  --output table 2>/dev/null
```

### B. Resource Health (대상 리소스 가용성)
- 가능하면 `mcp__azure__resourcehealth` 도구를 우선 사용
- 폴백: `az rest` 로 `/providers/Microsoft.ResourceHealth/availabilityStatuses`

### C. Activity Log (최근 24h, 변경 이력)
```bash
az monitor activity-log list \
  --resource-id <RESOURCE_ID> \
  --start-time $(date -u -d '24 hours ago' +%FT%TZ 2>/dev/null || date -u -v-24H +%FT%TZ) \
  --query "[?level=='Warning' || level=='Error' || (operationName.localizedValue!=null && status.value=='Succeeded' && contains(operationName.localizedValue, 'Write'))].{time:eventTimestamp, op:operationName.localizedValue, status:status.value, caller:caller}" \
  --output table
```

### D. 리소스 메트릭 (최근 1h, 핵심 지표만)
```bash
az monitor metrics list \
  --resource <RESOURCE_ID> \
  --start-time $(date -u -d '1 hour ago' +%FT%TZ 2>/dev/null || date -u -v-1H +%FT%TZ) \
  --interval PT5M \
  --output table
```

리소스 타입에 따라 핵심 메트릭 자동 선택:
- App Service / Functions: `Http5xx`, `AverageResponseTime`, `CpuPercentage`
- AKS: `node_cpu_usage_percentage`, `kube_pod_status_ready`
- SQL DB: `dtu_consumption_percent`, `connection_failed`
- Storage: `Availability`, `SuccessE2ELatency`, `Transactions`
- Cosmos DB: `TotalRequestUnits`, `ServerSideLatency`

## 결과 보고 형식

```
## 🚨 1차 진단

**리소스**: <ID>
**증상**: <요약>
**조사 시각**: <KST>

### 광역 헬스
- Service Health: ✅ 정상 / ⚠️ 진행 중 incident: <제목>
- Resource Health: Available / Unavailable / Degraded

### 변경 이력 (24h)
| 시각 | 작업 | 상태 | 호출자 |
|---|---|---|---|
| ... | ... | ... | ... |

### 핵심 메트릭 이상
- <메트릭>: <값> (평소: <기준>) — 🔴 비정상 / 🟢 정상

### 1차 결론
- **가장 가능성 높은 원인**: <한 줄>
- **추가 조사 필요**: <항목>

### 다음 단계
- 깊은 분석: `incident-investigator` 스킬 호출 (또는 "더 파봐줘" 요청)
- 다단계 RCA: `azure-troubleshooter` 에이전트 위임
- 변경/롤백 실행: `resource-deploy` 스킬 (사용자 승인 필수)
```

## 안전 원칙
- 이 명령은 **읽기 전용** — 어떤 리소스도 수정 금지
- 시크릿/connection string 출력 시 `***REDACTED***` 마스킹
- Activity Log/메트릭 데이터 지연(1–15분) 사용자에게 명시
