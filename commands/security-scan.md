Azure 환경의 빠른 보안 자세 점검을 실행합니다.

사용자가 제공한 인자(`$ARGUMENTS`)를 다음 중 하나로 해석:
- `quick` (기본) — 공개 노출만 30초 스캔
- `standard` — 공개 노출 + Defender + Key Vault (~2분)
- `deep` — 전 도메인 + azqr + RBAC 전수 (~10분)
- 리소스 ID/이름 — 해당 리소스에 한정한 점검

인자가 없으면 `quick`으로 실행하고, 결과 끝에 `standard` / `deep` 안내.

## 실행 절차

### 1. 인증 + 활성 구독 확인
```bash
az account show --query "{name:name, id:id}" -o table || { echo "az login 필요"; exit 1; }
```

### 2. 도메인별 병렬 점검

**A. 공개 노출 NSG (모든 모드)**
```bash
az graph query -q "resources
| where type =~ 'microsoft.network/networksecuritygroups'
| mv-expand rule = properties.securityRules
| where rule.properties.access == 'Allow'
| where rule.properties.direction == 'Inbound'
| where rule.properties.sourceAddressPrefix in ('*', '0.0.0.0/0', 'Internet')
| extend port = tostring(rule.properties.destinationPortRange)
| where port in ('22','3389','*','5985','5986','1433','3306','5432','27017','6379')
| project nsg=name, rg=resourceGroup, ruleName=tostring(rule.name), port, src=tostring(rule.properties.sourceAddressPrefix)
| limit 100" --output json
```

**B. 공개 Storage / SQL / Key Vault (모든 모드)**
```bash
az graph query -q "resources
| where type in~ ('microsoft.storage/storageaccounts','microsoft.sql/servers','microsoft.keyvault/vaults','microsoft.documentdb/databaseaccounts','microsoft.cache/redis')
| where properties.publicNetworkAccess == 'Enabled' or properties.allowBlobPublicAccess == true
| project name, type, rg=resourceGroup,
          publicNetworkAccess=tostring(properties.publicNetworkAccess),
          allowBlobPublicAccess=tobool(properties.allowBlobPublicAccess)
| limit 200" --output json
```

**C. Defender Secure Score (standard, deep)**
```bash
az security secure-scores list --query "[].{name:name, percentage:properties.score.percentage}" -o table 2>/dev/null
```

**D. Defender 미준수 권장사항 Top 20 (standard, deep)**
```bash
az security assessment list --query "[?properties.status.code=='Unhealthy'] | [0:20].{severity:metadata.severity, name:displayName, resource:resourceDetails.id}" -o json 2>/dev/null
```

**E. Key Vault 위생 (standard, deep)**
```bash
for v in $(az keyvault list --query "[].name" -o tsv); do
  az keyvault show -n "$v" --query "{name:name, softDelete:properties.enableSoftDelete, purgeProtection:properties.enablePurgeProtection, publicAccess:properties.publicNetworkAccess}" -o json
done
```

**F. RBAC Owner 보유자 (deep)**
```bash
az role assignment list --role "Owner" --scope "/subscriptions/$(az account show --query id -o tsv)" \
  --query "[].{principalName:principalName, type:principalType}" -o table
```

**G. azqr 통합 스캔 (deep, 사용 가능 시)**
```bash
if command -v azqr >/dev/null 2>&1; then
  azqr scan --output-format json --output-file /tmp/azqr-$(date +%Y%m%d-%H%M).json
  echo "결과: /tmp/azqr-*.json"
else
  echo "azqr 미설치 — 'mcp__azure__extension_cli_install' 으로 설치 안내 가능"
fi
```

## 결과 보고

위험도 ↓ 순으로 다음 형식 출력:

```
## 🛡️ 보안 자세 1차 점검

**구독**: <name>
**모드**: <quick|standard|deep>
**점검 시각**: <KST>
**Defender Secure Score**: XX% (standard 이상)

### 🔴 Critical
- NSG `<name>` (rg `<rg>`): 0.0.0.0/0 → port <p> 허용
- Storage `<name>`: allowBlobPublicAccess=true
- ...

### 🟠 High
| 카테고리 | 리소스 | 내용 |
|---|---|---|
| ... | ... | ... |

### 🟡 Medium / 🟢 Low
- 요약만 — 상세는 "더 보여줘" 요청 시 출력

### 📋 권장 다음 단계
- 깊은 분석: `security-posture` 스킬 호출 또는 `/security-scan deep`
- 종합 감사 보고서: `azure-security-auditor` 에이전트 위임 ("MCSB 기준으로 감사해줘")
- 시정 실행: `resource-deploy` 스킬 (사용자 승인 필수)
```

## 안전 원칙
- **읽기 전용** — 어떤 리소스도 수정 금지
- 시크릿/키/SAS token 출력 시 `***REDACTED***` 마스킹
- "공개 노출" 결과는 거짓 양성 가능 — Private Endpoint·Firewall 조합으로 실제로는 차단되어 있을 수 있음을 사용자에게 명시
- `deep` 모드는 시간이 오래 걸리므로 사용자에게 진행 상황 중간 보고
