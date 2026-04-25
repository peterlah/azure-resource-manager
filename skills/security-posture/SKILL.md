---
description: Azure 구독·리소스의 보안 자세(security posture)를 점검합니다. Defender for Cloud Secure Score, 공개 노출 리소스, NSG 위험 규칙, Key Vault 시크릿 만료, RBAC 과잉 권한, MFA·암호화 누락 등을 종합 진단합니다. 사용자가 "보안 점검", "취약점 스캔", "Defender 점수", "공개 노출", "NSG 검사", "RBAC 감사", "azqr" 등을 언급할 때 사용
---

# Azure Security Posture

Azure 환경의 **보안 자세를 정량 점검**하고, 위험도별로 우선순위화된 조치 계획을 제시합니다. Microsoft Defender for Cloud · Azure Policy · Azure Quick Review(azqr) · Azure Resource Graph를 교차 사용합니다.

## 사용 시점
- "우리 구독 보안 점수 알려줘"
- "공개 노출된 리소스 있어?"
- "NSG 0.0.0.0/0 SSH/RDP 열린 거 찾아"
- "Key Vault 만료 임박 시크릿"
- "Owner 권한 누가 들고 있어?"
- "Storage account 중에 public access 켜진 거"
- 분기별 보안 감사 / 컴플라이언스 보고서 준비

복잡한 다영역 감사(예: ISO 27001 매핑, 60일 진행형 감사)는 `azure-security-auditor` 에이전트로 위임 권장.

## ⚠️ 안전 원칙

### 읽기 전용
- 이 스킬은 **점검만** 수행 — 권한 회수, 정책 적용, 리소스 변경 일체 금지
- 발견된 위험에 대한 조치는 사용자에게 **권장**하고, 실행은 `resource-deploy` / `policy-author` / Bash로 사용자가 직접

### 발견 결과 취급 주의
- 보고서에 **시크릿 값**(connection string, key, token)이 절대 들어가지 않도록
- Key Vault 항목은 **이름·만료일·태그만** — value 절대 출력 금지
- Storage account key, SAS token은 마스킹: `***REDACTED***`

### 거짓 양성 가능성 인지
- "공개 노출"은 NSG/Firewall/Private Endpoint 조합에 따라 실제로는 안전할 수 있음
- "Owner 권한"은 PIM(Privileged Identity Management) just-in-time일 수 있음
- 결론을 단정하지 말고 "추가 검증 필요"를 명시

## 점검 도메인

### 1. Defender for Cloud Secure Score
- 구독·MG 단위 점수 조회
- 미준수 권장사항 카테고리별 집계
- 핵심 도구: `mcp__azure__monitor`, `az security` CLI

```bash
# Secure Score
az security secure-scores list --query "[].{name:name, percentage:properties.score.percentage, current:properties.score.current, max:properties.score.max}" -o table

# 미준수 권장사항 Top 20 (severity 기준)
az security assessment list --query "[?properties.status.code=='Unhealthy'].{name:displayName, severity:metadata.severity, resource:resourceDetails.id}" -o json | head -100
```

### 2. 공개 노출 (Public Exposure)
**가장 우선순위 높은 점검**. 인터넷에서 직접 접근 가능한 리소스 식별:

- Storage Account: `allowBlobPublicAccess`, `publicNetworkAccess`, 익명 컨테이너
- SQL Server: `publicNetworkAccess`, firewall rule 0.0.0.0–255.255.255.255
- Cosmos DB / Redis / Service Bus / Event Hubs: `publicNetworkAccess`
- Key Vault: `publicNetworkAccess`, network ACL `defaultAction`
- App Service / Functions: 인바운드 IP 제한 부재
- NSG: 0.0.0.0/0 → SSH(22) / RDP(3389) / WinRM(5985-5986) / DB 포트
- Public IP: 연결된 NIC가 위험한 NSG와 묶여있는지

**Resource Graph 단일 쿼리 (구독 전체 스캔)**:
```kusto
resources
| where type =~ 'microsoft.network/networksecuritygroups'
| mv-expand rule = properties.securityRules
| where rule.properties.access == 'Allow'
| where rule.properties.direction == 'Inbound'
| where rule.properties.sourceAddressPrefix in ('*', '0.0.0.0/0', 'Internet')
| extend port = tostring(rule.properties.destinationPortRange)
| where port in ('22','3389','*','5985','5986','1433','3306','5432','27017','6379')
| project nsg=name, rg=resourceGroup, ruleName=rule.name, port, src=rule.properties.sourceAddressPrefix
```

```kusto
resources
| where type =~ 'microsoft.storage/storageaccounts'
| where properties.allowBlobPublicAccess == true
   or properties.publicNetworkAccess == 'Enabled'
| project name, rg=resourceGroup,
          publicAccess=properties.allowBlobPublicAccess,
          networkAccess=properties.publicNetworkAccess,
          minTls=properties.minimumTlsVersion
```

### 3. RBAC 감사
- **Owner / Contributor 보유자 목록** (구독·리소스 그룹 단위)
- Service Principal에 부여된 광범위 권한
- 분리되지 않은 사람/서비스 계정 (예: 한 SP가 prod + dev 둘 다)
- 비활성 계정에 남은 권한 (Entra ID 로그인 90일 이상 없음)

```bash
# 구독 Owner
az role assignment list --role "Owner" --scope "/subscriptions/$(az account show --query id -o tsv)" \
  --query "[].{principalName:principalName, type:principalType, scope:scope}" -o table

# 모든 사용자 정의 역할 (custom role) 점검
az role definition list --custom-role-only true --query "[].{name:roleName, perms:permissions[0].actions}" -o json
```

**위험 신호**:
- `*` (모든 작업) 권한을 가진 custom role
- Subscription 단위 Owner를 가진 Service Principal
- 탈퇴/이직 가능성 있는 외부 도메인 사용자

### 4. Key Vault 위생
- Soft Delete + Purge Protection 미활성 vault
- 만료 임박(30일) / 만료된 시크릿·키·인증서
- Vault에 public network access 허용
- Diagnostic Logs 미설정 (감사 추적 불가)

```bash
# 모든 Key Vault 점검
for vault in $(az keyvault list --query "[].name" -o tsv); do
  az keyvault show -n "$vault" --query "{name:name, softDelete:properties.enableSoftDelete, purgeProtection:properties.enablePurgeProtection, publicAccess:properties.publicNetworkAccess}" -o json
done
```

### 5. 데이터 보호
- Storage / SQL / Cosmos: 암호화 키(MMK vs CMK) 정책
- TLS 최소 버전 (Storage `minimumTlsVersion`, SQL `minimalTlsVersion`)
- Backup 미구성 리소스 (특히 SQL DB, VM, App Service)
- Diagnostic Settings이 Log Analytics·Storage로 흘러가는가

### 6. ID/Identity
- Managed Identity 미사용 → 키/시크릿 인증 사용 중인 워크로드
- App Service 설정에 평문 connection string (App Settings에 `AccountKey=`, `Password=` 노출)
- Service Principal secret 만료 임박

### 7. Azure Quick Review (azqr)
오픈소스 통합 스캐너. 위 항목들을 한 번에 정리.

```bash
# 설치 확인 (없으면 안내만 — 자동 설치 금지, 사용자 명시 승인 필요)
which azqr || echo "miss"

# 구독 스캔 (현재 활성 구독)
azqr scan --output-format json --output-file ~/azqr-$(date +%Y%m%d).json

# 또는 MCP 도구 사용
# mcp__azure__extension_azqr 으로 위와 동등한 스캔 가능
```

`azqr`는 Microsoft 비공식이지만 매우 신뢰받는 스캐너 — 결과를 그대로 사용자에게 보여주지 말고, **위험도별로 재정리**해서 제시.

## 워크플로우

### Phase 0: 범위 정의
사용자에게 다음을 확인:
- **대상 범위**: 구독 전체 / 특정 RG / 특정 리소스
- **점검 깊이**: 빠른 점검(공개 노출만) / 종합(7개 도메인 전체)
- **출력 형식**: 요약 보고 / CSV / JSON

### Phase 1: 신호 수집 (병렬)
가능한 한 병렬로 실행해 시간 단축:
- Resource Graph 쿼리 (공개 노출, NSG, 암호화 정책)
- `az security` (Defender 점수·권장사항)
- `azqr` 또는 `mcp__azure__extension_azqr` (있다면)
- Key Vault·RBAC 개별 호출

### Phase 2: 위험도 산정
각 발견 항목에 다음 척도 적용:

| 위험도 | 기준 | 예시 |
|---|---|---|
| 🔴 Critical | 즉시 인터넷에서 악용 가능 | NSG 0.0.0.0/0 SSH, public Storage with key |
| 🟠 High | 권한 상승·데이터 유출 가능 | Owner를 가진 SP, 만료된 KV 시크릿 활성, public SQL |
| 🟡 Medium | 컴플라이언스 위반·간접 위험 | TLS 1.0, Diagnostic 미설정, Soft Delete 미활성 |
| 🟢 Low | 모범 사례 미준수 | 태그 누락, 권장 SKU 미적용 |

### Phase 3: 보고서 작성

```
## 🛡️ Azure 보안 자세 점검

**범위**: <구독명> / <RG>
**점검 일시**: 2026-04-25 15:30 KST
**Defender Secure Score**: 67% (1340/2000)
**총 발견 사항**: 47건 (🔴 4 / 🟠 12 / 🟡 23 / 🟢 8)

### 🔴 Critical (4건) — 즉시 조치 필요

#### 1. NSG 0.0.0.0/0 → SSH (22) 노출
- **리소스**: `nsg-vm-prod-001` (rg-prod, koreacentral)
- **규칙**: `Allow_SSH_Anywhere`
- **연결된 NIC**: 3개 (VM `vm-app-001`, `vm-app-002`, `vm-bastion`)
- **권장 조치**:
  - SSH는 Azure Bastion 또는 Just-in-Time VM Access로 전환
  - 아니라면 source를 회사 IP 대역으로 제한
  - 명령 예시 (참고만, 실행은 사용자 또는 `resource-deploy` 위임):
    ```bash
    az network nsg rule update -g rg-prod --nsg-name nsg-vm-prod-001 \
      -n Allow_SSH_Anywhere --source-address-prefixes <YOUR-CIDR>
    ```

#### 2. Storage Account 익명 Blob 공개
- **리소스**: `stproddata001`
- **위험**: 컨테이너 `public-uploads`가 Public access level=Container
- **권장**: `allowBlobPublicAccess=false` 설정 또는 Private Endpoint 도입
...

### 🟠 High (12건) — 1주 내 조치
| # | 카테고리 | 리소스 | 내용 |
|---|---|---|---|
| 1 | RBAC | sp-deploy-bot | 구독 Owner — 최소 Contributor로 강등 검토 |
| 2 | Key Vault | kv-shared-prod | Purge Protection 미활성 |
| ... | ... | ... | ... |

### 🟡 Medium (23건) / 🟢 Low (8건)
요약만 제공, 상세는 사용자 요청 시 출력.

### 📊 카테고리별 위험 분포
- Network exposure: 11건
- IAM/RBAC: 8건
- Data protection: 14건
- Identity & Secrets: 9건
- Logging/Diagnostic: 5건

### 🎯 권장 로드맵
- **이번 주**: Critical 4건 모두 처리 + High 중 RBAC 3건
- **이번 분기**: Defender 권장사항 Top 20 처리 → Secure Score +15% 예상
- **상시**: `azqr` 월간 정기 스캔, Action Group으로 신규 Critical 발견 시 알림

### 참고
- 결과는 정책 적용 시점 기준 — 일부 거짓 양성 가능
- 실제 조치 실행은 `resource-deploy` 또는 `policy-author` 스킬에 위임
- 포괄 감사는 `azure-security-auditor` 에이전트 활용
```

## 다른 컴포넌트로 위임
- 위반 항목 자동 수정 정책(Azure Policy 정의·할당) → `policy-author` 스킬 (없다면 사용자에게 추가 권장)
- 권한 회수·NSG 규칙 변경 실행 → `resource-deploy` 스킬
- 기준선과 현재 비교(거버넌스 컨벤션) → `governance-check` 스킬
- 60일 진행형·다리포트 감사 → `azure-security-auditor` 에이전트

## 점검 깊이 옵션

| 모드 | 소요 시간 | 커버 |
|---|---|---|
| **quick** | 30초 | 공개 노출만 (Resource Graph 1회) |
| **standard** | 2분 | quick + Defender 권장사항 + Key Vault |
| **deep** | 10분+ | standard + RBAC 전수 + azqr 통합 + 데이터 보호 |

기본값은 **standard**. 사용자 명시 시 변경.

## 참고 자료
- Defender for Cloud: https://learn.microsoft.com/azure/defender-for-cloud/
- Azure Quick Review (azqr): https://github.com/Azure/azqr
- Microsoft Cloud Security Benchmark: https://learn.microsoft.com/security/benchmark/azure/
- Azure Policy 보안 기준: https://learn.microsoft.com/azure/governance/policy/samples/
